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
  alias Ultistats.Teams.Player

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game = Games.get_game!(id)

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
       |> assign(:selected_player_ids, MapSet.new())
       |> assign(:selected_preset_id, nil)
       |> assign(:current_passer_id, nil)
       |> assign(:selected_receiver_id, nil)
       |> assign(:defense_kind, :block)
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
    <Layouts.app flash={@flash}>
      <p class="text-sm text-base-content/70 py-6">Loading summary…</p>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col min-h-[calc(100vh-3rem)]">
        <div
          class="sticky z-20 -mx-4 px-4 bg-base-100/95 backdrop-blur border-b border-base-200 transition-[top] duration-200 motion-reduce:transition-none"
          style="top: var(--nav-offset, 3.5rem)"
        >
          <.compact_header
            game={@game}
            score={@score}
            current_point={@current_point}
            possession={@possession}
            halftime?={Games.halftime?(@game) and not @halftime_dismissed?}
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
              disconnected?={@disconnected?}
              defense_kind={@defense_kind}
            />
          <% true -> %>
            <.between_points_view
              point_number={length_of_points(@game) + 1}
              line_presets={@line_presets}
              team_players={@team_players}
              selected_player_ids={@selected_player_ids}
              selected_preset_id={@selected_preset_id}
            />
        <% end %>

        <.bottom_action_bar
          game={@game}
          current_point={@current_point}
          selected_player_ids={@selected_player_ids}
          team_players={@team_players}
          disconnected?={@disconnected?}
        />

        <div
          :if={@current_point}
          class="sticky bottom-0 -mx-4 px-4 pb-safe bg-base-100/95 backdrop-blur border-t border-base-200"
        >
          <.calls_bar disconnected?={@disconnected?} />
        </div>
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

  defp compact_header(assigns) do
    ~H"""
    <div :if={@halftime?} class="pt-2">
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

    <div class="flex items-center justify-between gap-2 py-2">
      <button
        :if={@current_point}
        type="button"
        phx-click="cancel_current_point"
        data-confirm="You will lose all progress for this point if you go back."
        aria-label="Back to lineup (cancel point)"
        class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary shrink-0"
      >
        <.icon name="hero-arrow-uturn-left" class="size-4" />
      </button>

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

      <span
        :if={@current_point}
        class={[
          "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold shrink-0",
          case @possession do
            :ours -> "bg-success/15 text-success"
            :theirs -> "bg-error/10 text-error"
            _ -> "bg-base-200 text-base-content/70"
          end
        ]}
        aria-label={possession_label(@possession)}
      >
        <span aria-hidden="true">🥏</span>
        <span>{possession_short_label(@possession)}</span>
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
  attr :selected_player_ids, :any, required: true
  attr :selected_preset_id, :any, required: true

  defp between_points_view(assigns) do
    ~H"""
    <section class="flex-1 py-3 space-y-3" aria-label="Line picker">
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
              {length(preset.players)}
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
        <div id="game-line-picker" class="space-y-4">
          <.line_picker_section
            :for={role <- [:male_matching, :female_matching]}
            :if={Enum.any?(@team_players, &(&1.gender_role == role))}
            role={role}
            players={Enum.filter(@team_players, &(&1.gender_role == role))}
            selected_ids={@selected_player_ids}
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
  attr :disconnected?, :boolean, required: true
  attr :defense_kind, :atom, required: true, values: [:block, :catch]

  defp in_point_view(assigns) do
    line_player_ids = line_player_ids(assigns.current_point)
    on_field = Enum.filter(assigns.team_players, &(&1.id in line_player_ids))
    player_lookup = Map.new(assigns.team_players, &{&1.id, &1})

    assigns =
      assigns
      |> assign(:on_field, on_field)
      |> assign(:player_lookup, player_lookup)

    ~H"""
    <section class="flex-1 py-2 space-y-3" aria-label="Current point">
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
          disconnected?={@disconnected?}
          defense_kind={@defense_kind}
        />
      <% end %>
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
      <.current_passer_card
        current_passer_id={@current_passer_id}
        player_lookup={@player_lookup}
      />

      <p class="text-xs text-base-content/70" aria-live="polite">
        <%= if @passer_set? do %>
          Tap who caught (or attempted to catch) the throw.
        <% else %>
          Tap who has the disc.
        <% end %>
      </p>

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
      class="rounded-lg border border-base-200 divide-y divide-base-200"
      role="list"
      aria-label="On-field players"
    >
      <li :for={player <- @on_field}>
        <button
          type="button"
          phx-click={@event_name}
          phx-value-id={player.id}
          aria-pressed={
            to_string(
              receiver_active?(player.id, @passer_set?, @current_passer_id, @selected_receiver_id)
            )
          }
          disabled={receiver_disabled?(player.id, @passer_set?, @current_passer_id)}
          class={[
            "w-full min-h-9 px-2 py-0.5 flex items-center gap-2 text-left",
            "transition-colors motion-reduce:transition-none active:bg-base-200",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed",
            receiver_row_classes(player.id, @passer_set?, @current_passer_id, @selected_receiver_id)
          ]}
        >
          <span
            class={[
              "tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full text-[11px] shrink-0",
              if(player.id == @selected_receiver_id,
                do: "bg-primary text-primary-content",
                else: "bg-base-200 text-base-content"
              )
            ]}
            aria-hidden="true"
          >
            {player.jersey_number}
          </span>
          <span class="font-medium text-sm truncate flex-1 leading-tight">
            {Player.display_name(player)}
          </span>
          <.icon
            :if={player.id == @selected_receiver_id}
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
            "w-full min-h-9 px-2 py-0.5 flex items-center gap-2 text-left italic",
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
    <div class="space-y-3">
      <%!-- Catch / Drop / Goal — require both passer + receiver. --%>
      <div class="grid grid-cols-3 gap-3">
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="catch"
          disabled={@catch_disabled?}
          aria-label="Record a catch"
          class={[
            "min-h-14 px-3 py-2 rounded-xl",
            "flex flex-col items-center justify-center gap-1",
            "text-base font-semibold leading-tight",
            "bg-success text-success-content",
            "active:scale-[0.98] motion-reduce:active:scale-100 active:bg-success/80",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100"
          ]}
        >
          <.icon name="hero-check" class="size-6" />
          <span>Catch</span>
        </button>
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="drop"
          disabled={@catch_disabled?}
          aria-label="Record a drop"
          class={[
            "min-h-14 px-3 py-2 rounded-xl",
            "flex flex-col items-center justify-center gap-1",
            "text-base font-semibold leading-tight",
            "bg-error text-error-content",
            "active:scale-[0.98] motion-reduce:active:scale-100 active:bg-error/80",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100"
          ]}
        >
          <.icon name="hero-arrow-down-tray" class="size-6" />
          <span>Drop</span>
        </button>
        <.action_button
          kind={:goal}
          phx-click="record_throw_outcome"
          phx-value-type="goal"
          disabled?={@catch_disabled?}
        >
          Goal
        </.action_button>
      </div>

      <%!-- Throwaway / Stall — passer-only, receiver implicit nil. --%>
      <div class="grid grid-cols-2 gap-3">
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="throwaway"
          disabled={@passer_only_disabled?}
          aria-label="Record a throwaway"
          class={[
            "min-h-14 px-3 py-2 rounded-xl border-2 border-error/40",
            "flex items-center justify-center gap-2",
            "text-base font-semibold",
            "bg-base-100 text-error active:bg-error/10",
            "transition-colors motion-reduce:transition-none",
            "active:scale-[0.99] motion-reduce:active:scale-100",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100"
          ]}
        >
          <.icon name="hero-arrow-path-rounded-square" class="size-5" />
          <span>Throwaway</span>
        </button>
        <button
          type="button"
          phx-click="record_throw_outcome"
          phx-value-type="stall"
          disabled={@passer_only_disabled?}
          aria-label="Record a stall"
          class={[
            "min-h-14 px-3 py-2 rounded-xl border-2 border-error/40",
            "flex items-center justify-center gap-2",
            "text-base font-semibold",
            "bg-base-100 text-error active:bg-error/10",
            "transition-colors motion-reduce:transition-none",
            "active:scale-[0.99] motion-reduce:active:scale-100",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100"
          ]}
        >
          <.icon name="hero-clock" class="size-5" />
          <span>Stall</span>
        </button>
      </div>
    </div>
    """
  end

  attr :on_field, :list, required: true
  attr :disconnected?, :boolean, required: true
  attr :defense_kind, :atom, required: true, values: [:block, :catch]

  defp their_possession_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="rounded-xl bg-error/10 px-4 py-3" aria-live="polite">
        <p class="text-sm font-semibold text-error">Other team has the disc.</p>
      </div>

      <div>
        <div
          role="tablist"
          aria-label="Defensive play type"
          class="flex gap-6 border-b border-base-200 mb-2"
        >
          <button
            type="button"
            role="tab"
            id="defense-tab-block"
            aria-selected={to_string(@defense_kind == :block)}
            phx-click="set_defense_kind"
            phx-value-kind="block"
            class={defense_tab_classes(@defense_kind == :block)}
          >
            Block
          </button>
          <button
            type="button"
            role="tab"
            id="defense-tab-catch"
            aria-selected={to_string(@defense_kind == :catch)}
            phx-click="set_defense_kind"
            phx-value-kind="catch"
            class={defense_tab_classes(@defense_kind == :catch)}
          >
            Catch
          </button>
        </div>

        <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/70 mb-2">
          {defense_picker_label(@defense_kind)}
        </h3>
        <ul class="rounded-lg border border-base-200 divide-y divide-base-200" role="list">
          <li :for={player <- @on_field}>
            <button
              type="button"
              phx-click="pick_defense_player"
              phx-value-id={player.id}
              disabled={@disconnected?}
              aria-label={defense_aria_label(@defense_kind, Player.display_name(player))}
              class={[
                "w-full min-h-9 px-2 py-0.5 flex items-center gap-2 text-left",
                "transition-colors motion-reduce:transition-none active:bg-base-200",
                "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                "disabled:opacity-50 disabled:cursor-not-allowed"
              ]}
            >
              <span
                class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0"
                aria-hidden="true"
              >
                {player.jersey_number}
              </span>
              <span class="font-medium text-sm truncate flex-1 leading-tight">
                {Player.display_name(player)}
              </span>
              <.icon name={defense_kind_icon(@defense_kind)} class="size-4 text-primary shrink-0" />
            </button>
          </li>

          <li>
            <button
              type="button"
              phx-click="pick_defense_player"
              phx-value-id="unknown"
              disabled={@disconnected?}
              aria-label={defense_aria_label(@defense_kind, "Unknown")}
              class={[
                "w-full min-h-9 px-2 py-0.5 flex items-center gap-2 text-left italic",
                "border-t-2 border-dashed border-base-300",
                "transition-colors motion-reduce:transition-none active:bg-base-200",
                "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                "disabled:opacity-50 disabled:cursor-not-allowed"
              ]}
            >
              <span
                class="inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-xs shrink-0"
                aria-hidden="true"
              >
                ?
              </span>
              <span class="font-medium text-sm flex-1 leading-tight">Unknown</span>
            </button>
          </li>
        </ul>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <button
          type="button"
          phx-click="record_opponent_turnover"
          disabled={@disconnected?}
          aria-label="Record that the opponent turned the disc over"
          class={[
            "min-h-14 px-3 py-2 rounded-xl border-2 border-base-300",
            "flex items-center justify-center gap-2",
            "text-base font-semibold bg-base-100 text-base-content active:bg-base-200",
            "transition-colors motion-reduce:transition-none",
            "active:scale-[0.99] motion-reduce:active:scale-100",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100"
          ]}
        >
          <.icon name="hero-arrow-uturn-right" class="size-5" />
          <span>They turned it over</span>
        </button>
        <button
          type="button"
          phx-click="record_opponent_goal"
          disabled={@disconnected?}
          aria-label="Record that the opponent scored"
          class={[
            "min-h-14 px-3 py-2 rounded-xl",
            "flex items-center justify-center gap-2",
            "text-base font-semibold bg-error text-error-content",
            "active:scale-[0.99] motion-reduce:active:scale-100 active:bg-error/80",
            "transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100"
          ]}
        >
          <.icon name="hero-flag" class="size-5" />
          <span>They scored</span>
        </button>
      </div>
    </div>
    """
  end

  attr :disconnected?, :boolean, required: true

  defp calls_bar(assigns) do
    ~H"""
    <div class="py-2 flex items-center gap-2" aria-label="Calls">
      <span class="text-[11px] uppercase tracking-wide text-base-content/60 shrink-0">Calls</span>
      <div class="flex-1 grid grid-cols-2 gap-2">
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
  attr :selected_player_ids, :any, required: true
  attr :team_players, :list, required: true
  attr :disconnected?, :boolean, required: true

  defp bottom_action_bar(assigns) do
    ~H"""
    <div
      :if={@game.status != :finished and is_nil(@current_point)}
      class="sticky bottom-0 -mx-4 px-4 pb-safe bg-base-100/95 backdrop-blur border-t border-base-200"
    >
      <div class="py-3">
        <button
          type="button"
          phx-click="start_point"
          disabled={MapSet.size(@selected_player_ids) == 0 or @disconnected?}
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
              @selected_player_ids,
              @team_players,
              :male_matching
            )}
            <span aria-hidden="true">♀</span> {selected_role_count(
              @selected_player_ids,
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
  def handle_event("toggle_player", %{"id" => player_id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_player_ids, player_id) do
        MapSet.delete(socket.assigns.selected_player_ids, player_id)
      else
        MapSet.put(socket.assigns.selected_player_ids, player_id)
      end

    {:noreply,
     socket
     |> assign(:selected_player_ids, selected)
     |> assign(:selected_preset_id, nil)}
  end

  def handle_event("select_preset", %{"id" => preset_id}, socket) do
    case Enum.find(socket.assigns.line_presets, &(&1.id == preset_id)) do
      nil ->
        {:noreply, socket}

      preset ->
        ids = Enum.map(preset.players, & &1.id) |> MapSet.new()

        {:noreply,
         socket
         |> assign(:selected_player_ids, ids)
         |> assign(:selected_preset_id, preset_id)}
    end
  end

  def handle_event("start_point", _params, socket) do
    player_ids = MapSet.to_list(socket.assigns.selected_player_ids)

    case Games.start_point(socket.assigns.game, player_ids) do
      {:ok, point} ->
        {:noreply,
         socket
         |> assign(:current_point, point)
         |> assign(:events, [])
         |> assign(:possession, Games.starting_possession(socket.assigns.game, point))
         |> assign(:current_passer_id, nil)
         |> assign(:selected_receiver_id, nil)
         |> assign(:selected_player_ids, MapSet.new())
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
        previous_player_ids =
          point.our_line_snapshot
          |> Map.get("player_ids", [])
          |> MapSet.new()

        {:ok, _} = Repo.delete(point)

        {:noreply,
         socket
         |> assign(:current_point, nil)
         |> assign(:events, [])
         |> assign(:possession, nil)
         |> assign(:selected_player_ids, previous_player_ids)
         |> assign(:current_passer_id, nil)
         |> assign(:selected_receiver_id, nil)
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
      {:ok, _event} ->
        events = Games.events_for_point(point)

        socket = assign(socket, :events, events)
        apply_outcome_transition(socket, type, point, events)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record event.")}
    end
  end

  def handle_event("set_defense_kind", %{"kind" => kind}, socket)
      when kind in ["block", "catch"] do
    {:noreply, assign(socket, :defense_kind, String.to_existing_atom(kind))}
  end

  # Branches on `@defense_kind`:
  #   :block  → record :block (passer = our defender)
  #   :catch  → record :catch (passer = nil, receiver = our interceptor)
  # In both cases the picked player becomes the new current passer and
  # possession derives back to :ours.
  def handle_event("pick_defense_player", %{"id" => raw_id}, socket) do
    point = socket.assigns.current_point
    picked_token = parse_player_token(raw_id)
    picked_id = id_or_nil(picked_token)

    {type, passer_id, receiver_id} =
      case socket.assigns.defense_kind do
        :block -> {:block, picked_id, nil}
        :catch -> {:catch, nil, picked_id}
      end

    case Games.record_throw(point, type, passer_id, receiver_id) do
      {:ok, _event} ->
        events = Games.events_for_point(point)

        {:noreply,
         socket
         |> assign(:events, events)
         |> assign(:possession, derive_possession(socket.assigns.game, point, events))
         |> assign(:current_passer_id, picked_token)
         |> assign(:selected_receiver_id, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record event.")}
    end
  end

  def handle_event("record_opponent_turnover", _params, socket) do
    point = socket.assigns.current_point

    case Games.record_throw(point, :opponent_turnover, nil, nil) do
      {:ok, _event} ->
        events = Games.events_for_point(point)

        {:noreply,
         socket
         |> assign(:events, events)
         |> assign(:possession, derive_possession(socket.assigns.game, point, events))
         |> assign(:current_passer_id, nil)
         |> assign(:selected_receiver_id, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record turnover.")}
    end
  end

  def handle_event("record_opponent_goal", _params, socket) do
    point = socket.assigns.current_point

    with {:ok, _event} <- Games.record_throw(point, :opponent_goal, nil, nil),
         {:ok, _ended} <- Games.end_point(point, :theirs) do
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
        {:ok, _event} ->
          events = Games.events_for_point(point)

          # Possession unchanged for calls; we still re-derive defensively
          # so the assign stays in sync if any future logic changes.
          {:noreply,
           socket
           |> assign(:events, events)
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
     |> assign(:selected_receiver_id, nil)}
  end

  defp apply_outcome_transition(socket, :goal, point, _events) do
    case Games.end_point(point, :ours) do
      {:ok, _ended} ->
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
      |> assign(:selected_player_ids, MapSet.new())
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

  defp passer_card_label(player_id, lookup) when is_binary(player_id) do
    case Map.get(lookup, player_id) do
      nil -> "Unknown"
      player -> "##{player.jersey_number} #{Player.display_name(player)}"
    end
  end

  defp passer_card_label(_, _), do: "—"

  defp passer_card_number(:unknown, _lookup), do: "?"

  defp passer_card_number(player_id, lookup) when is_binary(player_id) do
    case Map.get(lookup, player_id) do
      nil -> "?"
      player -> player.jersey_number || "?"
    end
  end

  defp passer_card_number(_, _), do: "—"

  defp passer_data_id(:unknown), do: "unknown"
  defp passer_data_id(id) when is_binary(id), do: id
  defp passer_data_id(_), do: ""

  # Highlight the row corresponding to the current passer when receiver
  # picking is active, and the row corresponding to the selected receiver
  # otherwise.
  defp receiver_active?(player_id, true, _passer_id, selected_receiver_id) do
    player_id == selected_receiver_id
  end

  defp receiver_active?(_, false, _passer_id, _), do: false

  defp receiver_disabled?(player_id, true, current_passer_id) do
    # Can't pick the same player as both passer and receiver; they
    # already have the disc.
    player_id == current_passer_id
  end

  defp receiver_disabled?(_, false, _), do: false

  defp receiver_row_classes(player_id, true, current_passer_id, selected_receiver_id) do
    cond do
      player_id == selected_receiver_id -> "bg-primary/10"
      player_id == current_passer_id -> "bg-success/15 ring-1 ring-success/40"
      true -> ""
    end
  end

  defp receiver_row_classes(_player_id, false, _current_passer_id, _selected_receiver_id), do: ""

  defp length_of_points(game) do
    case Games.get_game_with_points!(game.id).points do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp line_player_ids(nil), do: []
  defp line_player_ids(%{our_line_snapshot: %{"player_ids" => ids}}) when is_list(ids), do: ids
  defp line_player_ids(_), do: []

  defp defense_tab_classes(true),
    do:
      "min-h-11 inline-flex items-center pb-2 -mb-px text-sm font-semibold text-primary border-b-2 border-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp defense_tab_classes(false),
    do:
      "min-h-11 inline-flex items-center pb-2 -mb-px text-sm font-medium text-base-content/60 hover:text-base-content border-b-2 border-transparent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp defense_picker_label(:block), do: "Tap who blocked it"
  defp defense_picker_label(:catch), do: "Tap who caught it"

  defp defense_kind_icon(:block), do: "hero-shield-check"
  defp defense_kind_icon(:catch), do: "hero-check"

  defp defense_aria_label(:block, name), do: "Record block by #{name}"
  defp defense_aria_label(:catch, name), do: "Record interception by #{name}"

  defp gender_glyph(:female_matching), do: "♀"
  defp gender_glyph(:male_matching), do: "♂"
  defp gender_glyph(_), do: ""

  defp possession_label(:ours), do: "We have the disc"
  defp possession_label(:theirs), do: "They have the disc"
  defp possession_label(_), do: "Possession unknown"

  defp possession_short_label(:ours), do: "Ours"
  defp possession_short_label(:theirs), do: "Theirs"
  defp possession_short_label(_), do: "—"

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

  defp selected_role_count(selected_ids, players, role) do
    Enum.count(players, &(&1.gender_role == role and MapSet.member?(selected_ids, &1.id)))
  end

  attr :role, :atom, required: true, values: [:female_matching, :male_matching]
  attr :players, :list, required: true
  attr :selected_ids, MapSet, required: true

  defp line_picker_section(assigns) do
    selected_in_section =
      Enum.count(assigns.players, &MapSet.member?(assigns.selected_ids, &1.id))

    assigns = assign(assigns, :selected_in_section, selected_in_section)

    ~H"""
    <section>
      <h3 class="flex items-center gap-2 text-base font-semibold text-base-content mb-1">
        <span class="text-lg leading-none" aria-hidden="true">{gender_glyph(@role)}</span>
        <span>{role_label(@role)}</span>
        <span class="tabular-nums text-sm font-medium text-base-content/60">
          {@selected_in_section} of {length(@players)}
        </span>
      </h3>

      <ul class="divide-y divide-base-200">
        <li :for={player <- @players} id={"line-pick-#{player.id}"}>
          <button
            type="button"
            phx-click="toggle_player"
            phx-value-id={player.id}
            aria-pressed={to_string(MapSet.member?(@selected_ids, player.id))}
            class={[
              "w-full flex items-center justify-between gap-3 py-2 px-2 -mx-2 rounded-md",
              "text-left transition-colors motion-reduce:transition-none",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              if(MapSet.member?(@selected_ids, player.id),
                do: "bg-primary/10 hover:bg-primary/15",
                else: "hover:bg-base-200"
              )
            ]}
          >
            <div class="flex items-center gap-3 min-w-0">
              <span
                :if={player.jersey_number}
                class="inline-flex items-center justify-center w-8 h-7 px-1 rounded-full bg-base-200 text-base-content text-sm font-semibold tabular-nums shrink-0"
              >
                {player.jersey_number}
              </span>
              <span class="font-medium truncate">{Player.display_name(player)}</span>
            </div>
            <.icon
              :if={MapSet.member?(@selected_ids, player.id)}
              name="hero-check-circle-solid"
              class="size-5 text-primary shrink-0"
            />
            <span
              :if={!MapSet.member?(@selected_ids, player.id)}
              class="size-5 shrink-0"
              aria-hidden="true"
            />
          </button>
        </li>
      </ul>
    </section>
    """
  end
end
