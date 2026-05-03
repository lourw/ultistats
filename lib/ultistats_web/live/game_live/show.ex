defmodule UltistatsWeb.GameLive.Show do
  @moduledoc """
  Live game tracker — the per-point loop with score header, line picker,
  bottom action bar, and player-attribution modal. Conforms to
  `docs/UI_DESIGN.md`.

  Render branches off two pieces of state:

    * `current_point != nil`            in-point view (action bar enabled)
    * otherwise                         between-points line picker

  When the game is `:finished` (either pre-existing on mount or auto-ended
  by a hard-cap goal), we `push_navigate` to `/games/:id/summary` rather
  than render a terminal placeholder here — the summary screen owns the
  post-game UX (`docs/MVP_SPEC.md` step 6).

  An overlay modal is rendered on top whenever `pending_event != nil`.
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
       |> assign(:pending_event, nil)
       |> assign(:pending_goal_player_id, nil)
       |> assign(:halftime_dismissed?, false)
       # Disconnect-driven button-disable is a TODO; the connectivity flash
       # banner from `Layouts.flash_group/1` already covers visual feedback.
       # See task notes — leaving the assign at false until we wire a JS hook.
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
        <div class="sticky top-14 z-20 -mx-4 px-4 bg-base-100/95 backdrop-blur border-b border-base-200">
          <.score_header
            game={@game}
            score={@score}
            current_point={@current_point}
            halftime?={Games.halftime?(@game) and not @halftime_dismissed?}
            disconnected?={@disconnected?}
            finished?={@game.status == :finished}
          />

          <.phase_stepper
            phase={phase(@game.status == :finished, @current_point)}
            events={@events}
          />

          <.possession_banner :if={@current_point} possession={@possession} />
        </div>

        <%= cond do %>
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
          team_players={@team_players}
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
    <div>
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
        <div class="flex items-center gap-2 shrink-0">
          <.link
            navigate={~p"/games/#{@game.id}/summary"}
            aria-label="Open game summary"
            class="min-h-11 min-w-11 inline-flex items-center justify-center rounded-lg border-2 border-base-300 bg-base-100 text-base-content active:bg-base-200 transition-colors motion-reduce:transition-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-chart-bar" class="size-5" />
          </.link>
          <.link
            navigate={~p"/games/#{@game.id}/timeline"}
            aria-label="Open timeline"
            class="min-h-11 min-w-11 inline-flex items-center justify-center rounded-lg border-2 border-base-300 bg-base-100 text-base-content active:bg-base-200 transition-colors motion-reduce:transition-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-list-bullet" class="size-5" />
          </.link>
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
            player={%{number: player.jersey_number, name: Player.display_name(player)}}
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
  attr :team_players, :list, required: true
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
              "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100",
              "inline-flex items-center justify-center gap-3"
            ]}
          >
            <span>Start point</span>
            <span class="text-sm font-medium tabular-nums opacity-90 inline-flex items-center gap-2">
              <span aria-hidden="true">♂</span> {selected_role_count(@selected_player_ids, @team_players, :male_matching)}
              <span aria-hidden="true">♀</span> {selected_role_count(@selected_player_ids, @team_players, :female_matching)}
            </span>
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
              player={%{number: player.jersey_number, name: Player.display_name(player)}}
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
         |> assign(:pending_event, nil)
         |> assign(:pending_goal_player_id, nil)
         |> put_flash(:info, "Point cancelled")}
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
        events = Games.events_for_point(point)

        {:noreply,
         socket
         |> assign(:pending_event, nil)
         |> assign(:events, events)
         |> assign(:possession, derive_possession(socket.assigns.game, point, events))}

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
      player -> "##{player.jersey_number} #{Player.display_name(player)}"
    end
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  defp format_time(_), do: ""

  defp gender_glyph(:female_matching), do: "♀"
  defp gender_glyph(:male_matching), do: "♂"
  defp gender_glyph(_), do: ""

  defp possession_label(:ours), do: "We have the disc"
  defp possession_label(:theirs), do: "They have the disc"
  defp possession_label(_), do: "Possession unknown"

  attr :possession, :atom, default: nil

  defp possession_banner(assigns) do
    ~H"""
    <div class="pb-3 flex justify-center">
      <div class={[
        "inline-flex items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-semibold",
        case @possession do
          :ours -> "bg-success/15 text-success"
          :theirs -> "bg-error/10 text-error"
          _ -> "bg-base-200 text-base-content/70"
        end
      ]}>
        <span class="text-base leading-none" aria-hidden="true">🥏</span>
        <span>{possession_label(@possession)}</span>
      </div>
    </div>
    """
  end

  # Possession at the start of the point comes from the pull/receive rules
  # (`Games.starting_possession/2`); each `:turn` event flips it to theirs,
  # each `:block` flips it to ours. `:goal` / `:assist` don't move the disc.
  defp derive_possession(game, point, events) do
    start = Games.starting_possession(game, point)

    Enum.reduce(events, start, fn
      %{type: :turn}, _current -> :theirs
      %{type: :block}, _current -> :ours
      _, current -> current
    end)
  end

  # ---- phase tracker (Lineup / In point / Final) -----------------------
  # Two surface options live in the score header (`phase_pill`) and above
  # the active view (`phase_stepper`). Either can be removed independently
  # by deleting its call site + component below.

  defp phase(_finished?, nil), do: :pre_pull
  defp phase(_finished?, _current_point), do: :in_point

  defp phase_label(:pre_pull), do: "Pre-pull"
  defp phase_label(:in_point), do: "In point"

  attr :phase, :atom, required: true, values: [:pre_pull, :in_point]
  attr :events, :list, default: []

  defp phase_stepper(assigns) do
    ~H"""
    <div class="my-3 flex items-center justify-center">
      <div class="relative">
        <button
          :if={@phase == :in_point}
          type="button"
          phx-click="cancel_current_point"
          data-confirm="You will lose all progress for this point if you go back."
          aria-label="Back to pre-pull (cancel point)"
          class="absolute right-full top-1/2 -translate-y-1/2 mr-2 min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content hover:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-arrow-uturn-left" class="size-4" />
        </button>

        <ol
          role="list"
          aria-label="Game phase"
          class="flex items-center justify-center gap-2 text-xs font-medium text-base-content/60 bg-base-200 rounded-lg px-3 py-2"
        >
        <li
          :for={{step, idx} <- Enum.with_index([:pre_pull, :in_point])}
          class="flex items-center gap-2"
        >
          <span class={[
            "inline-flex items-center justify-center w-5 h-5 rounded-full text-[10px] font-semibold tabular-nums",
            if(@phase == step,
              do: "bg-primary text-primary-content",
              else: "bg-base-200 text-base-content/60"
            )
          ]}>
            {idx + 1}
          </span>
          <span class={if(@phase == step, do: "text-base-content", else: "")}>
            {phase_label(step)}
          </span>
          <span :if={idx < 1} aria-hidden="true" class="w-6 h-px bg-base-300"></span>
        </li>
        </ol>
      </div>
    </div>
    """
  end
  # ---- end phase tracker ------------------------------------------------

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
