defmodule UltistatsWeb.GameLive.Show do
  @moduledoc """
  Live game tracker — the per-point loop with score header, line picker,
  bottom action bar, and player-attribution modal. Conforms to
  `docs/UI_DESIGN.md`.

  Render branches off three pieces of state:

    * `game.status == :finished`        terminal "game over" view
    * `current_point != nil`            in-point view (action bar enabled)
    * otherwise                         between-points line picker

  An overlay modal is rendered on top whenever `pending_event != nil`.
  """
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Teams}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game = Games.get_game!(id)
    team_players = Teams.list_players_for_team(game.team_id)
    line_presets = Teams.list_line_presets_for_team(game.team_id)
    current_point = Games.current_point(game)
    score = Games.score(game)
    events = if current_point, do: Games.events_for_point(current_point), else: []

    {:ok,
     socket
     |> assign(:page_title, "Game vs #{game.opponent_name}")
     |> assign(:game, game)
     |> assign(:team_players, team_players)
     |> assign(:line_presets, line_presets)
     |> assign(:current_point, current_point)
     |> assign(:score, score)
     |> assign(:events, events)
     |> assign(:selected_player_ids, MapSet.new())
     |> assign(:selected_preset_id, nil)
     |> assign(:pending_event, nil)
     |> assign(:pending_goal_player_id, nil)
     |> assign(:halftime_dismissed?, false)
     # Disconnect-driven button-disable is a TODO; the connectivity flash
     # banner from `Layouts.flash_group/1` already covers visual feedback.
     # See task notes — leaving the assign at false until we wire a JS hook.
     |> assign(:disconnected?, false)}
  end

  ## ---------------------------------------------------------------------
  ## render
  ## ---------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col min-h-[calc(100vh-3rem)]">
        <.score_header
          game={@game}
          score={@score}
          current_point={@current_point}
          halftime?={Games.halftime?(@game) and not @halftime_dismissed?}
          disconnected?={@disconnected?}
          finished?={@game.status == :finished}
        />

        <%= cond do %>
          <% @game.status == :finished -> %>
            <.finished_view game={@game} score={@score} />
          <% @current_point -> %>
            <.in_point_view
              current_point={@current_point}
              team_players={@team_players}
              events={@events}
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
          disconnected?={@disconnected?}
          pending_event={@pending_event}
        />
      </div>

      <.player_picker_modal
        :if={@pending_event}
        pending_event={@pending_event}
        pending_goal_player_id={@pending_goal_player_id}
        current_point={@current_point}
        team_players={@team_players}
      />
    </Layouts.app>
    """
  end

  ## ---------------------------------------------------------------------
  ## sub-renderers
  ## ---------------------------------------------------------------------

  # Sticky top header per UI_DESIGN.md §Layout. Safe-area inset top
  # respected via pt-safe.
  attr :game, :map, required: true
  attr :score, :map, required: true
  attr :current_point, :any, required: true
  attr :halftime?, :boolean, required: true
  attr :disconnected?, :boolean, required: true
  attr :finished?, :boolean, required: true

  defp score_header(assigns) do
    ~H"""
    <div class="sticky top-0 z-20 -mx-4 px-4 pt-safe bg-base-100/95 backdrop-blur border-b border-base-200">
      <div :if={@halftime?} class="mb-2">
        <div
          role="status"
          class="flex items-center gap-2 rounded-lg bg-warning text-warning-content px-3 py-2 text-sm"
        >
          <.icon name="hero-flag-solid" class="size-5 shrink-0" />
          <span class="flex-1 font-semibold tabular-nums">
            Halftime — score is {@score.ours}–{@score.theirs}
          </span>
          <button
            type="button"
            phx-click="dismiss_halftime"
            aria-label="Dismiss halftime banner"
            class="min-h-11 min-w-11 inline-flex items-center justify-center rounded-md active:bg-warning-content/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
      </div>

      <div class="flex items-start justify-between gap-3 py-3">
        <div class="flex flex-col gap-1 min-w-0">
          <.score_readout our_score={@score.ours} their_score={@score.theirs} />
          <p class="text-xs text-base-content/70 truncate">
            vs {@game.opponent_name}
          </p>
        </div>
        <button
          type="button"
          phx-click="they_scored"
          disabled={is_nil(@current_point) or @disconnected? or @finished?}
          aria-label="Record that the other team scored"
          class={[
            "min-h-11 px-3 py-2 rounded-lg text-sm font-semibold",
            "border-2 border-base-300 bg-base-100 text-base-content",
            "active:bg-base-200 transition-colors motion-reduce:transition-none",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
            "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        >
          They scored
        </button>
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
    <section class="flex-1 py-4 space-y-6" aria-label="Line picker">
      <div>
        <h2 class="text-lg font-semibold mb-2">Pick line for point {@point_number}</h2>
        <p class="text-sm text-base-content/70">
          Tap a preset, or pick players one-by-one below.
        </p>
      </div>

      <div :if={@line_presets != []} class="space-y-2">
        <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
          Line presets
        </h3>
        <div class="grid grid-cols-1 gap-2">
          <.line_preset_card
            :for={preset <- @line_presets}
            preset={%{name: preset.name, players: preset.players}}
            selected?={@selected_preset_id == preset.id}
            phx-click="select_preset"
            phx-value-id={preset.id}
          />
        </div>
      </div>

      <div class="space-y-2">
        <div class="flex items-baseline justify-between">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
            Roster
          </h3>
          <span class="text-sm text-base-content/70 tabular-nums">
            {MapSet.size(@selected_player_ids)} selected
          </span>
        </div>

        <%= if @team_players == [] do %>
          <div class="rounded-lg border-2 border-dashed border-base-300 p-6 text-center">
            <p class="text-base font-medium">No players on this team yet.</p>
            <p class="text-sm text-base-content/70 mt-1">
              Add players to the team's roster to start tracking points.
            </p>
          </div>
        <% else %>
          <div class="flex flex-wrap gap-2">
            <.player_chip
              :for={player <- @team_players}
              player={%{number: player.jersey_number, name: player.name}}
              selected?={MapSet.member?(@selected_player_ids, player.id)}
              phx-click="toggle_player"
              phx-value-id={player.id}
            />
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  attr :current_point, :map, required: true
  attr :team_players, :list, required: true
  attr :events, :list, required: true

  defp in_point_view(assigns) do
    line_player_ids = line_player_ids(assigns.current_point)
    on_field = Enum.filter(assigns.team_players, &(&1.id in line_player_ids))
    player_lookup = Map.new(assigns.team_players, &{&1.id, &1})
    recent = assigns.events |> Enum.reverse() |> Enum.take(5)

    assigns =
      assigns
      |> assign(:on_field, on_field)
      |> assign(:player_lookup, player_lookup)
      |> assign(:recent_events, recent)

    ~H"""
    <section class="flex-1 py-4 space-y-6" aria-label="Current point">
      <div class="space-y-2">
        <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
          On the field
        </h3>
        <div class="flex flex-wrap gap-2">
          <.player_chip
            :for={player <- @on_field}
            player={%{number: player.jersey_number, name: player.name}}
            selected?={true}
            disabled?={true}
          />
        </div>
      </div>

      <div class="space-y-2">
        <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
          Recent events
        </h3>
        <%= if @recent_events == [] do %>
          <p class="text-sm text-base-content/70 italic">
            No events yet — tap an action below.
          </p>
        <% else %>
          <ul class="divide-y divide-base-200 rounded-lg border border-base-200">
            <li :for={ev <- @recent_events} class="flex items-center gap-3 px-3 py-2">
              <.icon
                name={event_icon(ev.type)}
                class={["size-5 shrink-0", event_icon_class(ev.type)]}
              />
              <span class="font-semibold capitalize text-sm">{ev.type}</span>
              <span class="flex-1 text-sm truncate text-base-content/80">
                {player_label(@player_lookup, ev.player_id)}
              </span>
              <time class="tabular-nums text-xs text-base-content/60 shrink-0">
                {format_time(ev.occurred_at)}
              </time>
            </li>
          </ul>
        <% end %>
      </div>
    </section>
    """
  end

  attr :game, :map, required: true
  attr :current_point, :any, required: true
  attr :selected_player_ids, :any, required: true
  attr :disconnected?, :boolean, required: true
  attr :pending_event, :any, required: true

  defp bottom_action_bar(assigns) do
    ~H"""
    <div
      :if={@game.status != :finished}
      class="sticky bottom-0 -mx-4 px-4 pb-safe bg-base-100/95 backdrop-blur border-t border-base-200"
    >
      <div class="py-3">
        <%= if @current_point do %>
          <%!-- 4x action buttons. ≥56px tap target enforced by action_button. 12px gap per UI_DESIGN.md §Tap targets. --%>
          <div class="grid grid-cols-4 gap-3">
            <.action_button
              kind={:goal}
              phx-click="open_picker"
              phx-value-kind="goal"
              disabled?={@disconnected? or not is_nil(@pending_event)}
            >
              Goal
            </.action_button>
            <.action_button
              kind={:assist}
              phx-click="open_picker"
              phx-value-kind="assist"
              disabled?={@disconnected? or not is_nil(@pending_event)}
            >
              Assist
            </.action_button>
            <.action_button
              kind={:block}
              phx-click="open_picker"
              phx-value-kind="block"
              disabled?={@disconnected? or not is_nil(@pending_event)}
            >
              Block
            </.action_button>
            <.action_button
              kind={:turn}
              phx-click="open_picker"
              phx-value-kind="turn"
              disabled?={@disconnected? or not is_nil(@pending_event)}
            >
              Turn
            </.action_button>
          </div>
        <% else %>
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
              "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100"
            ]}
          >
            Start point
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  # Player picker modal. We don't use `<.modal>` from core_components
  # because it's not present in this project — we build a focus-trapped
  # backdrop overlay with daisyUI tokens instead. The Cancel button
  # provides explicit dismissal; tapping the backdrop also cancels.
  attr :pending_event, :any, required: true
  attr :pending_goal_player_id, :any, required: true
  attr :current_point, :any, required: true
  attr :team_players, :list, required: true

  defp player_picker_modal(assigns) do
    line_ids = line_player_ids(assigns.current_point)
    on_field = Enum.filter(assigns.team_players, &(&1.id in line_ids))

    {title, mode} = picker_title(assigns.pending_event)

    assigns =
      assigns
      |> assign(:title, title)
      |> assign(:mode, mode)
      |> assign(:on_field, on_field)

    ~H"""
    <div
      id="player-picker-modal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby="player-picker-title"
    >
      <div
        class="absolute inset-0 bg-black/50"
        phx-click="cancel_picker"
        aria-hidden="true"
      />
      <div class="relative z-10 w-full sm:max-w-md bg-base-100 rounded-t-2xl sm:rounded-2xl shadow-xl pb-safe">
        <div class="p-4 border-b border-base-200 flex items-center justify-between">
          <h2 id="player-picker-title" class="text-lg font-semibold">
            {@title}
          </h2>
          <button
            type="button"
            phx-click="cancel_picker"
            aria-label="Cancel"
            class="min-h-11 min-w-11 inline-flex items-center justify-center rounded-md active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="p-4 space-y-3 max-h-[60vh] overflow-y-auto">
          <div class="flex flex-wrap gap-2">
            <.player_chip
              :for={player <- @on_field}
              player={%{number: player.jersey_number, name: player.name}}
              phx-click={picker_event_name(@mode)}
              phx-value-id={player.id}
            />
          </div>

          <%= if @mode == :goal_assist do %>
            <button
              type="button"
              phx-click="skip_assist"
              class={[
                "w-full min-h-14 rounded-xl border-2 border-base-300",
                "text-base font-semibold bg-base-100 text-base-content",
                "active:bg-base-200 transition-colors motion-reduce:transition-none",
                "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              ]}
            >
              Skip — no assist
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Terminal "game over" view. Task 11 replaces this with the proper
  # summary route at `/games/:id/summary`.
  attr :game, :map, required: true
  attr :score, :map, required: true

  defp finished_view(assigns) do
    ~H"""
    <section class="flex-1 py-8 space-y-4 text-center" aria-label="Game finished">
      <.icon name="hero-trophy-solid" class="size-12 text-success mx-auto" />
      <h2 class="text-2xl font-bold">Game finished</h2>
      <p class="text-lg tabular-nums">
        Final score: <span class="font-bold">{@score.ours}–{@score.theirs}</span>
        vs {@game.opponent_name}
      </p>
      <p class="text-sm text-base-content/70">
        Per-player tallies will land with the summary screen.
      </p>
      <div class="pt-2">
        <.button navigate={~p"/teams/#{@game.team_id}"}>
          <.icon name="hero-arrow-left" /> Back to team
        </.button>
      </div>
    </section>
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
         |> assign(:selected_player_ids, MapSet.new())
         |> assign(:selected_preset_id, nil)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not start point — pick at least one player.")}
    end
  end

  def handle_event("open_picker", %{"kind" => kind}, socket) do
    case socket.assigns.current_point do
      nil ->
        {:noreply, socket}

      _point ->
        {:noreply,
         socket
         |> assign(:pending_event, String.to_existing_atom(kind))
         |> assign(:pending_goal_player_id, nil)}
    end
  end

  def handle_event("cancel_picker", _params, socket) do
    {:noreply,
     socket
     |> assign(:pending_event, nil)
     |> assign(:pending_goal_player_id, nil)}
  end

  # Goal flow: record goal event, then prompt for assist before ending
  # the point.
  def handle_event("pick_goal_scorer", %{"id" => player_id}, socket) do
    point = socket.assigns.current_point

    case Games.record_event(point, :goal, player_id) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> assign(:pending_event, :goal_assist)
         |> assign(:pending_goal_player_id, player_id)
         |> assign(:events, Games.events_for_point(point))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record goal.")}
    end
  end

  def handle_event("pick_goal_assister", %{"id" => player_id}, socket) do
    point = socket.assigns.current_point

    case Games.record_event(point, :assist, player_id) do
      {:ok, _event} ->
        {:noreply, finalize_our_goal(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record assist.")}
    end
  end

  def handle_event("skip_assist", _params, socket) do
    {:noreply, finalize_our_goal(socket)}
  end

  # Standalone assist: rare, but supported (action_button kind={:assist}
  # exists per UI_DESIGN.md §Components). Doesn't end the point.
  def handle_event("pick_standalone_assist", %{"id" => player_id}, socket) do
    point = socket.assigns.current_point

    case Games.record_event(point, :assist, player_id) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> assign(:pending_event, nil)
         |> assign(:events, Games.events_for_point(point))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record assist.")}
    end
  end

  def handle_event("pick_block", %{"id" => player_id}, socket) do
    record_non_terminal_event(socket, :block, player_id)
  end

  def handle_event("pick_turn", %{"id" => player_id}, socket) do
    record_non_terminal_event(socket, :turn, player_id)
  end

  def handle_event("they_scored", _params, socket) do
    case socket.assigns.current_point do
      nil ->
        {:noreply, socket}

      point ->
        case Games.end_point(point, :theirs) do
          {:ok, _ended} ->
            {:noreply, after_point_end(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not end point.")}
        end
    end
  end

  def handle_event("dismiss_halftime", _params, socket) do
    {:noreply, assign(socket, :halftime_dismissed?, true)}
  end

  ## ---------------------------------------------------------------------
  ## helpers
  ## ---------------------------------------------------------------------

  defp record_non_terminal_event(socket, type, player_id) do
    point = socket.assigns.current_point

    case Games.record_event(point, type, player_id) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> assign(:pending_event, nil)
         |> assign(:events, Games.events_for_point(point))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record event.")}
    end
  end

  defp finalize_our_goal(socket) do
    point = socket.assigns.current_point

    case Games.end_point(point, :ours) do
      {:ok, _ended} ->
        socket
        |> assign(:pending_event, nil)
        |> assign(:pending_goal_player_id, nil)
        |> after_point_end()

      {:error, _} ->
        socket
        |> assign(:pending_event, nil)
        |> put_flash(:error, "Could not end point.")
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
      |> assign(:selected_player_ids, MapSet.new())
      |> assign(:selected_preset_id, nil)

    if Games.hard_cap_reached?(game) do
      case Games.end_game(game) do
        {:ok, finished} -> assign(socket, :game, finished)
        _ -> socket
      end
    else
      socket
    end
  end

  defp length_of_points(game) do
    case Games.get_game_with_points!(game.id).points do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp line_player_ids(nil), do: []

  defp line_player_ids(%{our_line_snapshot: %{"player_ids" => ids}}) when is_list(ids), do: ids
  defp line_player_ids(_), do: []

  defp picker_title(:goal), do: {"Who scored?", :goal}
  defp picker_title(:goal_assist), do: {"Who got the assist?", :goal_assist}
  defp picker_title(:assist), do: {"Who assisted?", :assist}
  defp picker_title(:block), do: {"Who got the block?", :block}
  defp picker_title(:turn), do: {"Who turned it?", :turn}
  defp picker_title(_), do: {"Pick a player", :unknown}

  defp picker_event_name(:goal), do: "pick_goal_scorer"
  defp picker_event_name(:goal_assist), do: "pick_goal_assister"
  defp picker_event_name(:assist), do: "pick_standalone_assist"
  defp picker_event_name(:block), do: "pick_block"
  defp picker_event_name(:turn), do: "pick_turn"
  defp picker_event_name(_), do: "cancel_picker"

  defp event_icon(:goal), do: "hero-trophy"
  defp event_icon(:assist), do: "hero-hand-thumb-up"
  defp event_icon(:block), do: "hero-shield-check"
  defp event_icon(:turn), do: "hero-arrow-path-rounded-square"
  defp event_icon(_), do: "hero-bolt"

  defp event_icon_class(:goal), do: "text-success"
  defp event_icon_class(:assist), do: "text-info"
  defp event_icon_class(:block), do: "text-primary"
  defp event_icon_class(:turn), do: "text-error"
  defp event_icon_class(_), do: "text-base-content"

  defp player_label(_lookup, nil), do: "—"

  defp player_label(lookup, player_id) do
    case Map.get(lookup, player_id) do
      nil -> "—"
      player -> "##{player.jersey_number} #{player.name}"
    end
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  defp format_time(_), do: ""
end
