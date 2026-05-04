defmodule UltistatsWeb.GameLive.Show do
  @moduledoc """
  Live game tracker — the per-point loop with per-throw event capture.
  Conforms to `docs/UI_DESIGN.md` and `docs/MVP_SPEC.md` step 4.

  Render branches off two pieces of state:

    * `current_point != nil`  in-point view (passer/receiver/outcome flow)
    * otherwise               between-points line picker

  In-point view modes:

    * `possession == :ours`   current-passer card + on-field roster as
                              receiver candidates + outcome buttons
                              (Catch / Drop / Goal / Throwaway / Stall).
    * `possession == :theirs` Block / They turned it over / They scored.

  Calls (Pick / Foul) are always available and never change possession.

  When the game is `:finished` (either pre-existing on mount or auto-ended
  by a hard-cap goal), we `push_navigate` to `/games/:id/summary` rather
  than render a terminal placeholder here — the summary screen owns the
  post-game UX (`docs/MVP_SPEC.md` step 6).
  """
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Repo, Teams}
  alias Ultistats.Accounts.User
  alias Ultistats.Games.{Event, Point}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game = Games.get_game!(id)
    user = socket.assigns.current_scope.user

    cond do
      not Teams.user_member_of?(user, game.team_id) ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have permission to view that game.")
         |> push_navigate(to: ~p"/games")}

      true ->
        do_mount_game(socket, game)
    end
  end

  defp do_mount_game(socket, game) do
    if game.status == :finished do
      {:ok,
       socket
       |> assign(:page_title, "Game vs #{game.opponent_name}")
       |> assign(:game, game)
       |> push_navigate(to: ~p"/games/#{game.id}/summary")}
    else
      team_players = Teams.list_players_for_team(game.team_id)
      line_presets = Teams.list_line_presets_for_team(game.team_id)
      current_point = Games.current_point(game)
      points_count = Games.points_count(game)
      valid_user_ids = team_players |> Enum.map(& &1.user_id) |> MapSet.new()

      # Fresh-game fast path: with zero points and no in-progress point,
      # every score/stoppage/points-played query is guaranteed empty. Skip
      # them so the mount that follows `Start game` doesn't pay 5+
      # round-trips for known-zero answers.
      fresh? = points_count == 0 and is_nil(current_point)

      score = if fresh?, do: %{ours: 0, theirs: 0}, else: Games.score(game)
      events = if current_point, do: Games.events_for_point(current_point), else: []
      possession = if current_point, do: derive_possession(game, current_point, events), else: nil

      %{halftime_recorded?: halftime_recorded?, timeouts_remaining: timeouts_remaining} =
        if fresh? do
          %{halftime_recorded?: false, timeouts_remaining: Games.timeouts_per_half(game)}
        else
          Games.stoppage_state(game)
        end

      socket =
        socket
        |> assign(:page_title, "Game vs #{game.opponent_name}")
        |> assign(:game, game)
        |> assign(:team_players, team_players)
        |> assign(:valid_user_ids, valid_user_ids)
        |> assign(:line_presets, line_presets)
        |> assign(:current_point, current_point)
        |> assign(:points_count, points_count)
        |> assign(:score, score)
        |> assign(:events, events)
        |> assign(:possession, possession)
        |> assign(:selected_user_ids, MapSet.new())
        |> assign(:selected_preset_id, nil)
        |> assign(:current_passer_id, nil)
        |> assign(:undo_stack, [])
        |> assign(:redo_stack, [])
        |> assign(:last_ended, nil)
        |> assign(:throwaway_prompt, nil)
        |> assign(:halftime_dismissed?, false)
        # Disconnect-driven button-disable is wired via JS hook in a later
        # task; assigns stays at false until the hook lands. The flash
        # banner from `Layouts.flash_group/1` already covers visual feedback.
        |> assign(:disconnected?, false)
        |> assign(:line_picker_sort, :jersey)
        |> assign(:split_by_position?, false)
        |> assign(:timeout_active?, false)
        |> assign(:halftime_active?, false)
        |> assign(:halftime_recorded?, halftime_recorded?)
        |> assign(:timeouts_remaining, timeouts_remaining)
        |> assign(:call_prompt, nil)

      {:ok, assign_line_picker_state(socket)}
    end
  end

  # Refreshes everything the between-points line picker reads:
  #   * `:next_point_sequence`            — 1-based number of the upcoming point.
  #   * `:required_ratio`                 — %{m, f} map or nil from the ruleset.
  #   * `:starting_possession_preview`    — :ours / :theirs (O-line vs D-line).
  #   * `:ratio_violation`                — nil, or %{actual:, required:} on mismatch.
  # Called from mount + every state transition that flips between
  # in-point and between-points OR changes selection.
  defp assign_line_picker_state(socket) do
    socket
    |> assign_line_picker_game_state()
    |> assign_line_picker_selection_state()
  end

  # Game-state-derived picker assigns. These hit the DB
  # (`points_played_by_user`, `starting_possession_for_next_point`) so we
  # only refresh them when the underlying game state changed (mount,
  # start/cancel point, goal, undo/redo, resume from stoppage). Toggling
  # which players are selected does NOT need this.
  defp assign_line_picker_game_state(socket) do
    game = socket.assigns.game
    points_count = points_count(socket)
    next_seq = points_count + 1
    required = Games.required_ratio_for_point(game, next_seq)
    required_line_size = Games.line_size_for(game)

    {starting, points_played} =
      if points_count == 0 do
        # Fresh game: no points exist, so the next point is point 1.
        # `starting_possession` is purely derived from `game.first_pull`,
        # and nobody has played yet.
        {Games.starting_possession(game, %Point{sequence: 1}), %{}}
      else
        {Games.starting_possession_for_next_point(game), Games.points_played_by_user(game)}
      end

    socket
    |> assign(:next_point_sequence, next_seq)
    |> assign(:required_ratio, required)
    |> assign(:starting_possession_preview, starting)
    |> assign(:required_line_size, required_line_size)
    |> assign(:points_played_by_user, points_played)
  end

  # In-process refresh of the picker assigns immediately after a point
  # ends. `points_played_by_user` is bumped from the ended point's
  # snapshot, and `starting_possession_preview` is the opposite of
  # whoever just scored — both pure computations, zero DB queries.
  defp assign_line_picker_game_state_after_point(socket, %Point{} = ended_point, scoring_team) do
    game = socket.assigns.game
    next_seq = (socket.assigns[:points_count] || 0) + 1
    required = Games.required_ratio_for_point(game, next_seq)
    required_line_size = Games.line_size_for(game)

    starting =
      case scoring_team do
        :ours -> :theirs
        :theirs -> :ours
      end

    user_ids = ended_point.our_line_snapshot |> Map.get("user_ids", [])

    points_played =
      Enum.reduce(
        user_ids,
        socket.assigns[:points_played_by_user] || %{},
        fn uid, acc -> Map.update(acc, uid, 1, &(&1 + 1)) end
      )

    socket
    |> assign(:next_point_sequence, next_seq)
    |> assign(:required_ratio, required)
    |> assign(:starting_possession_preview, starting)
    |> assign(:required_line_size, required_line_size)
    |> assign(:points_played_by_user, points_played)
  end

  # Cached count from mount, fast-pathed for between-event renders. We
  # keep it in sync (re-fetch via `Games.points_count/1`) on the few
  # transitions that actually change the count (start_point,
  # cancel_current_point, goal scored, undo_last_goal).
  defp points_count(socket) do
    case socket.assigns[:points_count] do
      n when is_integer(n) -> n
      _ -> Games.points_count(socket.assigns.game)
    end
  end

  # Selection-derived picker assigns. Pure computation against current
  # selection + already-loaded `team_players` and the cached
  # `:required_ratio` / `:required_line_size`. Safe to call on every
  # toggle without a DB round-trip.
  defp assign_line_picker_selection_state(socket) do
    selected = selected_memberships(socket.assigns.team_players, socket.assigns.selected_user_ids)
    violation = Games.line_ratio_violation(selected, socket.assigns.required_ratio)

    line_size_violation =
      Games.line_size_violation(
        socket.assigns.selected_user_ids |> MapSet.to_list(),
        socket.assigns.required_line_size
      )

    socket
    |> assign(:ratio_violation, violation)
    |> assign(:line_size_violation, line_size_violation)
  end

  defp selected_memberships(team_players, selected_ids) do
    Enum.filter(team_players, &MapSet.member?(selected_ids, &1.user_id))
  end

  ## ---------------------------------------------------------------------
  ## render
  ## ---------------------------------------------------------------------

  @impl true
  def render(%{game: %{status: :finished}} = assigns) do
    # While push_navigate to /games/:id/summary is in flight, render a
    # tiny placeholder so the framework always has markup to mount.
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <p class="text-sm text-base-content/70 py-6">Loading summary…</p>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="game-show-root"
        phx-hook="HideNav"
        class={[
          "flex flex-col -mx-4 -mt-6 -mb-6 transition-[height] duration-200 motion-reduce:transition-none",
          surface_tint(@current_point, banner_state(@possession, @events))
        ]}
        style="height: calc(100dvh - var(--nav-offset, 0px) - env(safe-area-inset-bottom))"
      >
        <div class={[
          "border-b transition-colors duration-200 motion-reduce:transition-none",
          top_bar_classes(@current_point, banner_state(@possession, @events))
        ]}>
          <.compact_header
            game={@game}
            score={@score}
            current_point={@current_point}
            possession={@possession}
            banner_state={banner_state(@possession, @events)}
            halftime?={
              Games.halftime?(@game) and not @halftime_recorded? and
                not @halftime_dismissed? and not @halftime_active?
            }
            halftime_recorded?={@halftime_recorded?}
            undo_stack={@undo_stack}
            redo_stack={@redo_stack}
            last_ended={@last_ended}
          />
        </div>

        <%= cond do %>
          <% @timeout_active? -> %>
            <.timeout_overlay />
          <% @halftime_active? -> %>
            <.halftime_overlay score={@score} />
          <% @current_point -> %>
            <.in_point_view
              current_point={@current_point}
              team_players={@team_players}
              events={@events}
              possession={@possession}
              current_passer_id={@current_passer_id}
              throwaway_prompt={@throwaway_prompt}
              disconnected?={@disconnected?}
              call_prompt={@call_prompt}
              timeouts_remaining={@timeouts_remaining}
            />
          <% true -> %>
            <.between_points_view
              point_number={length_of_points(@game) + 1}
              line_presets={@line_presets}
              team_players={@team_players}
              selected_user_ids={@selected_user_ids}
              selected_preset_id={@selected_preset_id}
              required_ratio={@required_ratio}
              starting_possession_preview={@starting_possession_preview}
              ratio_violation={@ratio_violation}
              points_played_by_user={@points_played_by_user}
              sort={@line_picker_sort}
              split_by_position?={@split_by_position?}
              line_size_violation={@line_size_violation}
              halftime_recorded?={@halftime_recorded?}
              timeouts_remaining={@timeouts_remaining}
            />
        <% end %>

        <.bottom_action_bar
          :if={not @timeout_active? and not @halftime_active?}
          game={@game}
          current_point={@current_point}
          selected_user_ids={@selected_user_ids}
          team_players={@team_players}
          required_line_size={@required_line_size}
          disconnected?={@disconnected?}
        />
      </div>
    </Layouts.app>
    """
  end

  ## ---------------------------------------------------------------------
  ## sub-renderers
  ## ---------------------------------------------------------------------

  # Compact sticky header — single row carrying score + opponent +
  # possession pill + nav icons, with a discrete back-to-lineup chip
  # when in a point. Halftime banner stays as a one-time strip above it.
  attr :game, :map, required: true
  attr :score, :map, required: true
  attr :current_point, :any, required: true
  attr :possession, :any, required: true
  attr :banner_state, :any, required: true
  attr :halftime?, :boolean, required: true
  attr :halftime_recorded?, :boolean, required: true
  attr :undo_stack, :list, required: true
  attr :redo_stack, :list, required: true
  attr :last_ended, :any, required: true

  defp compact_header(assigns) do
    ~H"""
    <div
      :if={@current_point}
      class={[
        "py-1 text-center text-xs font-semibold uppercase tracking-wide",
        possession_banner_classes(@banner_state)
      ]}
    >
      {possession_banner_label(@banner_state)}
    </div>

    <div :if={@halftime?} class="px-4 pt-2">
      <div
        role="status"
        class="flex items-center gap-2 rounded-md bg-warning text-warning-content px-2 py-1.5 text-xs"
      >
        <.icon name="hero-flag-solid" class="size-4 shrink-0" />
        <span class="flex-1 font-semibold tabular-nums">
          Halftime — {@score.ours}–{@score.theirs}
        </span>
        <button
          type="button"
          phx-click="dismiss_halftime"
          aria-label="Dismiss halftime banner"
          class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md active:bg-warning-content/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>

    <div class="flex items-center justify-between gap-2 px-4 py-2">
      <div class="flex items-center gap-1 shrink-0">
        <button
          :if={@current_point}
          type="button"
          phx-click={if @undo_stack == [], do: "cancel_current_point", else: "undo"}
          data-confirm={
            if @undo_stack == [],
              do: "You will lose all progress for this point if you go back.",
              else: nil
          }
          aria-label={
            if @undo_stack == [], do: "Back to lineup (cancel point)", else: "Undo last event"
          }
          class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-arrow-uturn-left" class="size-4" />
        </button>
        <button
          :if={@current_point}
          type="button"
          phx-click="redo"
          disabled={@redo_stack == []}
          aria-label="Redo"
          class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-30 disabled:cursor-not-allowed"
        >
          <.icon name="hero-arrow-uturn-right" class="size-4" />
        </button>
        <button
          :if={is_nil(@current_point) and not is_nil(@last_ended)}
          type="button"
          phx-click="undo_last_goal"
          aria-label="Undo last goal"
          class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-arrow-uturn-left" class="size-4" />
        </button>
      </div>

      <div class="flex items-baseline gap-1.5 min-w-0 flex-1">
        <span
          class="tabular-nums font-bold text-2xl leading-none"
          aria-label={"Our score #{@score.ours}"}
        >
          {@score.ours}
        </span>
        <span class="text-base text-base-content/40 leading-none" aria-hidden="true">–</span>
        <span
          class="tabular-nums font-bold text-2xl leading-none"
          aria-label={"Opponent score #{@score.theirs}"}
        >
          {@score.theirs}
        </span>
        <span class="text-xs text-base-content/60 truncate ml-1">vs {@game.opponent_name}</span>
        <span class="ml-1 inline-flex items-center rounded-full bg-base-200 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-base-content/70 shrink-0">
          {if @halftime_recorded?, do: "Half 2", else: "Half 1"}
        </span>
      </div>

      <span :if={@current_point} class="sr-only" aria-live="polite">
        {possession_label(@possession)}
      </span>

      <div class="flex items-center gap-1 shrink-0">
        <.link
          navigate={~p"/games/#{@game.id}/summary"}
          aria-label="Open game summary"
          class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-chart-bar" class="size-4" />
        </.link>
        <.link
          navigate={~p"/games/#{@game.id}/timeline"}
          aria-label="Open timeline"
          class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-list-bullet" class="size-4" />
        </.link>
        <.link
          :if={@game.ruleset_id}
          navigate={~p"/rulesets/#{@game.ruleset_id}"}
          aria-label="View ruleset"
          class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-document-text" class="size-4" />
        </.link>
      </div>
    </div>
    """
  end

  attr :point_number, :integer, required: true
  attr :line_presets, :list, required: true
  attr :team_players, :list, required: true
  attr :selected_user_ids, :any, required: true
  attr :selected_preset_id, :any, required: true
  attr :required_ratio, :any, required: true
  attr :starting_possession_preview, :atom, required: true
  attr :ratio_violation, :any, required: true
  attr :points_played_by_user, :map, required: true
  attr :sort, :atom, required: true
  attr :split_by_position?, :boolean, required: true
  attr :line_size_violation, :any, required: true
  attr :halftime_recorded?, :boolean, required: true
  attr :timeouts_remaining, :integer, required: true

  defp between_points_view(assigns) do
    ~H"""
    <section
      class="flex-1 min-h-0 flex flex-col gap-2 px-4 py-3 overflow-hidden"
      aria-label="Line picker"
    >
      <div
        class={[
          "-mx-4 flex items-center gap-2 px-4 py-1.5 text-xs font-semibold",
          starting_possession_banner_classes(@starting_possession_preview)
        ]}
        role="status"
      >
        <.icon name={starting_possession_icon(@starting_possession_preview)} class="size-4 shrink-0" />
        <span>{starting_possession_label(@starting_possession_preview)}</span>
      </div>

      <details :if={@line_presets != []} class="group">
        <summary class={[
          "min-h-9 list-none cursor-pointer inline-flex w-full items-center gap-2 px-2.5 py-1",
          "rounded-md border border-base-300 bg-base-100 text-xs font-medium",
          "active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        ]}>
          <.icon name="hero-list-bullet" class="size-3.5 shrink-0" />
          <span class="truncate flex-1 text-left">
            {preset_summary_label(@line_presets, @selected_preset_id)}
          </span>
          <.icon
            name="hero-chevron-down"
            class="size-3.5 shrink-0 transition-transform group-open:rotate-180 motion-reduce:transition-none"
          />
        </summary>
        <ul class="mt-1 rounded-md border border-base-300 bg-base-100 divide-y divide-base-200 overflow-hidden">
          <li>
            <button
              type="button"
              phx-click="clear_preset"
              aria-pressed={to_string(is_nil(@selected_preset_id))}
              class={[
                "w-full min-h-9 px-3 py-1 flex items-center gap-2 text-left text-xs italic",
                "active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                if(is_nil(@selected_preset_id), do: "bg-primary/10 font-semibold", else: "")
              ]}
            >
              <span class="flex-1 truncate text-base-content/70">None</span>
              <.icon
                :if={is_nil(@selected_preset_id)}
                name="hero-check-circle-solid"
                class="size-3.5 text-primary shrink-0"
              />
            </button>
          </li>
          <li :for={preset <- @line_presets}>
            <button
              type="button"
              phx-click="select_preset"
              phx-value-id={preset.id}
              aria-pressed={to_string(@selected_preset_id == preset.id)}
              class={[
                "w-full min-h-9 px-3 py-1 flex items-center gap-2 text-left text-xs",
                "active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                if(@selected_preset_id == preset.id, do: "bg-primary/10 font-semibold", else: "")
              ]}
            >
              <span class="flex-1 truncate">{preset.name}</span>
              <span class="tabular-nums text-[11px] text-base-content/60">
                {length(preset.users)}
              </span>
              <.icon
                :if={@selected_preset_id == preset.id}
                name="hero-check-circle-solid"
                class="size-3.5 text-primary shrink-0"
              />
            </button>
          </li>
        </ul>
      </details>

      <%= if @team_players == [] do %>
        <div class="rounded-lg border-2 border-dashed border-base-300 p-6 text-center">
          <p class="text-base font-medium">No players on this team yet.</p>
          <p class="text-sm text-base-content/70 mt-1">
            Add players to the team's roster to start tracking points.
          </p>
        </div>
      <% else %>
        <.line_picker_sort_control sort={@sort} split_by_position?={@split_by_position?} />

        <div id="game-line-picker" class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden space-y-4">
          <.line_picker_section
            :for={role <- [:male_matching, :female_matching]}
            :if={Enum.any?(@team_players, &(&1.user.gender_role == role))}
            role={role}
            players={Enum.filter(@team_players, &(&1.user.gender_role == role))}
            selected_ids={@selected_user_ids}
            points_played_by_user={@points_played_by_user}
            sort={@sort}
            split_by_position?={@split_by_position?}
          />
        </div>
      <% end %>

      <.stoppages_bar
        disconnected?={false}
        show_halftime?={true}
        show_finish_game?={true}
        halftime_recorded?={@halftime_recorded?}
        timeouts_remaining={@timeouts_remaining}
      />
    </section>
    """
  end

  defp timeout_overlay(assigns) do
    ~H"""
    <section
      class="flex-1 min-h-0 flex flex-col items-center justify-center gap-6 px-4 py-6 bg-base-200"
      aria-label="Timeout in progress"
    >
      <div class="flex flex-col items-center gap-2 text-center">
        <.icon name="hero-pause-circle-solid" class="size-16 text-base-content/40" />
        <h2 class="text-xl font-semibold">Timeout</h2>
        <p class="text-sm text-base-content/70">Tap resume when play continues.</p>
      </div>
      <button
        type="button"
        phx-click="resume_game"
        class={[
          "min-h-12 px-6 rounded-xl bg-primary text-primary-content",
          "inline-flex items-center justify-center gap-2 text-base font-semibold",
          "active:scale-[0.99] motion-reduce:active:scale-100",
          "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        ]}
      >
        <.icon name="hero-play" class="size-5" />
        <span>Resume game</span>
      </button>
    </section>
    """
  end

  attr :score, :map, required: true

  defp halftime_overlay(assigns) do
    ~H"""
    <section
      class="flex-1 min-h-0 flex flex-col items-center justify-center gap-6 px-4 py-6 bg-base-200"
      aria-label="Halftime in progress"
    >
      <div class="flex flex-col items-center gap-2 text-center">
        <.icon name="hero-flag-solid" class="size-16 text-warning" />
        <h2 class="text-xl font-semibold">Halftime</h2>
        <p class="tabular-nums text-base-content/70">
          {@score.ours}–{@score.theirs}
        </p>
        <p class="text-sm text-base-content/70">Tap resume when the second half starts.</p>
      </div>
      <button
        type="button"
        phx-click="resume_game"
        class={[
          "min-h-12 px-6 rounded-xl bg-primary text-primary-content",
          "inline-flex items-center justify-center gap-2 text-base font-semibold",
          "active:scale-[0.99] motion-reduce:active:scale-100",
          "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        ]}
      >
        <.icon name="hero-play" class="size-5" />
        <span>Resume game</span>
      </button>
    </section>
    """
  end

  attr :sort, :atom, required: true
  attr :split_by_position?, :boolean, required: true

  defp line_picker_sort_control(assigns) do
    ~H"""
    <div class="flex items-center gap-2 flex-wrap text-[11px]">
      <div
        class="flex items-center gap-1"
        role="radiogroup"
        aria-label="Sort players"
      >
        <span class="text-base-content/60 uppercase tracking-wide font-semibold mr-1">Sort</span>
        <button
          :for={
            {key, label} <- [
              {:jersey, "#"},
              {:name, "Name"},
              {:points, "Playtime"}
            ]
          }
          type="button"
          phx-click="change_sort"
          phx-value-sort={Atom.to_string(key)}
          role="radio"
          aria-checked={to_string(@sort == key)}
          class={[
            "min-h-7 px-2 inline-flex items-center rounded-md font-medium",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            if(@sort == key,
              do: "bg-primary text-primary-content",
              else: "bg-base-200 text-base-content/70 active:bg-base-300"
            )
          ]}
        >
          {label}
        </button>
      </div>

      <label class="ml-auto inline-flex items-center gap-1.5 cursor-pointer">
        <input
          type="checkbox"
          phx-click="toggle_split_by_position"
          checked={@split_by_position?}
          class="checkbox checkbox-xs checkbox-primary"
        />
        <span class="text-base-content/70">Split by position</span>
      </label>
    </div>
    """
  end

  attr :current_point, :map, required: true
  attr :team_players, :list, required: true
  attr :events, :list, required: true
  attr :possession, :atom, required: true
  attr :current_passer_id, :any, required: true
  attr :disconnected?, :boolean, required: true
  attr :throwaway_prompt, :any, required: true
  attr :call_prompt, :any, required: true
  attr :timeouts_remaining, :integer, required: true

  defp in_point_view(assigns) do
    line_user_ids = line_user_ids(assigns.current_point)
    on_field = Enum.filter(assigns.team_players, &(&1.user_id in line_user_ids))
    player_lookup = Map.new(assigns.team_players, &{&1.user_id, &1})

    assigns =
      assigns
      |> assign(:on_field, on_field)
      |> assign(:player_lookup, player_lookup)

    ~H"""
    <section
      class="flex-1 min-h-0 px-4 py-2 space-y-2 overflow-hidden"
      aria-label="Current point"
    >
      <%= if @possession == :ours do %>
        <.our_possession_view
          on_field={@on_field}
          player_lookup={@player_lookup}
          current_passer_id={@current_passer_id}
          throwaway_prompt={@throwaway_prompt}
          disconnected?={@disconnected?}
        />
      <% else %>
        <.their_possession_view
          on_field={@on_field}
          pull_pending?={@events == []}
          disconnected?={@disconnected?}
        />
      <% end %>

      <.calls_bar
        disconnected?={@disconnected?}
        call_prompt={@call_prompt}
        timeouts_remaining={@timeouts_remaining}
      />
    </section>
    """
  end

  attr :on_field, :list, required: true
  attr :player_lookup, :map, required: true
  attr :current_passer_id, :any, required: true
  attr :throwaway_prompt, :any, required: true
  attr :disconnected?, :boolean, required: true

  defp our_possession_view(assigns) do
    passer_set? = not is_nil(assigns.current_passer_id)
    assigns = assign(assigns, :passer_set?, passer_set?)

    ~H"""
    <div class="space-y-2">
      <h3 class="text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
        Actions from our team
      </h3>

      <.current_passer_card
        current_passer_id={@current_passer_id}
        player_lookup={@player_lookup}
        pending_throwaway?={not is_nil(@throwaway_prompt)}
      />

      <.throwaway_prompt_strip
        :if={@throwaway_prompt}
        prompt={@throwaway_prompt}
        current_passer_id={@current_passer_id}
        player_lookup={@player_lookup}
      />

      <p :if={not @passer_set?} class="text-xs text-base-content/70" aria-live="polite">
        Tap who has the disc.
      </p>

      <.action_legend variant={:ours} />

      <.action_player_grid
        on_field={@on_field}
        passer_set?={@passer_set?}
        current_passer_id={@current_passer_id}
        disconnected?={@disconnected?}
      />

      <button
        type="button"
        phx-click="record_throw_outcome"
        phx-value-type="stall"
        disabled={@disconnected? or not @passer_set?}
        aria-label="Record a stall"
        class={[
          "min-h-9 px-3 py-1 rounded-md border border-base-300",
          "inline-flex items-center justify-center gap-1.5",
          "text-sm font-semibold bg-base-100 text-base-content active:bg-base-200",
          "transition-colors motion-reduce:transition-none",
          "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
          "disabled:opacity-50 disabled:cursor-not-allowed"
        ]}
      >
        <.icon name="hero-clock" class="size-4" />
        <span>Stall</span>
      </button>
    </div>
    """
  end

  attr :on_field, :list, required: true
  attr :passer_set?, :boolean, required: true
  attr :current_passer_id, :any, required: true
  attr :disconnected?, :boolean, required: true

  defp action_player_grid(assigns) do
    ~H"""
    <ul
      class="-mx-4 border-y border-base-200 divide-y divide-base-200"
      role="list"
      aria-label="On-field players"
    >
      <li :for={member <- @on_field}>
        <.action_player_row
          player_id={member.user_id}
          jersey={Teams.resolved_jersey_number(member)}
          name={User.display_name(member.user)}
          passer_set?={@passer_set?}
          is_current_passer?={@current_passer_id == member.user_id}
          disconnected?={@disconnected?}
        />
      </li>

      <%!-- Unknown row — same buttons, records nil ids. --%>
      <li>
        <.action_player_row
          player_id={:unknown}
          jersey={nil}
          name="Unknown"
          passer_set?={@passer_set?}
          is_current_passer?={@current_passer_id == :unknown}
          disconnected?={@disconnected?}
          unknown?={true}
        />
      </li>
    </ul>
    """
  end

  attr :player_id, :any, required: true
  attr :jersey, :any, default: nil
  attr :name, :string, required: true
  attr :passer_set?, :boolean, required: true
  attr :is_current_passer?, :boolean, required: true
  attr :disconnected?, :boolean, required: true
  attr :unknown?, :boolean, default: false

  defp action_player_row(assigns) do
    ~H"""
    <div class={[
      "relative min-h-9 flex items-center gap-2 px-4 py-1",
      @unknown? && "italic",
      @is_current_passer? && "bg-success/15"
    ]}>
      <%!-- Full-row tap target for set_passer. Sits behind the
           jersey/name/action buttons so taps on those still hit the
           intended controls; bare row area falls through here. --%>
      <button
        type="button"
        phx-click="set_passer"
        phx-value-id={action_row_phx_value(@player_id)}
        disabled={@disconnected? or @passer_set?}
        aria-label={"Set #{@name} as current passer"}
        class={[
          "absolute inset-0 rounded-md",
          "focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-primary",
          "disabled:cursor-default"
        ]}
      >
      </button>

      <span
        :if={@jersey}
        class="relative tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0 pointer-events-none"
        aria-hidden="true"
      >
        {@jersey}
      </span>
      <span
        :if={@unknown?}
        class="relative inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-xs shrink-0 pointer-events-none"
        aria-hidden="true"
      >
        ?
      </span>
      <span class="relative font-medium text-sm truncate flex-1 leading-tight pointer-events-none">
        {@name}
      </span>

      <div class="relative flex items-center gap-1 shrink-0">
        <button
          type="button"
          phx-click="record_throw_for_player"
          phx-value-player-id={action_row_phx_value(@player_id)}
          phx-value-type="catch"
          disabled={
            @disconnected? or not @passer_set? or
              (@is_current_passer? and not @unknown?)
          }
          aria-label={"Record catch by #{@name}"}
          class={action_row_button_classes(:catch)}
        >
          <.icon name="hero-check" class="size-3.5" />
          <span class="text-[10px] font-bold leading-none">C</span>
        </button>
        <button
          type="button"
          phx-click="record_throw_for_player"
          phx-value-player-id={action_row_phx_value(@player_id)}
          phx-value-type="drop"
          disabled={
            @disconnected? or not @passer_set? or
              (@is_current_passer? and not @unknown?)
          }
          aria-label={"Record drop by #{@name}"}
          class={action_row_button_classes(:drop)}
        >
          <.icon name="hero-arrow-down-tray" class="size-3.5" />
          <span class="text-[10px] font-bold leading-none">D</span>
        </button>
        <button
          type="button"
          phx-click="prompt_throwaway"
          phx-value-player-id={action_row_phx_value(@player_id)}
          disabled={@disconnected? or not @passer_set?}
          aria-label={"Disambiguate turnover involving #{@name}"}
          class={action_row_button_classes(:throwaway)}
        >
          <.icon name="hero-arrow-path-rounded-square" class="size-3.5" />
          <span class="text-[10px] font-bold leading-none">T</span>
        </button>
        <button
          type="button"
          phx-click="record_throw_for_player"
          phx-value-player-id={action_row_phx_value(@player_id)}
          phx-value-type="goal"
          disabled={
            @disconnected? or not @passer_set? or
              (@is_current_passer? and not @unknown?)
          }
          aria-label={"Record goal by #{@name}"}
          class={action_row_button_classes(:goal)}
        >
          <.icon name="hero-trophy" class="size-3.5" />
          <span class="text-[10px] font-bold leading-none">G</span>
        </button>
      </div>
    </div>
    """
  end

  attr :prompt, :map, required: true
  attr :current_passer_id, :any, required: true
  attr :player_lookup, :map, required: true

  defp throwaway_prompt_strip(assigns) do
    passer_label = passer_card_label(assigns.current_passer_id, assigns.player_lookup)

    assigns = assign(assigns, :passer_label, passer_label)

    ~H"""
    <div class="space-y-1.5" role="dialog" aria-label="Disambiguate turnover">
      <div class="flex items-center gap-2 text-xs font-medium text-base-content/70">
        <span class="flex-1">What happened?</span>
        <button
          type="button"
          phx-click="cancel_throwaway"
          aria-label="Cancel"
          class="min-h-7 min-w-7 inline-flex items-center justify-center rounded-md text-base-content/60 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <div class="grid grid-cols-3 gap-1.5">
        <button
          type="button"
          phx-click="record_throw_for_player"
          phx-value-type="throwaway"
          class={turnover_action_classes()}
        >
          Throwaway
        </button>
        <button
          type="button"
          phx-click="record_throw_for_player"
          phx-value-type="throwaway"
          class={turnover_action_classes()}
        >
          Blocked
        </button>
        <button
          type="button"
          phx-click="record_throw_for_player"
          phx-value-type="throwaway"
          class={turnover_action_classes()}
        >
          Intercepted
        </button>
      </div>
    </div>
    """
  end

  defp turnover_action_classes do
    [
      "min-h-9 px-2 inline-flex items-center justify-center rounded-md text-xs font-semibold",
      "border border-error/60 bg-error text-error-content active:bg-error/80",
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    ]
  end

  attr :variant, :atom, required: true, values: [:ours, :theirs]

  defp action_legend(assigns) do
    ~H"""
    <div
      class="flex items-center flex-wrap gap-x-2 gap-y-1 text-[10px] text-base-content/60"
      aria-label="Action icons"
    >
      <span class="uppercase tracking-wide font-semibold text-base-content/50">Legend</span>
      <span :for={item <- legend_items(@variant)} class="inline-flex items-center gap-1">
        <span class={[
          "inline-flex items-center justify-center size-5 rounded-md",
          action_row_button_color(item.kind)
        ]}>
          <.icon name={item.icon} class="size-3" />
        </span>
        <span>{item.label}</span>
      </span>
    </div>
    """
  end

  defp legend_items(:ours) do
    [
      %{kind: :catch, icon: "hero-check", letter: "C", label: "Catch"},
      %{kind: :drop, icon: "hero-arrow-down-tray", letter: "D", label: "Drop"},
      %{
        kind: :throwaway,
        icon: "hero-arrow-path-rounded-square",
        letter: "T",
        label: "Turnover"
      },
      %{kind: :goal, icon: "hero-trophy", letter: "G", label: "Goal"}
    ]
  end

  defp legend_items(:theirs) do
    [
      %{kind: :catch, icon: "hero-shield-check", letter: "B", label: "Block"},
      %{kind: :throwaway, icon: "hero-arrows-right-left", letter: "I", label: "Intercept"}
    ]
  end

  defp action_row_phx_value(:unknown), do: "unknown"
  defp action_row_phx_value(id) when is_binary(id), do: id

  defp action_row_button_classes(kind) do
    [
      "min-h-9 min-w-9 px-1.5 inline-flex items-center justify-center gap-0.5 rounded-md",
      action_row_button_color(kind),
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
      "disabled:opacity-30 disabled:cursor-not-allowed"
    ]
  end

  defp action_row_button_color(:catch), do: "bg-success/10 text-success active:bg-success/20"
  defp action_row_button_color(:drop), do: "bg-error/10 text-error active:bg-error/20"

  # Turnover sits between the /10 alpha of its peers and the solid fill
  # tested earlier — bright enough to read as clearly enabled when the
  # C/D/G siblings fade to disabled-30%, but not so dark that it reads
  # as the dominant action on the row.
  defp action_row_button_color(:throwaway),
    do: "bg-warning/30 text-warning active:bg-warning/40"

  defp action_row_button_color(:goal), do: "bg-primary/10 text-primary active:bg-primary/20"

  attr :current_passer_id, :any, required: true
  attr :player_lookup, :map, required: true
  attr :pending_throwaway?, :boolean, default: false

  defp current_passer_card(assigns) do
    label = passer_card_label(assigns.current_passer_id, assigns.player_lookup)
    assigns = assign(assigns, :label, label)

    ~H"""
    <div
      :if={is_nil(@current_passer_id)}
      class="rounded-lg border-2 border-dashed border-base-300 px-3 py-2 text-center"
      aria-label="No current passer"
    >
      <p class="text-xs text-base-content/70 italic">Tap who has the disc</p>
    </div>

    <div
      :if={not is_nil(@current_passer_id)}
      class={[
        "rounded-lg px-3 py-2",
        if(@pending_throwaway?,
          do: "bg-warning/15 ring-2 ring-warning",
          else: "bg-success/15 ring-2 ring-success"
        )
      ]}
      aria-label={"Current passer: #{@label}"}
      data-current-passer={passer_data_id(@current_passer_id)}
    >
      <div class="flex items-center gap-2">
        <span
          class={[
            "tabular-nums font-semibold inline-flex items-center justify-center size-8 rounded-full text-sm",
            if(@pending_throwaway?,
              do: "bg-warning text-warning-content",
              else: "bg-success text-success-content"
            )
          ]}
          aria-hidden="true"
        >
          {passer_card_number(@current_passer_id, @player_lookup)}
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold truncate leading-tight">{@label}</p>
          <p class="text-[11px] text-base-content/70 leading-tight">
            <%= if @pending_throwaway? do %>
              has thrown it away
            <% else %>
              has the disc
            <% end %>
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :on_field, :list, required: true
  attr :pull_pending?, :boolean, default: false
  attr :disconnected?, :boolean, required: true

  defp their_possession_view(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= if @pull_pending? do %>
        <h3 class="text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
          Who pulled?
        </h3>

        <p class="text-xs text-base-content/70" aria-live="polite">
          Tap the player who pulled the disc.
        </p>

        <ul
          class="-mx-4 border-y border-base-200 divide-y divide-base-200"
          role="list"
          aria-label="On-field pullers"
        >
          <li :for={member <- @on_field}>
            <.pull_picker_row
              player_id={member.user_id}
              jersey={Teams.resolved_jersey_number(member)}
              name={User.display_name(member.user)}
              disconnected?={@disconnected?}
            />
          </li>
          <li>
            <.pull_picker_row
              player_id={:unknown}
              jersey={nil}
              name="Unknown"
              disconnected?={@disconnected?}
              unknown?={true}
            />
          </li>
        </ul>
      <% else %>
        <h3 class="text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
          Actions from our team
        </h3>

        <p class="text-xs text-base-content/70" aria-live="polite">
          Tap the action next to the defender who got the disc back.
        </p>

        <.action_legend variant={:theirs} />

        <ul
          class="-mx-4 border-y border-base-200 divide-y divide-base-200"
          role="list"
          aria-label="On-field defenders"
        >
          <li :for={member <- @on_field}>
            <.defender_action_row
              player_id={member.user_id}
              jersey={Teams.resolved_jersey_number(member)}
              name={User.display_name(member.user)}
              disconnected?={@disconnected?}
            />
          </li>
          <li>
            <.defender_action_row
              player_id={:unknown}
              jersey={nil}
              name="Unknown"
              disconnected?={@disconnected?}
              unknown?={true}
            />
          </li>
        </ul>
      <% end %>

      <h3 class="text-[11px] font-semibold uppercase tracking-wide text-base-content/60 pt-1">
        Actions from their team
      </h3>
      <div class="grid grid-cols-2 gap-2">
        <button
          type="button"
          phx-click="record_opponent_turnover"
          disabled={@disconnected?}
          aria-label="Record that the opponent turned the disc over"
          class={[
            "min-h-9 px-2 py-1 rounded-md border border-base-300",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold bg-base-100 text-base-content active:bg-base-200",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-arrow-uturn-right" class="size-4" />
          <span>Turnover</span>
        </button>
        <button
          type="button"
          phx-click="record_opponent_goal"
          disabled={@disconnected?}
          aria-label="Record that the opponent scored"
          class={[
            "min-h-9 px-2 py-1 rounded-md border border-base-300",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold bg-base-100 text-base-content active:bg-base-200",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-flag" class="size-4" />
          <span>Score</span>
        </button>
      </div>
    </div>
    """
  end

  attr :player_id, :any, required: true
  attr :jersey, :any, default: nil
  attr :name, :string, required: true
  attr :disconnected?, :boolean, required: true
  attr :unknown?, :boolean, default: false

  defp pull_picker_row(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="record_pull"
      phx-value-player-id={action_row_phx_value(@player_id)}
      disabled={@disconnected?}
      aria-label={"Record pull by #{@name}"}
      class={[
        "w-full min-h-9 px-4 py-1 flex items-center gap-2 text-left",
        "transition-colors motion-reduce:transition-none active:bg-base-200",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
        "disabled:opacity-50 disabled:cursor-not-allowed",
        @unknown? && "italic"
      ]}
    >
      <span
        :if={@jersey}
        class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0"
        aria-hidden="true"
      >
        {@jersey}
      </span>
      <span
        :if={@unknown?}
        class="inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-xs shrink-0"
        aria-hidden="true"
      >
        ?
      </span>
      <span class="font-medium text-sm truncate flex-1 leading-tight">{@name}</span>
      <.icon name="hero-paper-airplane" class="size-4 text-base-content/60 shrink-0" />
    </button>
    """
  end

  attr :player_id, :any, required: true
  attr :jersey, :any, default: nil
  attr :name, :string, required: true
  attr :disconnected?, :boolean, required: true
  attr :unknown?, :boolean, default: false

  defp defender_action_row(assigns) do
    ~H"""
    <div class={["min-h-9 flex items-center gap-2 px-4 py-1", @unknown? && "italic"]}>
      <span
        :if={@jersey}
        class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0"
        aria-hidden="true"
      >
        {@jersey}
      </span>
      <span
        :if={@unknown?}
        class="inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-xs shrink-0"
        aria-hidden="true"
      >
        ?
      </span>
      <span class="font-medium text-sm truncate flex-1 leading-tight">{@name}</span>
      <div class="flex items-center gap-1 shrink-0">
        <button
          type="button"
          phx-click="record_defense_for_player"
          phx-value-player-id={action_row_phx_value(@player_id)}
          phx-value-kind="block"
          disabled={@disconnected?}
          aria-label={"Record block by #{@name}"}
          class={action_row_button_classes(:catch)}
        >
          <.icon name="hero-shield-check" class="size-3.5" />
          <span class="text-[10px] font-bold leading-none">B</span>
        </button>
        <button
          type="button"
          phx-click="record_defense_for_player"
          phx-value-player-id={action_row_phx_value(@player_id)}
          phx-value-kind="catch"
          disabled={@disconnected?}
          aria-label={"Record interception by #{@name}"}
          class={action_row_button_classes(:throwaway)}
        >
          <.icon name="hero-arrows-right-left" class="size-3.5" />
          <span class="text-[10px] font-bold leading-none">I</span>
        </button>
      </div>
    </div>
    """
  end

  attr :prompt, :map, required: true

  defp call_resolution_strip(assigns) do
    actions = [
      {"back_to_thrower", "Back to thrower"},
      {"retract", "Retracted"},
      {"resume", "Resume"},
      {"turnover", "Turnover"}
    ]

    label =
      case assigns.prompt.type do
        :pick -> "Pick called — choose resolution"
        :foul -> "Foul called — choose resolution"
      end

    assigns = assign(assigns, actions: actions, label: label)

    ~H"""
    <div
      class="-mx-4 px-4 py-2 bg-warning/10 text-warning space-y-1"
      role="status"
    >
      <div class="flex items-center gap-2 text-xs font-semibold">
        <.icon name="hero-exclamation-triangle-solid" class="size-4 shrink-0" />
        <span class="flex-1">{@label}</span>
        <button
          type="button"
          phx-click="resolve_call"
          phx-value-action="cancel"
          aria-label="Cancel call"
          class="min-h-7 min-w-7 inline-flex items-center justify-center rounded-md text-warning active:bg-warning/20 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <div class="grid grid-cols-2 gap-2">
        <button
          :for={{action, label} <- @actions}
          type="button"
          phx-click="resolve_call"
          phx-value-action={action}
          class={[
            "min-h-9 px-2 py-1 rounded-md border",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            call_action_classes(action)
          ]}
        >
          {label}
        </button>
      </div>
    </div>
    """
  end

  defp call_action_classes("turnover"),
    do: "border-error/60 bg-error text-error-content active:bg-error/80"

  defp call_action_classes(_),
    do: "border-base-300 bg-base-200 text-base-content/80 active:bg-base-300"

  attr :disconnected?, :boolean, required: true
  attr :call_prompt, :any, required: true
  attr :timeouts_remaining, :integer, required: true

  defp calls_bar(assigns) do
    ~H"""
    <div class="space-y-2" aria-label="Calls">
      <.call_resolution_strip :if={@call_prompt} prompt={@call_prompt} />

      <div class="space-y-1">
        <h3 class="text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
          Calls
        </h3>
        <div class="grid grid-cols-2 gap-2">
          <button
            type="button"
            phx-click="record_call"
            phx-value-type="pick"
            disabled={@disconnected?}
            aria-label="Record a pick call"
            class={[
              "min-h-9 px-2 py-1 rounded-md border border-base-300",
              "inline-flex items-center justify-center gap-1.5",
              "text-sm font-semibold bg-base-100 text-base-content active:bg-base-200",
              "transition-colors motion-reduce:transition-none",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              "disabled:opacity-50 disabled:cursor-not-allowed"
            ]}
          >
            <.icon name="hero-hand-raised" class="size-4" />
            <span>Pick</span>
          </button>
          <button
            type="button"
            phx-click="record_call"
            phx-value-type="foul"
            disabled={@disconnected?}
            aria-label="Record a foul call"
            class={[
              "min-h-9 px-2 py-1 rounded-md border border-base-300",
              "inline-flex items-center justify-center gap-1.5",
              "text-sm font-semibold bg-base-100 text-base-content active:bg-base-200",
              "transition-colors motion-reduce:transition-none",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              "disabled:opacity-50 disabled:cursor-not-allowed"
            ]}
          >
            <.icon name="hero-exclamation-triangle" class="size-4" />
            <span>Foul</span>
          </button>
        </div>
      </div>

      <.stoppages_bar
        disconnected?={@disconnected?}
        show_halftime?={false}
        timeouts_remaining={@timeouts_remaining}
      />
    </div>
    """
  end

  attr :disconnected?, :boolean, required: true
  attr :show_halftime?, :boolean, required: true
  attr :show_finish_game?, :boolean, default: false
  attr :halftime_recorded?, :boolean, default: false
  attr :timeouts_remaining, :integer, required: true

  defp stoppages_bar(assigns) do
    show_halftime_button? = assigns.show_halftime? and not assigns.halftime_recorded?

    cols =
      cond do
        show_halftime_button? and assigns.show_finish_game? -> "grid-cols-3"
        show_halftime_button? or assigns.show_finish_game? -> "grid-cols-2"
        true -> "grid-cols-1"
      end

    assigns =
      assigns
      |> assign(:cols, cols)
      |> assign(:show_halftime_button?, show_halftime_button?)

    ~H"""
    <div class="space-y-1" aria-label="Stoppages">
      <h3 class="text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
        Stoppages
      </h3>
      <div class={["grid gap-2", @cols]}>
        <button
          type="button"
          phx-click="record_timeout"
          disabled={@disconnected? or @timeouts_remaining <= 0}
          aria-label={"Take a timeout (#{@timeouts_remaining} left this half)"}
          class={[
            "min-h-9 px-2 py-1 rounded-md border border-base-300",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold bg-base-100 text-base-content active:bg-base-200",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-pause" class="size-4" />
          <span>Timeout</span>
          <span class="tabular-nums text-[11px] text-base-content/60">
            ({@timeouts_remaining})
          </span>
        </button>
        <button
          :if={@show_halftime_button?}
          type="button"
          phx-click="record_halftime"
          disabled={@disconnected?}
          aria-label="Record halftime"
          class={[
            "min-h-9 px-2 py-1 rounded-md border border-base-300",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold bg-base-100 text-base-content active:bg-base-200",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-flag" class="size-4" />
          <span>Halftime</span>
        </button>
        <button
          :if={@show_finish_game?}
          type="button"
          phx-click="finish_game"
          data-confirm="Finish this game? You can't add more points after."
          disabled={@disconnected?}
          aria-label="Finish game"
          class={[
            "min-h-9 px-2 py-1 rounded-md border border-error/40 text-error",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold bg-base-100 active:bg-error/10",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-flag" class="size-4" />
          <span>Finish</span>
        </button>
      </div>
    </div>
    """
  end

  attr :game, :map, required: true
  attr :current_point, :any, required: true
  attr :selected_user_ids, :any, required: true
  attr :team_players, :list, required: true
  attr :required_line_size, :integer, required: true
  attr :disconnected?, :boolean, required: true

  defp bottom_action_bar(assigns) do
    counts = selected_position_counts(assigns.team_players, assigns.selected_user_ids)
    assigns = assign(assigns, :position_counts, counts)

    ~H"""
    <div
      :if={@game.status != :finished and is_nil(@current_point)}
      class="sticky bottom-0 px-4 pb-safe bg-base-100/95 backdrop-blur border-t border-base-200"
    >
      <div class="py-2 space-y-2">
        <button
          type="button"
          phx-click="start_point"
          disabled={MapSet.size(@selected_user_ids) != @required_line_size or @disconnected?}
          class={[
            "w-full min-h-9 rounded-md px-2 py-1",
            "inline-flex items-center justify-center gap-2",
            "text-sm font-semibold bg-primary text-primary-content",
            "transition-colors motion-reduce:transition-none active:bg-primary/80",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <span>Start point</span>
          <span aria-hidden="true">-</span>
          <span class="tabular-nums">
            H {@position_counts.handler} · C {@position_counts.cutter} · X {@position_counts.hybrid}
          </span>
          <span aria-hidden="true">-</span>
          <span class="tabular-nums">
            {MapSet.size(@selected_user_ids)} / {@required_line_size}
          </span>
        </button>
      </div>
    </div>
    """
  end

  defp selected_position_counts(team_players, selected_user_ids) do
    team_players
    |> Enum.filter(&MapSet.member?(selected_user_ids, &1.user_id))
    |> Enum.reduce(%{handler: 0, cutter: 0, hybrid: 0}, fn p, acc ->
      case Teams.resolved_position(p) do
        :handler -> %{acc | handler: acc.handler + 1}
        :cutter -> %{acc | cutter: acc.cutter + 1}
        :hybrid -> %{acc | hybrid: acc.hybrid + 1}
        _ -> acc
      end
    end)
  end

  ## ---------------------------------------------------------------------
  ## events
  ## ---------------------------------------------------------------------

  @impl true
  def handle_event("toggle_player", %{"id" => user_id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_user_ids, user_id) do
        MapSet.delete(socket.assigns.selected_user_ids, user_id)
      else
        MapSet.put(socket.assigns.selected_user_ids, user_id)
      end

    {:noreply,
     socket
     |> assign(:selected_user_ids, selected)
     |> assign(:selected_preset_id, nil)
     |> assign_line_picker_selection_state()}
  end

  def handle_event("toggle_split_by_position", _params, socket) do
    {:noreply, assign(socket, :split_by_position?, not socket.assigns.split_by_position?)}
  end

  def handle_event("change_sort", %{"sort" => sort}, socket) do
    parsed =
      case sort do
        "jersey" -> :jersey
        "name" -> :name
        "points" -> :points
        _ -> socket.assigns.line_picker_sort
      end

    {:noreply, assign(socket, :line_picker_sort, parsed)}
  end

  def handle_event("clear_preset", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_user_ids, MapSet.new())
     |> assign(:selected_preset_id, nil)
     |> assign_line_picker_selection_state()}
  end

  def handle_event("select_preset", %{"id" => preset_id}, socket) do
    case Enum.find(socket.assigns.line_presets, &(&1.id == preset_id)) do
      nil ->
        {:noreply, socket}

      preset ->
        ids = Enum.map(preset.users, & &1.id) |> MapSet.new()

        {:noreply,
         socket
         |> assign(:selected_user_ids, ids)
         |> assign(:selected_preset_id, preset_id)
         |> assign_line_picker_selection_state()}
    end
  end

  def handle_event("start_point", _params, socket) do
    user_ids = MapSet.to_list(socket.assigns.selected_user_ids)

    case Games.start_point(socket.assigns.game, user_ids) do
      {:ok, point} ->
        # No assign_line_picker_state here — the picker isn't visible
        # in-point. Its assigns get refreshed in after_point_end when the
        # picker comes back. Skipping saves 2 DB round-trips per start.
        {:noreply,
         socket
         |> assign(:current_point, point)
         |> assign(:points_count, (socket.assigns[:points_count] || 0) + 1)
         |> assign(:events, [])
         |> assign(:possession, Games.starting_possession(socket.assigns.game, point))
         |> assign(:current_passer_id, nil)
         |> assign(:throwaway_prompt, nil)
         |> assign(:undo_stack, [])
         |> assign(:redo_stack, [])
         |> assign(:last_ended, nil)
         |> assign(:selected_user_ids, MapSet.new())
         |> assign(:selected_preset_id, nil)}

      {:error, :wrong_line_size} ->
        required = Games.line_size_for(socket.assigns.game)

        {:noreply,
         put_flash(socket, :error, "Pick exactly #{required} players to start the point.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not start point — pick at least one player.")}
    end
  end

  def handle_event("finish_game", _params, socket) do
    case Games.end_game(socket.assigns.game) do
      {:ok, finished} ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{finished.id}/summary")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not finish game.")}
    end
  end

  def handle_event("cancel_current_point", _params, socket) do
    case socket.assigns.current_point do
      nil ->
        {:noreply, socket}

      point ->
        # Restore the line snapshot back to the picker so the tracker can
        # tweak and re-start without re-tapping every player.
        previous_user_ids =
          point.our_line_snapshot
          |> Map.get("user_ids", [])
          |> MapSet.new()

        {:ok, _} = Repo.delete(point)

        {:noreply,
         socket
         |> assign(:current_point, nil)
         |> assign(:points_count, max((socket.assigns[:points_count] || 1) - 1, 0))
         |> assign(:events, [])
         |> assign(:possession, nil)
         |> assign(:selected_user_ids, previous_user_ids)
         |> assign(:current_passer_id, nil)
         |> assign(:throwaway_prompt, nil)
         |> assign(:undo_stack, [])
         |> assign(:redo_stack, [])
         |> assign(:last_ended, nil)
         |> assign_line_picker_state()
         |> put_flash(:info, "Point cancelled")}
    end
  end

  # When no current passer is set yet, a tap on a player's name area
  # promotes them to the current passer.
  def handle_event("set_passer", %{"id" => raw_id}, socket) do
    {:noreply, assign(socket, :current_passer_id, parse_player_token(raw_id))}
  end

  # Inline per-row outcome capture. `type` is one of
  # `"catch" | "drop" | "goal" | "throwaway"`. For passer-only types
  # (`throwaway`) the row's player-id is ignored; for receiver-attributed
  # types it becomes the receiver_id (or nil for "unknown").
  def handle_event("record_throw_for_player", %{"type" => type_str} = params, socket) do
    type = String.to_existing_atom(type_str)
    point = socket.assigns.current_point
    passer_id = id_or_nil(socket.assigns.current_passer_id)

    receiver_id =
      case type do
        t when t in [:throwaway, :stall] ->
          nil

        _ ->
          params
          |> Map.get("player-id")
          |> parse_player_token()
          |> id_or_nil()
      end

    case Games.record_throw(point, type, passer_id, receiver_id, throw_opts(socket)) do
      {:ok, event} ->
        events = socket.assigns.events ++ [event]

        socket =
          socket
          |> assign(:events, events)
          |> track_event_recorded(event)
          |> assign(:throwaway_prompt, nil)

        apply_outcome_transition(socket, type, point, events)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record event.")}
    end
  end

  # Record the opening pull for a defending point. Sets passer = our
  # puller, no receiver. Possession stays :theirs.
  def handle_event("record_pull", %{"player-id" => raw}, socket) do
    point = socket.assigns.current_point
    puller_id = raw |> parse_player_token() |> id_or_nil()

    case Games.record_throw(point, :pull, puller_id, nil, throw_opts(socket)) do
      {:ok, event} ->
        events = socket.assigns.events ++ [event]

        {:noreply,
         socket
         |> assign(:events, events)
         |> track_event_recorded(event)
         |> assign(:possession, derive_possession(socket.assigns.game, point, events))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record pull.")}
    end
  end

  # Standalone Stall button (passer-only, no row context).
  def handle_event("record_throw_outcome", %{"type" => "stall"}, socket) do
    point = socket.assigns.current_point
    passer_id = id_or_nil(socket.assigns.current_passer_id)

    case Games.record_throw(point, :stall, passer_id, nil, throw_opts(socket)) do
      {:ok, event} ->
        events = socket.assigns.events ++ [event]

        socket =
          socket
          |> assign(:events, events)
          |> track_event_recorded(event)

        apply_outcome_transition(socket, :stall, point, events)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record stall.")}
    end
  end

  # Open the throwaway disambiguation strip for `player-id` (the row
  # whose Throwaway icon was tapped).
  def handle_event("prompt_throwaway", %{"player-id" => raw}, socket) do
    {:noreply, assign(socket, :throwaway_prompt, %{player_id: parse_player_token(raw)})}
  end

  def handle_event("cancel_throwaway", _params, socket) do
    {:noreply, assign(socket, :throwaway_prompt, nil)}
  end

  # Inline defender-row capture. `kind` is `"block"` (defender = passer)
  # or `"catch"` (defender = receiver/interceptor, passer = nil).
  def handle_event("record_defense_for_player", %{"player-id" => raw, "kind" => kind}, socket)
      when kind in ["block", "catch"] do
    point = socket.assigns.current_point
    token = parse_player_token(raw)
    id = id_or_nil(token)

    {type, passer_id, receiver_id} =
      case kind do
        "block" -> {:block, id, nil}
        "catch" -> {:catch, nil, id}
      end

    case Games.record_throw(point, type, passer_id, receiver_id, throw_opts(socket)) do
      {:ok, event} ->
        events = socket.assigns.events ++ [event]

        # A block knocks the disc down — someone still has to pick it up,
        # so we clear the passer and let the user tap who has the disc.
        # An interception (catch) means the defender already has it, so
        # they auto-become the passer.
        next_passer =
          case kind do
            "catch" -> token
            _ -> nil
          end

        {:noreply,
         socket
         |> assign(:events, events)
         |> track_event_recorded(event)
         |> assign(:possession, derive_possession(socket.assigns.game, point, events))
         |> assign(:current_passer_id, next_passer)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record event.")}
    end
  end

  def handle_event("record_opponent_turnover", _params, socket) do
    point = socket.assigns.current_point

    case Games.record_throw(point, :opponent_turnover, nil, nil, throw_opts(socket)) do
      {:ok, event} ->
        events = socket.assigns.events ++ [event]

        {:noreply,
         socket
         |> assign(:events, events)
         |> track_event_recorded(event)
         |> assign(:possession, derive_possession(socket.assigns.game, point, events))
         |> assign(:current_passer_id, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record turnover.")}
    end
  end

  def handle_event("record_opponent_goal", _params, socket) do
    point = socket.assigns.current_point

    with {:ok, event} <- Games.record_throw(point, :opponent_goal, nil, nil, throw_opts(socket)),
         {:ok, _ended} <- Games.end_point(point, :theirs) do
      socket = assign(socket, :last_ended, %{point_id: point.id, event_id: event.id})
      {:noreply, after_point_end(socket, point, :theirs)}
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record opponent goal.")}
    end
  end

  def handle_event("record_call", %{"type" => type_str}, socket) do
    type = String.to_existing_atom(type_str)

    if type in [:pick, :foul] do
      point = socket.assigns.current_point

      case Games.record_throw(point, type, nil, nil, throw_opts(socket)) do
        {:ok, event} ->
          events = socket.assigns.events ++ [event]

          # Possession unchanged for calls; we still re-derive defensively
          # so the assign stays in sync if any future logic changes.
          {:noreply,
           socket
           |> assign(:events, events)
           |> track_event_recorded(event)
           |> assign(:possession, derive_possession(socket.assigns.game, point, events))
           |> assign(:call_prompt, %{type: type, event_id: event.id})}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not record call.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("resolve_call", %{"action" => action}, socket) do
    case socket.assigns.call_prompt do
      nil -> {:noreply, socket}
      prompt -> apply_call_resolution(socket, prompt, action)
    end
  end

  def handle_event("record_timeout", _params, socket) do
    type =
      case socket.assigns.possession do
        :theirs -> :timeout_theirs
        _ -> :timeout_ours
      end

    case Games.record_game_event(socket.assigns.game, type) do
      {:ok, event} ->
        socket = track_event_recorded(socket, event)

        events =
          if socket.assigns.current_point do
            socket.assigns.events ++ [event]
          else
            socket.assigns.events
          end

        {:noreply,
         socket
         |> assign(:events, events)
         |> assign(:timeout_active?, true)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record timeout.")}
    end
  end

  def handle_event("resume_game", _params, socket) do
    resume_type =
      cond do
        socket.assigns.timeout_active? -> :timeout_resume
        socket.assigns.halftime_active? -> :halftime_resume
        true -> nil
      end

    socket =
      if resume_type do
        case Games.record_game_event(socket.assigns.game, resume_type) do
          {:ok, event} ->
            socket = track_event_recorded(socket, event)

            events =
              case socket.assigns.current_point do
                %Point{} = point -> Games.events_for_point(point)
                _ -> socket.assigns.events
              end

            assign(socket, :events, events)

          {:error, _} ->
            put_flash(socket, :error, "Could not record resume.")
        end
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:timeout_active?, false)
     |> assign(:halftime_active?, false)
     |> assign_line_picker_state()}
  end

  def handle_event("record_halftime", _params, socket) do
    case Games.record_game_event(socket.assigns.game, :halftime) do
      {:ok, event} ->
        socket = track_event_recorded(socket, event)

        events =
          if socket.assigns.current_point do
            socket.assigns.events ++ [event]
          else
            socket.assigns.events
          end

        {:noreply,
         socket
         |> assign(:events, events)
         |> assign(:halftime_active?, true)
         |> put_flash(:info, "Halftime recorded.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record halftime.")}
    end
  end

  def handle_event("dismiss_halftime", _params, socket) do
    {:noreply, assign(socket, :halftime_dismissed?, true)}
  end

  def handle_event("undo", _params, socket) do
    case socket.assigns.undo_stack do
      [] ->
        {:noreply, socket}

      [event_id | rest_undo] ->
        with %Event{} = event <- Enum.find(socket.assigns.events, &(&1.id == event_id)),
             {:ok, _} <- Games.soft_delete_event(event) do
          events = Enum.reject(socket.assigns.events, &(&1.id == event_id))

          {:noreply,
           after_history_change(
             socket,
             rest_undo,
             [event_id | socket.assigns.redo_stack],
             events,
             event.type
           )}
        else
          _ -> {:noreply, put_flash(socket, :error, "Could not undo.")}
        end
    end
  end

  # Undo the goal that just ended a point and reopen the point so the
  # tracker can keep recording. The goal event is soft-deleted; the
  # point's `scoring_team` is cleared. Score auto-updates from the now-
  # filtered events. One-shot — does not feed the redo stack.
  def handle_event("undo_last_goal", _params, socket) do
    case socket.assigns.last_ended do
      nil ->
        {:noreply, socket}

      %{point_id: point_id, event_id: event_id} ->
        with %Event{} = event <- Repo.get(Event, event_id),
             {:ok, _} <- Games.soft_delete_event(event),
             {:ok, point} <- Games.reopen_point(point_id) do
          events = Games.events_for_point(point)
          game = socket.assigns.game

          {:noreply,
           socket
           |> assign(:current_point, point)
           |> assign(:events, events)
           |> assign(:possession, derive_possession(game, point, events))
           |> assign(:current_passer_id, derive_current_passer(events))
           |> assign(:score, Games.score(game))
           |> assign(:undo_stack, events |> Enum.reverse() |> Enum.map(& &1.id))
           |> assign(:redo_stack, [])
           |> assign(:last_ended, nil)
           |> assign(:selected_user_ids, MapSet.new())
           |> assign(:selected_preset_id, nil)
           |> assign_line_picker_state()
           |> put_flash(:info, "Goal undone")}
        else
          _ -> {:noreply, put_flash(socket, :error, "Could not undo goal.")}
        end
    end
  end

  def handle_event("redo", _params, socket) do
    case socket.assigns.redo_stack do
      [] ->
        {:noreply, socket}

      [event_id | rest_redo] ->
        with %Event{} = event <- Repo.get(Event, event_id),
             {:ok, restored} <- Games.restore_event(event) do
          events =
            (socket.assigns.events ++ [restored])
            |> Enum.sort_by(& &1.sequence)

          {:noreply,
           after_history_change(
             socket,
             [event_id | socket.assigns.undo_stack],
             rest_redo,
             events,
             restored.type
           )}
        else
          _ -> {:noreply, put_flash(socket, :error, "Could not redo.")}
        end
    end
  end

  ## ---------------------------------------------------------------------
  ## helpers — undo / redo bookkeeping
  ## ---------------------------------------------------------------------

  # Push the just-recorded event onto the undo stack and clear the redo
  # stack (a fresh action invalidates any prior redos). Refreshes the
  # halftime/timeout-counter assigns so stoppages_bar reflects the new
  # event state.
  # Only halftime/timeout events affect `halftime_recorded?` and
  # `timeouts_remaining` — for ordinary throws (catch/drop/goal/etc.) we
  # skip those two DB queries entirely. Real game events fire fast on
  # the sideline so this matters per-tap.
  @stoppage_event_types [
    :halftime,
    :halftime_resume,
    :timeout_ours,
    :timeout_theirs,
    :timeout_resume
  ]

  # Builds the opts that turn `Games.record_throw` from 3 DB queries
  # (validate passer + validate receiver + sequence lookup) into 1
  # (just the INSERT). Both checks are derived from already-loaded
  # socket state so they happen in-process.
  defp throw_opts(socket) do
    [
      sequence: next_event_sequence_from_assigns(socket.assigns.events),
      valid_user_ids: socket.assigns.valid_user_ids
    ]
  end

  defp next_event_sequence_from_assigns([]), do: 1

  defp next_event_sequence_from_assigns(events) do
    events
    |> Enum.reduce(0, fn e, acc -> max(acc, e.sequence) end)
    |> Kernel.+(1)
  end

  defp track_event_recorded(socket, %Event{id: event_id, type: type}) do
    socket
    |> assign(:undo_stack, [event_id | socket.assigns.undo_stack])
    |> assign(:redo_stack, [])
    |> maybe_assign_stoppage_state(type)
  end

  defp maybe_assign_stoppage_state(socket, type) when type in @stoppage_event_types,
    do: assign_stoppage_state(socket)

  defp maybe_assign_stoppage_state(socket, _), do: socket

  defp assign_stoppage_state(socket) do
    %{halftime_recorded?: hr?, timeouts_remaining: tr} =
      Games.stoppage_state(socket.assigns.game)

    socket
    |> assign(:halftime_recorded?, hr?)
    |> assign(:timeouts_remaining, tr)
  end

  defp apply_call_resolution(socket, _prompt, "resume") do
    {:noreply, assign(socket, :call_prompt, nil)}
  end

  defp apply_call_resolution(socket, prompt, "cancel") do
    apply_call_resolution(socket, prompt, "retract")
  end

  defp apply_call_resolution(socket, %{event_id: event_id}, "retract") do
    case Repo.get(Event, event_id) do
      %Event{} = event ->
        case Games.soft_delete_event(event) do
          {:ok, _} ->
            point = socket.assigns.current_point
            events = Enum.reject(socket.assigns.events, &(&1.id == event_id))

            {:noreply,
             socket
             |> assign(:events, events)
             |> assign(:undo_stack, List.delete(socket.assigns.undo_stack, event_id))
             |> assign(:call_prompt, nil)
             |> assign(:possession, derive_possession(socket.assigns.game, point, events))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not retract call.")}
        end

      nil ->
        {:noreply, assign(socket, :call_prompt, nil)}
    end
  end

  defp apply_call_resolution(socket, _prompt, "back_to_thrower") do
    point = socket.assigns.current_point
    events = socket.assigns.events

    case last_live_catch(events) do
      nil ->
        {:noreply,
         socket
         |> assign(:call_prompt, nil)
         |> put_flash(:info, "No previous thrower to return to.")}

      catch_event ->
        case Games.soft_delete_event(catch_event) do
          {:ok, _} ->
            refreshed = Enum.reject(socket.assigns.events, &(&1.id == catch_event.id))

            {:noreply,
             socket
             |> assign(:events, refreshed)
             |> assign(:undo_stack, List.delete(socket.assigns.undo_stack, catch_event.id))
             |> assign(:call_prompt, nil)
             |> assign(:current_passer_id, catch_event.passer_user_id || :unknown)
             |> assign(:possession, derive_possession(socket.assigns.game, point, refreshed))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not return to thrower.")}
        end
    end
  end

  defp apply_call_resolution(socket, _prompt, "turnover") do
    point = socket.assigns.current_point

    {type, passer_id, receiver_id} =
      case socket.assigns.possession do
        :theirs -> {:opponent_turnover, nil, nil}
        _ -> {:throwaway, id_or_nil(socket.assigns.current_passer_id), nil}
      end

    case Games.record_throw(point, type, passer_id, receiver_id, throw_opts(socket)) do
      {:ok, event} ->
        events = socket.assigns.events ++ [event]

        {:noreply,
         socket
         |> assign(:events, events)
         |> track_event_recorded(event)
         |> assign(:call_prompt, nil)
         |> assign(:current_passer_id, nil)
         |> assign(:possession, derive_possession(socket.assigns.game, point, events))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record turnover.")}
    end
  end

  defp apply_call_resolution(socket, _prompt, _other) do
    {:noreply, socket}
  end

  defp last_live_catch(events) do
    events
    |> Enum.reverse()
    |> Enum.find(&(&1.type == :catch and is_nil(&1.deleted_at)))
  end

  # Re-syncs everything that derives from the events list after an undo
  # or redo: events, possession, current passer. Selection state
  # (receiver / defender pickers) is cleared so the user starts the
  # next interaction fresh. Stoppage state only refreshes when the
  # deleted/restored event was a stoppage event.
  defp after_history_change(socket, undo_stack, redo_stack, events, event_type) do
    point = socket.assigns.current_point

    socket
    |> assign(:undo_stack, undo_stack)
    |> assign(:redo_stack, redo_stack)
    |> assign(:events, events)
    |> assign(:possession, derive_possession(socket.assigns.game, point, events))
    |> assign(:current_passer_id, derive_current_passer(events))
    |> assign(:throwaway_prompt, nil)
    |> maybe_assign_stoppage_state(event_type)
  end

  # Walks the (live) events for a point and returns the current passer
  # token: a user id, `:unknown`, or `nil` for "no passer set".
  defp derive_current_passer(events) do
    Enum.reduce(events, nil, fn ev, current ->
      case ev.type do
        :catch -> token_from_id(ev.receiver_user_id)
        # A block leaves the disc loose; the next passer is set by the
        # tracker tapping who picks it up, not by the blocker's id.
        :block -> nil
        :drop -> nil
        :throwaway -> nil
        :stall -> nil
        :opponent_turnover -> nil
        _ -> current
      end
    end)
  end

  defp token_from_id(nil), do: :unknown
  defp token_from_id(id) when is_binary(id), do: id

  ## ---------------------------------------------------------------------
  ## helpers — outcome transitions
  ## ---------------------------------------------------------------------

  # After a successful per-throw event, refresh derived state from the
  # live event list. `:catch` makes the receiver the new current passer;
  # `:drop`/`:throwaway`/`:stall` clear it (possession flips to :theirs).
  # `:goal` ends the point and transitions to the line picker.
  defp apply_outcome_transition(socket, type, point, events)
       when type in [:catch, :drop, :throwaway, :stall] do
    {:noreply,
     socket
     |> assign(:possession, derive_possession(socket.assigns.game, point, events))
     |> assign(:current_passer_id, derive_current_passer(events))}
  end

  defp apply_outcome_transition(socket, :goal, point, _events) do
    case Games.end_point(point, :ours) do
      {:ok, _ended} ->
        # The goal event we just recorded sits at the head of the undo
        # stack. Stash it so the line picker can offer "Undo last goal".
        last_event_id = List.first(socket.assigns.undo_stack)

        socket =
          assign(socket, :last_ended, %{point_id: point.id, event_id: last_event_id})

        {:noreply, after_point_end(socket, point, :ours)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not end point.")}
    end
  end

  # Refresh score, line picker state, and check for hard-cap. Score
  # increments and `points_played_by_user` updates are derived from the
  # just-ended point's snapshot so we avoid 4 DB round-trips per goal
  # (Games.score x2 aggregates, points_played_by_user, starting_possession).
  defp after_point_end(socket, %Point{} = ended_point, scoring_team) do
    prior_score = socket.assigns.score

    score =
      case scoring_team do
        :ours -> %{prior_score | ours: prior_score.ours + 1}
        :theirs -> %{prior_score | theirs: prior_score.theirs + 1}
      end

    socket =
      socket
      |> assign(:score, score)
      |> assign(:current_point, nil)
      |> assign(:events, [])
      |> assign(:possession, nil)
      |> assign(:current_passer_id, nil)
      |> assign(:throwaway_prompt, nil)
      |> assign(:undo_stack, [])
      |> assign(:redo_stack, [])
      |> assign(:selected_user_ids, MapSet.new())
      |> assign(:selected_preset_id, nil)
      |> assign_line_picker_game_state_after_point(ended_point, scoring_team)
      |> assign_line_picker_selection_state()

    game = socket.assigns.game

    if Games.hard_cap_reached?(game, score) do
      case Games.end_game(game) do
        {:ok, finished} ->
          socket
          |> assign(:game, finished)
          |> push_navigate(to: ~p"/games/#{finished.id}/summary")

        _ ->
          socket
      end
    else
      socket
    end
  end

  ## ---------------------------------------------------------------------
  ## helpers — display + parsing
  ## ---------------------------------------------------------------------

  defp parse_player_token("unknown"), do: :unknown
  defp parse_player_token(""), do: nil
  defp parse_player_token(id) when is_binary(id), do: id
  defp parse_player_token(other), do: other

  defp id_or_nil(:unknown), do: nil
  defp id_or_nil(nil), do: nil
  defp id_or_nil(id) when is_binary(id), do: id

  defp passer_card_label(:unknown, _lookup), do: "🥏 Unknown"

  defp passer_card_label(user_id, lookup) when is_binary(user_id) do
    case Map.get(lookup, user_id) do
      nil -> "Unknown"
      member -> "##{Teams.resolved_jersey_number(member)} #{User.display_name(member.user)}"
    end
  end

  defp passer_card_label(_, _), do: "—"

  defp passer_card_number(:unknown, _lookup), do: "?"

  defp passer_card_number(user_id, lookup) when is_binary(user_id) do
    case Map.get(lookup, user_id) do
      nil -> "?"
      member -> Teams.resolved_jersey_number(member) || "?"
    end
  end

  defp passer_card_number(_, _), do: "—"

  defp passer_data_id(:unknown), do: "unknown"
  defp passer_data_id(id) when is_binary(id), do: id
  defp passer_data_id(_), do: ""

  defp length_of_points(game) do
    case Games.get_game_with_points!(game.id).points do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp line_user_ids(nil), do: []
  defp line_user_ids(%{our_line_snapshot: %{"user_ids" => ids}}) when is_list(ids), do: ids
  defp line_user_ids(_), do: []

  defp gender_glyph(:female_matching), do: "F"
  defp gender_glyph(:male_matching), do: "M"
  defp gender_glyph(_), do: ""

  defp possession_label(:ours), do: "We have the disc"
  defp possession_label(:theirs), do: "They have the disc"
  defp possession_label(_), do: "Possession unknown"

  # Tints the entire sticky top area by possession state. Between points
  # (no current_point) we keep the neutral base.
  defp top_bar_classes(nil, _), do: "bg-base-100/95 border-base-200"
  defp top_bar_classes(_point, :ours), do: "bg-success/10 border-success/30"
  defp top_bar_classes(_point, :theirs), do: "bg-error/10 border-error/30"
  defp top_bar_classes(_point, :pulling), do: "bg-info/10 border-info/30"
  defp top_bar_classes(_point, _), do: "bg-base-100/95 border-base-200"

  # Whole-surface tint matching the top bar — only during an active
  # point so the line picker keeps a neutral background.
  defp surface_tint(nil, _), do: ""
  defp surface_tint(_point, :ours), do: "bg-success/5"
  defp surface_tint(_point, :theirs), do: "bg-error/5"
  defp surface_tint(_point, :pulling), do: "bg-info/5"
  defp surface_tint(_point, _), do: ""

  defp possession_banner_classes(:ours), do: "bg-success/20 text-success"
  defp possession_banner_classes(:theirs), do: "bg-error/20 text-error"
  defp possession_banner_classes(:pulling), do: "bg-info/20 text-info"
  defp possession_banner_classes(_), do: "bg-base-200 text-base-content/70"

  defp possession_banner_label(:ours), do: "Our possession"
  defp possession_banner_label(:theirs), do: "Their possession"
  defp possession_banner_label(:pulling), do: "Pulling"
  defp possession_banner_label(_), do: "Possession unknown"

  # The banner state collapses possession + pull-pending into a single atom:
  # `:pulling` while we're on D and the pull hasn't been recorded yet,
  # otherwise the raw possession atom (`:ours` / `:theirs` / nil).
  defp banner_state(:theirs, []), do: :pulling
  defp banner_state(possession, _events), do: possession

  # Line-picker pull pill: "We pull" means we kick the disc to them, so
  # we start the point on defense. The receiving side (:ours == we have
  # the disc next) is offense.
  defp starting_possession_label(:ours), do: "They pull → start on offense"
  defp starting_possession_label(:theirs), do: "We pull → start on defense"
  defp starting_possession_label(_), do: "Possession unknown"

  defp starting_possession_banner_classes(:ours), do: "bg-success/15 text-success"
  defp starting_possession_banner_classes(:theirs), do: "bg-error/10 text-error"
  defp starting_possession_banner_classes(_), do: "bg-base-200 text-base-content/70"

  defp starting_possession_icon(:ours), do: "hero-arrow-right-circle"
  defp starting_possession_icon(:theirs), do: "hero-shield-check"
  defp starting_possession_icon(_), do: "hero-question-mark-circle"

  # Possession at the start of the point comes from the pull/receive rules
  # (`Games.starting_possession/2`); per-throw events flip per the table
  # in `docs/DESIGN.md`. Calls (`:pick`, `:foul`) leave possession alone.
  defp derive_possession(game, point, events) do
    start = Games.starting_possession(game, point)

    Enum.reduce(events, start, fn ev, current ->
      case ev.type do
        :pull -> :theirs
        :catch -> :ours
        :throwaway -> :theirs
        :drop -> :theirs
        :stall -> :theirs
        :block -> :ours
        :opponent_turnover -> :ours
        # :goal / :opponent_goal end the point — possession is moot but
        # we leave the value in place for the post-end render.
        _ -> current
      end
    end)
  end

  defp role_label(:male_matching), do: "Male-matching"
  defp role_label(:female_matching), do: "Female-matching"

  attr :role, :atom, required: true, values: [:female_matching, :male_matching]
  attr :players, :list, required: true
  attr :selected_ids, MapSet, required: true
  attr :points_played_by_user, :map, required: true
  attr :sort, :atom, required: true
  attr :split_by_position?, :boolean, required: true

  defp line_picker_section(assigns) do
    sorted = sort_players(assigns.players, assigns.sort, assigns.points_played_by_user)

    selected_in_section =
      Enum.count(assigns.players, &MapSet.member?(assigns.selected_ids, &1.user_id))

    groups =
      if assigns.split_by_position? do
        position_groups(sorted)
      else
        [{nil, sorted}]
      end

    assigns =
      assigns
      |> assign(:players, sorted)
      |> assign(:selected_in_section, selected_in_section)
      |> assign(:groups, groups)

    ~H"""
    <section class="space-y-1">
      <h3 class="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-wide text-base-content/60 px-1">
        <span class="text-xs font-bold leading-none" aria-hidden="true">{gender_glyph(@role)}</span>
        <span>{role_label(@role)}</span>
        <span class="tabular-nums text-base-content/50">
          {@selected_in_section} of {length(@players)}
        </span>
      </h3>

      <div :for={{position, members} <- @groups} class="space-y-1">
        <h4
          :if={@split_by_position?}
          class="flex items-center gap-1.5 px-1 text-[10px] font-semibold uppercase tracking-wide text-base-content/50"
        >
          <span class={[
            "inline-flex items-center justify-center size-4 rounded-full text-[10px] font-semibold",
            position_pill_classes(position)
          ]}>
            {position_letter(position)}
          </span>
          <span>{humanize_position(position) || "Unspecified"}</span>
        </h4>

        <ul
          class="rounded-md border border-base-200 divide-y divide-base-200 overflow-hidden"
          role="list"
          aria-label={role_label(@role) <> " players"}
        >
          <li :for={member <- members} id={"line-pick-#{member.user_id}"}>
            <button
              type="button"
              phx-click="toggle_player"
              phx-value-id={member.user_id}
              aria-pressed={to_string(MapSet.member?(@selected_ids, member.user_id))}
              class={[
                "w-full min-h-9 px-3 py-0.5 flex items-center gap-2 text-left",
                "transition-colors motion-reduce:transition-none active:bg-base-200",
                "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                "phx-click-loading:bg-primary/10",
                if(MapSet.member?(@selected_ids, member.user_id), do: "bg-primary/10", else: "")
              ]}
            >
              <span
                class={[
                  "tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full text-[11px] shrink-0",
                  if(MapSet.member?(@selected_ids, member.user_id),
                    do: "bg-primary text-primary-content",
                    else: "bg-base-200 text-base-content"
                  )
                ]}
                aria-hidden="true"
              >
                {Teams.resolved_jersey_number(member)}
              </span>
              <span class="flex items-center gap-1.5 flex-1 min-w-0">
                <span class="font-medium text-sm truncate leading-tight">
                  {User.display_name(member.user)}
                </span>
                <span
                  :if={pos = Teams.resolved_position(member)}
                  class={[
                    "inline-flex items-center justify-center size-5 rounded-full shrink-0",
                    "text-[10px] font-semibold tabular-nums",
                    position_pill_classes(pos)
                  ]}
                  aria-label={humanize_position(pos)}
                  title={humanize_position(pos)}
                >
                  {position_letter(pos)}
                </span>
              </span>
              <span
                class="inline-flex items-center gap-0.5 tabular-nums text-[11px] text-base-content/60 shrink-0"
                aria-label="playtime"
                title="Playtime"
              >
                <.icon name="hero-clock" class="size-3.5" />
                {Map.get(@points_played_by_user, member.user_id, 0)}
              </span>
            </button>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  defp position_groups(players) do
    grouped =
      Enum.group_by(players, fn member ->
        Teams.resolved_position(member) || :unspecified
      end)

    [:handler, :cutter, :hybrid, :unspecified]
    |> Enum.map(fn key ->
      {if(key == :unspecified, do: nil, else: key), Map.get(grouped, key, [])}
    end)
    |> Enum.reject(fn {_, members} -> members == [] end)
  end

  defp sort_players(players, :name, _points) do
    Enum.sort_by(players, &String.downcase(User.display_name(&1.user)))
  end

  defp sort_players(players, :points, points_played) do
    Enum.sort_by(
      players,
      &{-Map.get(points_played, &1.user_id, 0), String.downcase(User.display_name(&1.user))}
    )
  end

  defp sort_players(players, _jersey, _points) do
    Enum.sort_by(players, &jersey_sort_key_for_picker/1)
  end

  defp jersey_sort_key_for_picker(membership) do
    case Teams.resolved_jersey_number(membership) do
      nil ->
        {2, ""}

      "" ->
        {2, ""}

      n when is_binary(n) ->
        case Integer.parse(n) do
          {int, ""} -> {0, int}
          _ -> {1, n}
        end
    end
  end

  defp humanize_position(:handler), do: "Handler"
  defp humanize_position(:cutter), do: "Cutter"
  defp humanize_position(:hybrid), do: "Hybrid"

  defp humanize_position(other) when is_atom(other),
    do: other |> Atom.to_string() |> String.capitalize()

  defp humanize_position(_), do: nil

  defp position_letter(:handler), do: "H"
  defp position_letter(:cutter), do: "C"
  defp position_letter(:hybrid), do: "X"
  defp position_letter(_), do: "?"

  defp position_pill_classes(:handler), do: "bg-success/15 text-success"
  defp position_pill_classes(:cutter), do: "bg-warning/15 text-warning"
  defp position_pill_classes(:hybrid), do: "bg-info/15 text-info"
  defp position_pill_classes(_), do: "bg-base-200 text-base-content/70"

  defp preset_summary_label(_presets, nil), do: "Use preselected line"

  defp preset_summary_label(presets, selected_id) do
    case Enum.find(presets, &(&1.id == selected_id)) do
      nil -> "Use preselected line"
      preset -> preset.name
    end
  end
end
