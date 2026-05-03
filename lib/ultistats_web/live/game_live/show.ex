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
  alias Ultistats.Games.Event

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
      score = Games.score(game)
      events = if current_point, do: Games.events_for_point(current_point), else: []
      possession = if current_point, do: derive_possession(game, current_point, events), else: nil

      {:ok,
       socket
       |> assign(:page_title, "Game vs #{game.opponent_name}")
       |> assign(:game, game)
       |> assign(:team_players, team_players)
       |> assign(:line_presets, line_presets)
       |> assign(:current_point, current_point)
       |> assign(:score, score)
       |> assign(:events, events)
       |> assign(:possession, possession)
       |> assign(:selected_user_ids, MapSet.new())
       |> assign(:selected_preset_id, nil)
       |> assign(:current_passer_id, nil)
       |> assign(:selected_receiver_id, nil)
       |> assign(:selected_defender_id, nil)
       |> assign(:undo_stack, [])
       |> assign(:redo_stack, [])
       |> assign(:last_ended, nil)
       |> assign(:halftime_dismissed?, false)
       # Disconnect-driven button-disable is wired via JS hook in a later
       # task; assigns stays at false until the hook lands. The flash
       # banner from `Layouts.flash_group/1` already covers visual feedback.
       |> assign(:disconnected?, false)}
    end
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
        class="flex flex-col -mx-4 -mt-6 -mb-6 transition-[height] duration-200 motion-reduce:transition-none"
        style="height: calc(100dvh - var(--nav-offset, 3.5rem))"
      >
        <div class={[
          "border-b transition-colors duration-200 motion-reduce:transition-none",
          top_bar_classes(@current_point, @possession)
        ]}>
          <.compact_header
            game={@game}
            score={@score}
            current_point={@current_point}
            possession={@possession}
            halftime?={Games.halftime?(@game) and not @halftime_dismissed?}
            undo_stack={@undo_stack}
            redo_stack={@redo_stack}
            last_ended={@last_ended}
          />
        </div>

        <%= cond do %>
          <% @current_point -> %>
            <.in_point_view
              current_point={@current_point}
              team_players={@team_players}
              events={@events}
              possession={@possession}
              current_passer_id={@current_passer_id}
              selected_receiver_id={@selected_receiver_id}
              selected_defender_id={@selected_defender_id}
              disconnected?={@disconnected?}
            />
          <% true -> %>
            <.between_points_view
              point_number={length_of_points(@game) + 1}
              line_presets={@line_presets}
              team_players={@team_players}
              selected_user_ids={@selected_user_ids}
              selected_preset_id={@selected_preset_id}
            />
        <% end %>

        <.bottom_action_bar
          game={@game}
          current_point={@current_point}
          selected_user_ids={@selected_user_ids}
          team_players={@team_players}
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
  attr :halftime?, :boolean, required: true
  attr :undo_stack, :list, required: true
  attr :redo_stack, :list, required: true
  attr :last_ended, :any, required: true

  defp compact_header(assigns) do
    ~H"""
    <div
      :if={@current_point}
      class={[
        "py-1 text-center text-xs font-semibold uppercase tracking-wide",
        possession_banner_classes(@possession)
      ]}
    >
      {possession_banner_label(@possession)}
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
      </div>
    </div>
    """
  end

  attr :point_number, :integer, required: true
  attr :line_presets, :list, required: true
  attr :team_players, :list, required: true
  attr :selected_user_ids, :any, required: true
  attr :selected_preset_id, :any, required: true

  defp between_points_view(assigns) do
    ~H"""
    <section
      class="flex-1 min-h-0 flex flex-col gap-3 px-4 py-3 overflow-hidden"
      aria-label="Line picker"
    >
      <div :if={@line_presets != []} class="-mx-4 px-4 overflow-x-auto">
        <div class="flex gap-2 w-max">
          <button
            :for={preset <- @line_presets}
            type="button"
            phx-click="select_preset"
            phx-value-id={preset.id}
            aria-pressed={to_string(@selected_preset_id == preset.id)}
            class={[
              "min-h-11 inline-flex items-center gap-2 px-3 rounded-full text-sm font-medium",
              "border transition-colors motion-reduce:transition-none active:scale-[0.98] motion-reduce:active:scale-100",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              if(@selected_preset_id == preset.id,
                do: "bg-primary text-primary-content border-primary",
                else: "bg-base-100 text-base-content border-base-300 active:bg-base-200"
              )
            ]}
          >
            <span>{preset.name}</span>
            <span class={[
              "tabular-nums text-xs px-1.5 py-0.5 rounded-full",
              if(@selected_preset_id == preset.id,
                do: "bg-primary-content/20 text-primary-content",
                else: "bg-base-200 text-base-content/70"
              )
            ]}>
              {length(preset.users)}
            </span>
          </button>
        </div>
      </div>

      <%= if @team_players == [] do %>
        <div class="rounded-lg border-2 border-dashed border-base-300 p-6 text-center">
          <p class="text-base font-medium">No players on this team yet.</p>
          <p class="text-sm text-base-content/70 mt-1">
            Add players to the team's roster to start tracking points.
          </p>
        </div>
      <% else %>
        <div id="game-line-picker" class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden space-y-4">
          <.line_picker_section
            :for={role <- [:male_matching, :female_matching]}
            :if={Enum.any?(@team_players, &(&1.user.gender_role == role))}
            role={role}
            players={Enum.filter(@team_players, &(&1.user.gender_role == role))}
            selected_ids={@selected_user_ids}
          />
        </div>
      <% end %>
    </section>
    """
  end

  attr :current_point, :map, required: true
  attr :team_players, :list, required: true
  attr :events, :list, required: true
  attr :possession, :atom, required: true
  attr :current_passer_id, :any, required: true
  attr :selected_receiver_id, :any, required: true
  attr :selected_defender_id, :any, required: true
  attr :disconnected?, :boolean, required: true

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
          selected_receiver_id={@selected_receiver_id}
          disconnected?={@disconnected?}
        />
      <% else %>
        <.their_possession_view
          on_field={@on_field}
          selected_defender_id={@selected_defender_id}
          disconnected?={@disconnected?}
        />
      <% end %>

      <.calls_bar disconnected?={@disconnected?} />
    </section>
    """
  end

  attr :on_field, :list, required: true
  attr :player_lookup, :map, required: true
  attr :current_passer_id, :any, required: true
  attr :selected_receiver_id, :any, required: true
  attr :disconnected?, :boolean, required: true

  defp our_possession_view(assigns) do
    passer_set? = not is_nil(assigns.current_passer_id)
    receiver_set? = not is_nil(assigns.selected_receiver_id)

    assigns =
      assigns
      |> assign(:passer_set?, passer_set?)
      |> assign(:receiver_set?, receiver_set?)

    ~H"""
    <div class="space-y-2">
      <h3 class="text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
        Actions from our team
      </h3>

      <.current_passer_card
        current_passer_id={@current_passer_id}
        player_lookup={@player_lookup}
      />

      <.receiver_grid
        on_field={@on_field}
        passer_set?={@passer_set?}
        current_passer_id={@current_passer_id}
        selected_receiver_id={@selected_receiver_id}
      />

      <.outcome_buttons
        passer_set?={@passer_set?}
        receiver_set?={@receiver_set?}
        disconnected?={@disconnected?}
      />

      <h3 class="text-[11px] font-semibold uppercase tracking-wide text-base-content/60 pt-1">
        Actions from their team
      </h3>
      <div class="grid grid-cols-2 gap-2">
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="throwaway"
          disabled={@disconnected? or not @passer_set?}
          aria-label="Record an opponent block"
          class={[
            "min-h-9 px-2 py-1 rounded-md border border-base-300",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold bg-base-100 text-base-content active:bg-base-200",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-shield-check" class="size-4" />
          <span>Block</span>
        </button>
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="throwaway"
          disabled={@disconnected? or not @passer_set?}
          aria-label="Record an opponent interception"
          class={[
            "min-h-9 px-2 py-1 rounded-md border border-base-300",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold bg-base-100 text-base-content active:bg-base-200",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-check" class="size-4" />
          <span>Catch</span>
        </button>
      </div>
    </div>
    """
  end

  attr :current_passer_id, :any, required: true
  attr :player_lookup, :map, required: true

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
      class="rounded-lg bg-success/15 ring-2 ring-success px-3 py-2"
      aria-label={"Current passer: #{@label}"}
      data-current-passer={passer_data_id(@current_passer_id)}
    >
      <div class="flex items-center gap-2">
        <span
          class="tabular-nums font-semibold inline-flex items-center justify-center size-8 rounded-full bg-success text-success-content text-sm"
          aria-hidden="true"
        >
          {passer_card_number(@current_passer_id, @player_lookup)}
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold truncate leading-tight">{@label}</p>
          <p class="text-[11px] text-base-content/70 leading-tight">has the disc</p>
        </div>
      </div>
    </div>
    """
  end

  attr :on_field, :list, required: true
  attr :passer_set?, :boolean, required: true
  attr :current_passer_id, :any, required: true
  attr :selected_receiver_id, :any, required: true

  defp receiver_grid(assigns) do
    event_name = if assigns.passer_set?, do: "set_receiver", else: "set_passer"
    assigns = assign(assigns, :event_name, event_name)

    ~H"""
    <ul
      class="-mx-4 border-y border-base-200 divide-y divide-base-200"
      role="list"
      aria-label="On-field players"
    >
      <li :for={member <- @on_field}>
        <button
          type="button"
          phx-click={@event_name}
          phx-value-id={member.user_id}
          aria-pressed={
            to_string(
              receiver_active?(
                member.user_id,
                @passer_set?,
                @current_passer_id,
                @selected_receiver_id
              )
            )
          }
          disabled={receiver_disabled?(member.user_id, @passer_set?, @current_passer_id)}
          class={[
            "w-full min-h-9 px-4 py-0.5 flex items-center gap-2 text-left",
            "transition-colors motion-reduce:transition-none active:bg-base-200",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed",
            receiver_row_classes(
              member.user_id,
              @passer_set?,
              @current_passer_id,
              @selected_receiver_id
            )
          ]}
        >
          <span
            class={[
              "tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full text-[11px] shrink-0",
              if(member.user_id == @selected_receiver_id,
                do: "bg-primary text-primary-content",
                else: "bg-base-200 text-base-content"
              )
            ]}
            aria-hidden="true"
          >
            {member.jersey_number}
          </span>
          <span class="font-medium text-sm truncate flex-1 leading-tight">
            {User.display_name(member.user)}
          </span>
          <.icon
            :if={member.user_id == @selected_receiver_id}
            name="hero-check-circle-solid"
            class="size-4 text-primary shrink-0"
          />
        </button>
      </li>

      <%!-- Unknown chip — for when the tracker missed who threw or caught. --%>
      <li>
        <button
          type="button"
          phx-click={@event_name}
          phx-value-id="unknown"
          aria-pressed={
            to_string(
              receiver_active?(:unknown, @passer_set?, @current_passer_id, @selected_receiver_id)
            )
          }
          class={[
            "w-full min-h-9 px-4 py-0.5 flex items-center gap-2 text-left italic",
            "border-t-2 border-dashed border-base-300",
            "transition-colors motion-reduce:transition-none active:bg-base-200",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            receiver_row_classes(:unknown, @passer_set?, @current_passer_id, @selected_receiver_id)
          ]}
        >
          <span
            class="inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-xs shrink-0"
            aria-hidden="true"
          >
            ?
          </span>
          <span class="font-medium text-sm flex-1 leading-tight">Unknown</span>
          <.icon
            :if={@selected_receiver_id == :unknown}
            name="hero-check-circle-solid"
            class="size-4 text-primary shrink-0"
          />
        </button>
      </li>
    </ul>
    """
  end

  attr :passer_set?, :boolean, required: true
  attr :receiver_set?, :boolean, required: true
  attr :disconnected?, :boolean, required: true

  defp outcome_buttons(assigns) do
    catch_disabled? = assigns.disconnected? or not (assigns.passer_set? and assigns.receiver_set?)
    passer_only_disabled? = assigns.disconnected? or not assigns.passer_set?

    assigns =
      assigns
      |> assign(:catch_disabled?, catch_disabled?)
      |> assign(:passer_only_disabled?, passer_only_disabled?)

    ~H"""
    <div class="space-y-2">
      <%!-- Catch / Drop / Goal — require both passer + receiver. --%>
      <div class="grid grid-cols-3 gap-2">
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="catch"
          disabled={@catch_disabled?}
          aria-label="Record a catch"
          class={[
            "min-h-11 px-3 py-1.5 rounded-lg",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold",
            "bg-success text-success-content active:bg-success/80",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-check" class="size-4" />
          <span>Catch</span>
        </button>
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="drop"
          disabled={@catch_disabled?}
          aria-label="Record a drop"
          class={[
            "min-h-11 px-3 py-1.5 rounded-lg",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold",
            "bg-error text-error-content active:bg-error/80",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-arrow-down-tray" class="size-4" />
          <span>Drop</span>
        </button>
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="goal"
          disabled={@catch_disabled?}
          aria-label="Record a goal"
          class={[
            "min-h-11 px-3 py-1.5 rounded-lg",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold",
            "bg-primary text-primary-content active:bg-primary/80",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-trophy" class="size-4" />
          <span>Goal</span>
        </button>
      </div>

      <%!-- Throwaway / Stall — passer-only, calls-style. --%>
      <div class="grid grid-cols-2 gap-2">
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="throwaway"
          disabled={@passer_only_disabled?}
          aria-label="Record a throwaway"
          class={[
            "min-h-9 px-2 py-1 rounded-md border border-base-300",
            "inline-flex items-center justify-center gap-1.5",
            "text-sm font-semibold bg-base-100 text-base-content active:bg-base-200",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          <.icon name="hero-arrow-path-rounded-square" class="size-4" />
          <span>Throwaway</span>
        </button>
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="stall"
          disabled={@passer_only_disabled?}
          aria-label="Record a stall"
          class={[
            "min-h-9 px-2 py-1 rounded-md border border-base-300",
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
    </div>
    """
  end

  attr :on_field, :list, required: true
  attr :selected_defender_id, :any, required: true
  attr :disconnected?, :boolean, required: true

  defp their_possession_view(assigns) do
    defender_set? = not is_nil(assigns.selected_defender_id)
    assigns = assign(assigns, :defender_set?, defender_set?)

    ~H"""
    <div class="space-y-2">
      <h3 class="text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
        Actions from our team
      </h3>

      <ul
        class="-mx-4 border-y border-base-200 divide-y divide-base-200"
        role="list"
        aria-label="On-field defenders"
      >
        <li :for={member <- @on_field}>
          <button
            type="button"
            phx-click="set_defender"
            phx-value-id={member.user_id}
            aria-pressed={to_string(@selected_defender_id == member.user_id)}
            class={[
              "w-full min-h-9 px-4 py-0.5 flex items-center gap-2 text-left",
              "transition-colors motion-reduce:transition-none active:bg-base-200",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              if(@selected_defender_id == member.user_id, do: "bg-primary/10", else: "")
            ]}
          >
            <span
              class={[
                "tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full text-[11px] shrink-0",
                if(@selected_defender_id == member.user_id,
                  do: "bg-primary text-primary-content",
                  else: "bg-base-200 text-base-content"
                )
              ]}
              aria-hidden="true"
            >
              {member.jersey_number}
            </span>
            <span class="font-medium text-sm truncate flex-1 leading-tight">
              {User.display_name(member.user)}
            </span>
            <.icon
              :if={@selected_defender_id == member.user_id}
              name="hero-check-circle-solid"
              class="size-4 text-primary shrink-0"
            />
          </button>
        </li>

        <li>
          <button
            type="button"
            phx-click="set_defender"
            phx-value-id="unknown"
            aria-pressed={to_string(@selected_defender_id == :unknown)}
            class={[
              "w-full min-h-9 px-4 py-0.5 flex items-center gap-2 text-left italic",
              "border-t-2 border-dashed border-base-300",
              "transition-colors motion-reduce:transition-none active:bg-base-200",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              if(@selected_defender_id == :unknown, do: "bg-primary/10", else: "")
            ]}
          >
            <span
              class="inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-xs shrink-0"
              aria-hidden="true"
            >
              ?
            </span>
            <span class="font-medium text-sm flex-1 leading-tight">Unknown</span>
            <.icon
              :if={@selected_defender_id == :unknown}
              name="hero-check-circle-solid"
              class="size-4 text-primary shrink-0"
            />
          </button>
        </li>
      </ul>

      <div class="grid grid-cols-2 gap-2">
        <button
          type="button"
          phx-click="record_defense"
          phx-value-kind="block"
          disabled={@disconnected? or not @defender_set?}
          aria-label="Record a block"
          class={[
            "min-h-11 px-3 py-2 rounded-xl",
            "flex items-center justify-center gap-2",
            "text-base font-semibold bg-primary text-primary-content",
            "active:scale-[0.98] motion-reduce:active:scale-100 active:bg-primary/80",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100"
          ]}
        >
          <.icon name="hero-shield-check" class="size-5" />
          <span>Block</span>
        </button>
        <button
          type="button"
          phx-click="record_defense"
          phx-value-kind="catch"
          disabled={@disconnected? or not @defender_set?}
          aria-label="Record an interception"
          class={[
            "min-h-11 px-3 py-2 rounded-xl",
            "flex items-center justify-center gap-2",
            "text-base font-semibold bg-success text-success-content",
            "active:scale-[0.98] motion-reduce:active:scale-100 active:bg-success/80",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100"
          ]}
        >
          <.icon name="hero-check" class="size-5" />
          <span>Catch</span>
        </button>
      </div>

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

  attr :disconnected?, :boolean, required: true

  defp calls_bar(assigns) do
    ~H"""
    <div class="space-y-1" aria-label="Calls">
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
    """
  end

  attr :game, :map, required: true
  attr :current_point, :any, required: true
  attr :selected_user_ids, :any, required: true
  attr :team_players, :list, required: true
  attr :disconnected?, :boolean, required: true

  defp bottom_action_bar(assigns) do
    ~H"""
    <div
      :if={@game.status != :finished and is_nil(@current_point)}
      class="sticky bottom-0 px-4 pb-safe bg-base-100/95 backdrop-blur border-t border-base-200"
    >
      <div class="py-3">
        <button
          type="button"
          phx-click="start_point"
          disabled={MapSet.size(@selected_user_ids) == 0 or @disconnected?}
          class={[
            "w-full min-h-14 rounded-xl px-4 py-3",
            "text-lg font-semibold",
            "bg-primary text-primary-content",
            "transition-colors motion-reduce:transition-none",
            "active:scale-[0.99] active:bg-primary/80 motion-reduce:active:scale-100",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100",
            "inline-flex items-center justify-center gap-3"
          ]}
        >
          <span>Start point</span>
          <span class="text-sm font-medium tabular-nums opacity-90 inline-flex items-center gap-2">
            <span aria-hidden="true">♂</span> {selected_role_count(
              @selected_user_ids,
              @team_players,
              :male_matching
            )}
            <span aria-hidden="true">♀</span> {selected_role_count(
              @selected_user_ids,
              @team_players,
              :female_matching
            )}
          </span>
        </button>
      </div>
    </div>
    """
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
     |> assign(:selected_preset_id, nil)}
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
         |> assign(:selected_preset_id, preset_id)}
    end
  end

  def handle_event("start_point", _params, socket) do
    user_ids = MapSet.to_list(socket.assigns.selected_user_ids)

    case Games.start_point(socket.assigns.game, user_ids) do
      {:ok, point} ->
        {:noreply,
         socket
         |> assign(:current_point, point)
         |> assign(:events, [])
         |> assign(:possession, Games.starting_possession(socket.assigns.game, point))
         |> assign(:current_passer_id, nil)
         |> assign(:selected_receiver_id, nil)
         |> assign(:selected_defender_id, nil)
         |> assign(:undo_stack, [])
         |> assign(:redo_stack, [])
         |> assign(:last_ended, nil)
         |> assign(:selected_user_ids, MapSet.new())
         |> assign(:selected_preset_id, nil)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not start point — pick at least one player.")}
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
         |> assign(:events, [])
         |> assign(:possession, nil)
         |> assign(:selected_user_ids, previous_user_ids)
         |> assign(:current_passer_id, nil)
         |> assign(:selected_receiver_id, nil)
         |> assign(:selected_defender_id, nil)
         |> assign(:undo_stack, [])
         |> assign(:redo_stack, [])
         |> assign(:last_ended, nil)
         |> put_flash(:info, "Point cancelled")}
    end
  end

  # When no current passer is set, a tap in the on-field grid sets the passer.
  def handle_event("set_passer", %{"id" => raw_id}, socket) do
    {:noreply,
     socket
     |> assign(:current_passer_id, parse_player_token(raw_id))
     |> assign(:selected_receiver_id, nil)}
  end

  # When the passer is set, a tap in the on-field grid selects the receiver.
  def handle_event("set_receiver", %{"id" => raw_id}, socket) do
    {:noreply, assign(socket, :selected_receiver_id, parse_player_token(raw_id))}
  end

  def handle_event("record_throw_outcome", %{"type" => type_str}, socket) do
    type = String.to_existing_atom(type_str)
    point = socket.assigns.current_point
    passer_id = id_or_nil(socket.assigns.current_passer_id)

    receiver_id =
      case type do
        t when t in [:throwaway, :stall] -> nil
        _ -> id_or_nil(socket.assigns.selected_receiver_id)
      end

    case Games.record_throw(point, type, passer_id, receiver_id) do
      {:ok, event} ->
        events = Games.events_for_point(point)

        socket =
          socket
          |> assign(:events, events)
          |> track_event_recorded(event)

        apply_outcome_transition(socket, type, point, events)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record event.")}
    end
  end

  def handle_event("set_defender", %{"id" => raw_id}, socket) do
    {:noreply, assign(socket, :selected_defender_id, parse_player_token(raw_id))}
  end

  # Records a defensive play with the previously-selected defender.
  #   :block  → :block event (defender = passer)
  #   :catch  → :catch event (passer = nil, defender = receiver / interceptor)
  # In both cases the defender becomes the new current passer and
  # possession derives back to :ours.
  def handle_event("record_defense", %{"kind" => kind}, socket)
      when kind in ["block", "catch"] do
    point = socket.assigns.current_point
    defender_token = socket.assigns.selected_defender_id
    defender_id = id_or_nil(defender_token)

    {type, passer_id, receiver_id} =
      case kind do
        "block" -> {:block, defender_id, nil}
        "catch" -> {:catch, nil, defender_id}
      end

    case Games.record_throw(point, type, passer_id, receiver_id) do
      {:ok, event} ->
        events = Games.events_for_point(point)

        {:noreply,
         socket
         |> assign(:events, events)
         |> track_event_recorded(event)
         |> assign(:possession, derive_possession(socket.assigns.game, point, events))
         |> assign(:current_passer_id, defender_token)
         |> assign(:selected_receiver_id, nil)
         |> assign(:selected_defender_id, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record event.")}
    end
  end

  def handle_event("record_opponent_turnover", _params, socket) do
    point = socket.assigns.current_point

    case Games.record_throw(point, :opponent_turnover, nil, nil) do
      {:ok, event} ->
        events = Games.events_for_point(point)

        {:noreply,
         socket
         |> assign(:events, events)
         |> track_event_recorded(event)
         |> assign(:possession, derive_possession(socket.assigns.game, point, events))
         |> assign(:current_passer_id, nil)
         |> assign(:selected_receiver_id, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record turnover.")}
    end
  end

  def handle_event("record_opponent_goal", _params, socket) do
    point = socket.assigns.current_point

    with {:ok, event} <- Games.record_throw(point, :opponent_goal, nil, nil),
         {:ok, _ended} <- Games.end_point(point, :theirs) do
      socket = assign(socket, :last_ended, %{point_id: point.id, event_id: event.id})
      {:noreply, after_point_end(socket)}
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record opponent goal.")}
    end
  end

  def handle_event("record_call", %{"type" => type_str}, socket) do
    type = String.to_existing_atom(type_str)

    if type in [:pick, :foul] do
      point = socket.assigns.current_point

      case Games.record_throw(point, type, nil, nil) do
        {:ok, event} ->
          events = Games.events_for_point(point)

          # Possession unchanged for calls; we still re-derive defensively
          # so the assign stays in sync if any future logic changes.
          {:noreply,
           socket
           |> assign(:events, events)
           |> track_event_recorded(event)
           |> assign(:possession, derive_possession(socket.assigns.game, point, events))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not record call.")}
      end
    else
      {:noreply, socket}
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
        with %Event{} = event <- Repo.get(Event, event_id),
             {:ok, _} <- Games.soft_delete_event(event) do
          {:noreply,
           after_history_change(socket, rest_undo, [event_id | socket.assigns.redo_stack])}
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
             {:ok, _} <- Games.restore_event(event) do
          {:noreply,
           after_history_change(socket, [event_id | socket.assigns.undo_stack], rest_redo)}
        else
          _ -> {:noreply, put_flash(socket, :error, "Could not redo.")}
        end
    end
  end

  ## ---------------------------------------------------------------------
  ## helpers — undo / redo bookkeeping
  ## ---------------------------------------------------------------------

  # Push the just-recorded event onto the undo stack and clear the redo
  # stack (a fresh action invalidates any prior redos).
  defp track_event_recorded(socket, %Event{id: event_id}) do
    socket
    |> assign(:undo_stack, [event_id | socket.assigns.undo_stack])
    |> assign(:redo_stack, [])
  end

  # Re-syncs everything that derives from the events list after an undo
  # or redo: events, possession, current passer. Selection state
  # (receiver / defender pickers) is cleared so the user starts the
  # next interaction fresh.
  defp after_history_change(socket, undo_stack, redo_stack) do
    point = socket.assigns.current_point
    events = Games.events_for_point(point)

    socket
    |> assign(:undo_stack, undo_stack)
    |> assign(:redo_stack, redo_stack)
    |> assign(:events, events)
    |> assign(:possession, derive_possession(socket.assigns.game, point, events))
    |> assign(:current_passer_id, derive_current_passer(events))
    |> assign(:selected_receiver_id, nil)
    |> assign(:selected_defender_id, nil)
  end

  # Walks the (live) events for a point and returns the current passer
  # token: a user id, `:unknown`, or `nil` for "no passer set".
  defp derive_current_passer(events) do
    Enum.reduce(events, nil, fn ev, current ->
      case ev.type do
        :catch -> token_from_id(ev.receiver_user_id)
        :block -> token_from_id(ev.passer_user_id)
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

  # After a successful `record_throw_outcome`, update assigns based on
  # the type:
  #   :catch     receiver becomes new passer, clear receiver
  #   :drop      possession flipped to :theirs (derive); clear both
  #   :throwaway/:stall — same
  #   :goal      end point :ours, transition back to between-points
  defp apply_outcome_transition(socket, :catch, point, events) do
    new_passer = socket.assigns.selected_receiver_id

    {:noreply,
     socket
     |> assign(:possession, derive_possession(socket.assigns.game, point, events))
     |> assign(:current_passer_id, new_passer)
     |> assign(:selected_receiver_id, nil)}
  end

  defp apply_outcome_transition(socket, type, point, events)
       when type in [:drop, :throwaway, :stall] do
    {:noreply,
     socket
     |> assign(:possession, derive_possession(socket.assigns.game, point, events))
     |> assign(:current_passer_id, nil)
     |> assign(:selected_receiver_id, nil)
     |> assign(:selected_defender_id, nil)}
  end

  defp apply_outcome_transition(socket, :goal, point, _events) do
    case Games.end_point(point, :ours) do
      {:ok, _ended} ->
        # The goal event we just recorded sits at the head of the undo
        # stack. Stash it so the line picker can offer "Undo last goal".
        last_event_id = List.first(socket.assigns.undo_stack)

        socket =
          assign(socket, :last_ended, %{point_id: point.id, event_id: last_event_id})

        {:noreply, after_point_end(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not end point.")}
    end
  end

  # Re-load score, current_point, and check for hard-cap auto-end.
  defp after_point_end(socket) do
    game = socket.assigns.game
    score = Games.score(game)

    socket =
      socket
      |> assign(:score, score)
      |> assign(:current_point, nil)
      |> assign(:events, [])
      |> assign(:possession, nil)
      |> assign(:current_passer_id, nil)
      |> assign(:selected_receiver_id, nil)
      |> assign(:selected_defender_id, nil)
      |> assign(:undo_stack, [])
      |> assign(:redo_stack, [])
      |> assign(:selected_user_ids, MapSet.new())
      |> assign(:selected_preset_id, nil)

    if Games.hard_cap_reached?(game) do
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
      member -> "##{member.jersey_number} #{User.display_name(member.user)}"
    end
  end

  defp passer_card_label(_, _), do: "—"

  defp passer_card_number(:unknown, _lookup), do: "?"

  defp passer_card_number(user_id, lookup) when is_binary(user_id) do
    case Map.get(lookup, user_id) do
      nil -> "?"
      member -> member.jersey_number || "?"
    end
  end

  defp passer_card_number(_, _), do: "—"

  defp passer_data_id(:unknown), do: "unknown"
  defp passer_data_id(id) when is_binary(id), do: id
  defp passer_data_id(_), do: ""

  # Highlight the row corresponding to the current passer when receiver
  # picking is active, and the row corresponding to the selected receiver
  # otherwise.
  defp receiver_active?(user_id, true, _passer_id, selected_receiver_id) do
    user_id == selected_receiver_id
  end

  defp receiver_active?(_, false, _passer_id, _), do: false

  defp receiver_disabled?(user_id, true, current_passer_id) do
    # Can't pick the same player as both passer and receiver; they
    # already have the disc.
    user_id == current_passer_id
  end

  defp receiver_disabled?(_, false, _), do: false

  defp receiver_row_classes(user_id, true, current_passer_id, selected_receiver_id) do
    cond do
      user_id == selected_receiver_id -> "bg-primary/10"
      user_id == current_passer_id -> "bg-success/15 ring-1 ring-success/40"
      true -> ""
    end
  end

  defp receiver_row_classes(_user_id, false, _current_passer_id, _selected_receiver_id), do: ""

  defp length_of_points(game) do
    case Games.get_game_with_points!(game.id).points do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp line_user_ids(nil), do: []
  defp line_user_ids(%{our_line_snapshot: %{"user_ids" => ids}}) when is_list(ids), do: ids
  defp line_user_ids(_), do: []

  defp gender_glyph(:female_matching), do: "♀"
  defp gender_glyph(:male_matching), do: "♂"
  defp gender_glyph(_), do: ""

  defp possession_label(:ours), do: "We have the disc"
  defp possession_label(:theirs), do: "They have the disc"
  defp possession_label(_), do: "Possession unknown"

  # Tints the entire sticky top area by possession state. Between points
  # (no current_point) we keep the neutral base.
  defp top_bar_classes(nil, _), do: "bg-base-100/95 border-base-200"
  defp top_bar_classes(_point, :ours), do: "bg-success/10 border-success/30"
  defp top_bar_classes(_point, :theirs), do: "bg-error/10 border-error/30"
  defp top_bar_classes(_point, _), do: "bg-base-100/95 border-base-200"

  defp possession_banner_classes(:ours), do: "bg-success/20 text-success"
  defp possession_banner_classes(:theirs), do: "bg-error/20 text-error"
  defp possession_banner_classes(_), do: "bg-base-200 text-base-content/70"

  defp possession_banner_label(:ours), do: "Our possession"
  defp possession_banner_label(:theirs), do: "Their possession"
  defp possession_banner_label(_), do: "Possession unknown"

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

  defp selected_role_count(selected_ids, members, role) do
    Enum.count(
      members,
      &(&1.user.gender_role == role and MapSet.member?(selected_ids, &1.user_id))
    )
  end

  attr :role, :atom, required: true, values: [:female_matching, :male_matching]
  attr :players, :list, required: true
  attr :selected_ids, MapSet, required: true

  defp line_picker_section(assigns) do
    selected_in_section =
      Enum.count(assigns.players, &MapSet.member?(assigns.selected_ids, &1.user_id))

    assigns = assign(assigns, :selected_in_section, selected_in_section)

    ~H"""
    <section class="space-y-1">
      <h3 class="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-wide text-base-content/60 px-4">
        <span class="text-sm leading-none" aria-hidden="true">{gender_glyph(@role)}</span>
        <span>{role_label(@role)}</span>
        <span class="tabular-nums text-base-content/50">
          {@selected_in_section} of {length(@players)}
        </span>
      </h3>

      <ul
        class="-mx-4 border-y border-base-200 divide-y divide-base-200"
        role="list"
        aria-label={role_label(@role) <> " players"}
      >
        <li :for={member <- @players} id={"line-pick-#{member.user_id}"}>
          <button
            type="button"
            phx-click="toggle_player"
            phx-value-id={member.user_id}
            aria-pressed={to_string(MapSet.member?(@selected_ids, member.user_id))}
            class={[
              "w-full min-h-9 px-4 py-0.5 flex items-center gap-2 text-left",
              "transition-colors motion-reduce:transition-none active:bg-base-200",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
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
              {member.jersey_number}
            </span>
            <span class="font-medium text-sm truncate flex-1 leading-tight">
              {User.display_name(member.user)}
            </span>
            <.icon
              :if={MapSet.member?(@selected_ids, member.user_id)}
              name="hero-check-circle-solid"
              class="size-4 text-primary shrink-0"
            />
          </button>
        </li>
      </ul>
    </section>
    """
  end
end
