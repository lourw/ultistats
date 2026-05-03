defmodule UltistatsWeb.GameLive.Timeline do
  @moduledoc """
  Timeline view for a game — the mistake-recovery surface
  (`docs/MVP_SPEC.md` step 7). Renders every live (non-deleted) event
  for the game, grouped by point in `sequence` order, with per-row
  edit and soft-delete affordances.

  Edit affordances:

    * Edit       opens a modal with type + player selectors that calls
                 `Games.update_event/2`.
    * Delete     swaps the row's action area for an inline
                 Confirm / Cancel pair (UI_DESIGN.md §State + feedback —
                 destructive actions require confirmation; using an
                 inline confirm avoids stacking yet another overlay).

  Score recomputes on every edit/delete by re-reading
  `Games.score/1`; out-of-scope per the task: automatically clearing a
  point's `scoring_team` when its terminal goal is deleted/edited.
  """
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Teams}
  alias Ultistats.Accounts.User

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game = Games.get_game_with_points!(id)
    user = socket.assigns.current_scope.user

    if not Teams.user_member_of?(user, game.team_id) do
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to view that game.")
       |> push_navigate(to: ~p"/games")}
    else
      team_players = Teams.list_players_for_team(game.team_id)
      members_by_user_id = Map.new(team_players, &{&1.user_id, &1})

      {:ok,
       socket
       |> assign(:page_title, "Timeline · vs #{game.opponent_name}")
       |> assign(:game, game)
       |> assign(:team_players, team_players)
       |> assign(:players_by_id, members_by_user_id)
       |> assign(:editing_event_id, nil)
       |> assign(:edit_type, nil)
       |> assign(:edit_user_id, nil)
       |> assign(:confirming_delete_id, nil)
       |> assign(:sort_order, :newest_first)
       |> reload_timeline()}
    end
  end

  ## ---------------------------------------------------------------------
  ## render
  ## ---------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex flex-col gap-6 pb-safe">
        <.timeline_header game={@game} score={@score} sort_order={@sort_order} />

        <%= if @timeline == [] do %>
          <.empty_state game={@game} />
        <% else %>
          <ol class="space-y-6" aria-label="Game timeline">
            <li :for={section <- @timeline}>
              <.point_section
                section={section}
                players_by_id={@players_by_id}
                editing_event_id={@editing_event_id}
                confirming_delete_id={@confirming_delete_id}
              />
            </li>
          </ol>
        <% end %>
      </div>

      <.edit_event_modal
        :if={@editing_event_id}
        editing_event={editing_event(@timeline, @editing_event_id)}
        edit_type={@edit_type}
        edit_user_id={@edit_user_id}
        team_players={@team_players}
      />
    </Layouts.app>
    """
  end

  ## ---------------------------------------------------------------------
  ## sub-renderers
  ## ---------------------------------------------------------------------

  attr :game, :map, required: true
  attr :score, :map, required: true
  attr :sort_order, :atom, required: true

  defp timeline_header(assigns) do
    ~H"""
    <div class="sticky top-0 z-20 -mx-4 px-4 pt-safe bg-base-100/95 backdrop-blur border-b border-base-200">
      <div class="py-3 space-y-2">
        <.link
          navigate={~p"/games/#{@game.id}"}
          class="inline-flex items-center gap-1 min-h-11 text-sm font-medium text-base-content/80 active:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary rounded-md"
        >
          <.icon name="hero-arrow-left" class="size-4" />
          <span>Back to game</span>
        </.link>

        <div class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1 min-w-0">
            <h1 class="text-lg font-semibold truncate">
              Timeline
              <span class="text-base-content/70 font-normal">· vs {@game.opponent_name}</span>
            </h1>
            <.score_readout our_score={@score.ours} their_score={@score.theirs} />
          </div>

          <button
            type="button"
            phx-click="set_sort"
            phx-value-order={
              if @sort_order == :newest_first, do: "oldest_first", else: "newest_first"
            }
            aria-label={
              if @sort_order == :newest_first,
                do: "Sort oldest first",
                else: "Sort newest first"
            }
            class="min-h-9 inline-flex items-center gap-1 rounded-md border border-base-300 px-2 text-xs font-semibold text-base-content/80 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary shrink-0"
          >
            <.icon
              name={
                if @sort_order == :newest_first,
                  do: "hero-bars-arrow-down",
                  else: "hero-bars-arrow-up"
              }
              class="size-4"
            />
            <span>{sort_label(@sort_order)}</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp sort_label(:newest_first), do: "Newest"
  defp sort_label(:oldest_first), do: "Oldest"

  attr :game, :map, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="rounded-lg border-2 border-dashed border-base-300 p-6 text-center">
      <.icon name="hero-clock" class="size-8 text-base-content/40 mx-auto mb-2" />
      <p class="text-base font-medium">No points played yet</p>
      <p class="text-sm text-base-content/70 mt-1">
        Once you start tracking points, every event will appear here for review.
      </p>
      <div class="mt-4">
        <.link
          navigate={~p"/games/#{@game.id}"}
          class="inline-flex items-center gap-2 min-h-11 px-4 rounded-lg bg-primary text-primary-content font-semibold active:bg-primary/80 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-arrow-right" class="size-4" /> Go to game
        </.link>
      </div>
    </div>
    """
  end

  attr :section, :map, required: true
  attr :players_by_id, :map, required: true
  attr :editing_event_id, :any, required: true
  attr :confirming_delete_id, :any, required: true

  defp point_section(assigns) do
    ~H"""
    <section aria-label={"Point #{@section.point.sequence}"}>
      <header class="flex items-baseline justify-between gap-3 mb-2">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70 tabular-nums">
          Point {@section.point.sequence}
        </h2>
        <span class={[
          "inline-flex items-center gap-1 text-xs font-semibold px-2 py-0.5 rounded-full",
          scoring_badge_classes(@section.point.scoring_team)
        ]}>
          <.icon name={scoring_badge_icon(@section.point.scoring_team)} class="size-3.5" />
          {scoring_badge_label(@section.point.scoring_team)}
        </span>
      </header>

      <%= if @section.events == [] do %>
        <p class="text-sm text-base-content/60 italic px-3 py-2">
          No events recorded for this point.
        </p>
      <% else %>
        <ul class="-mx-4 border-y border-base-200 divide-y divide-base-200">
          <li :for={event <- @section.events}>
            <.timeline_event
              event={event_view(event, @players_by_id, @section.point)}
              editable?={true}
            >
              <:actions>
                <%= if @confirming_delete_id == event.id do %>
                  <.delete_confirm event_id={event.id} />
                <% else %>
                  <.row_actions event_id={event.id} editing?={@editing_event_id == event.id} />
                <% end %>
              </:actions>
            </.timeline_event>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  attr :event_id, :any, required: true
  attr :editing?, :boolean, required: true

  defp row_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5">
      <button
        type="button"
        phx-click="open_edit"
        phx-value-id={@event_id}
        aria-label="Edit event"
        aria-pressed={to_string(@editing?)}
        class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <.icon name="hero-pencil-square" class="size-4" />
      </button>
      <button
        type="button"
        phx-click="ask_delete"
        phx-value-id={@event_id}
        aria-label="Delete event"
        class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-error active:bg-error/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <.icon name="hero-trash" class="size-4" />
      </button>
    </div>
    """
  end

  attr :event_id, :any, required: true

  defp delete_confirm(assigns) do
    ~H"""
    <div class="flex items-center gap-1" role="group" aria-label="Confirm delete">
      <span class="text-xs font-medium text-base-content/80 hidden sm:inline">
        Delete?
      </span>
      <button
        type="button"
        phx-click="confirm_delete"
        phx-value-id={@event_id}
        aria-label="Confirm delete event"
        class="min-h-9 px-2 inline-flex items-center justify-center rounded-md text-xs font-semibold bg-error text-error-content active:bg-error/80 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        Delete
      </button>
      <button
        type="button"
        phx-click="cancel_delete"
        aria-label="Cancel delete"
        class="min-h-9 px-2 inline-flex items-center justify-center rounded-md text-xs font-semibold border border-base-300 text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        Cancel
      </button>
    </div>
    """
  end

  # Hand-rolled modal — matches the pattern used in
  # `UltistatsWeb.GameLive.Show.player_picker_modal/1`. TODO: promote
  # both to a shared `<.modal>` primitive in `ui_components.ex`
  # (per UI_DESIGN.md §Components — sixth-primitive rule applies).
  attr :editing_event, :map, required: true
  attr :edit_type, :atom, required: true
  attr :edit_user_id, :any, required: true
  attr :team_players, :list, required: true

  defp edit_event_modal(assigns) do
    ~H"""
    <div
      id="edit-event-modal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby="edit-event-title"
    >
      <div
        class="absolute inset-0 bg-black/50"
        phx-click="cancel_edit"
        aria-hidden="true"
      />
      <div class="relative z-10 w-full sm:max-w-md bg-base-100 rounded-t-2xl sm:rounded-2xl shadow-xl pb-safe">
        <div class="p-4 border-b border-base-200 flex items-center justify-between">
          <h2 id="edit-event-title" class="text-lg font-semibold">Edit event</h2>
          <button
            type="button"
            phx-click="cancel_edit"
            aria-label="Cancel"
            class="min-h-11 min-w-11 inline-flex items-center justify-center rounded-md active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <form phx-submit="save_edit" class="p-4 space-y-5 max-h-[70vh] overflow-y-auto">
          <div class="space-y-1 mb-2">
            <p class="block text-sm font-medium text-base-content">Type</p>
            <div
              class="grid grid-cols-2 sm:grid-cols-4 gap-2"
              role="radiogroup"
              aria-label="Event type"
            >
              <.event_type_button
                :for={type <- [:goal, :catch, :drop, :throwaway, :stall, :block, :pick, :foul]}
                type={type}
                selected?={@edit_type == type}
                phx-click="set_edit_type"
                phx-value-type={Atom.to_string(type)}
              />
            </div>
          </div>

          <div class="space-y-1 mb-2">
            <p class="block text-sm font-medium text-base-content">Player</p>
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                phx-click="set_edit_player"
                phx-value-id=""
                aria-pressed={to_string(is_nil(@edit_user_id))}
                class={[
                  "min-h-11 px-3 py-2 rounded-full text-base font-medium border-2",
                  "active:scale-[0.98] motion-reduce:active:scale-100 transition-colors motion-reduce:transition-none",
                  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                  if(is_nil(@edit_user_id),
                    do: "bg-primary text-primary-content border-primary",
                    else: "bg-base-100 text-base-content border-base-300 active:bg-base-200"
                  )
                ]}
              >
                No player
              </button>
              <.player_chip
                :for={player <- @team_players}
                player={
                  %{
                    number: Teams.resolved_jersey_number(player),
                    name: User.display_name(player.user)
                  }
                }
                selected?={@edit_user_id == player.user_id}
                phx-click="set_edit_player"
                phx-value-id={player.user_id}
              />
            </div>
          </div>

          <div class="flex items-center gap-2 pt-2">
            <button
              type="submit"
              class="flex-1 min-h-14 rounded-xl px-4 py-3 text-base font-semibold bg-primary text-primary-content active:bg-primary/80 transition-colors motion-reduce:transition-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              Save
            </button>
            <button
              type="button"
              phx-click="cancel_edit"
              class="min-h-14 px-4 rounded-xl border-2 border-base-300 text-base font-semibold bg-base-100 text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  ## ---------------------------------------------------------------------
  ## events
  ## ---------------------------------------------------------------------

  @impl true
  def handle_event("set_sort", %{"order" => order}, socket)
      when order in ["newest_first", "oldest_first"] do
    {:noreply,
     socket
     |> assign(:sort_order, String.to_existing_atom(order))
     |> reload_timeline()}
  end

  def handle_event("open_edit", %{"id" => id}, socket) do
    case find_event(socket.assigns.timeline, id) do
      nil ->
        {:noreply, socket}

      event ->
        {:noreply,
         socket
         |> assign(:editing_event_id, event.id)
         |> assign(:edit_type, event.type)
         |> assign(:edit_user_id, event.passer_user_id)
         |> assign(:confirming_delete_id, nil)}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_event_id, nil)
     |> assign(:edit_type, nil)
     |> assign(:edit_user_id, nil)}
  end

  def handle_event("set_edit_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :edit_type, String.to_existing_atom(type))}
  end

  def handle_event("set_edit_player", %{"id" => ""}, socket) do
    {:noreply, assign(socket, :edit_user_id, nil)}
  end

  def handle_event("set_edit_player", %{"id" => user_id}, socket) do
    {:noreply, assign(socket, :edit_user_id, user_id)}
  end

  def handle_event("save_edit", _params, socket) do
    %{
      editing_event_id: id,
      edit_type: type,
      edit_user_id: user_id
    } = socket.assigns

    with event when not is_nil(event) <- find_event(socket.assigns.timeline, id),
         {:ok, _updated} <-
           Games.update_event(event, %{type: type, passer_user_id: user_id}) do
      {:noreply,
       socket
       |> assign(:editing_event_id, nil)
       |> assign(:edit_type, nil)
       |> assign(:edit_user_id, nil)
       |> reload_timeline()}
    else
      nil ->
        {:noreply,
         socket
         |> assign(:editing_event_id, nil)
         |> put_flash(:error, "Event no longer exists.")}

      {:error, :user_not_on_team} ->
        {:noreply, put_flash(socket, :error, "That player isn't on this team.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Could not update event.")}
    end
  end

  def handle_event("ask_delete", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:confirming_delete_id, id)
     |> assign(:editing_event_id, nil)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirming_delete_id, nil)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    case find_event(socket.assigns.timeline, id) do
      nil ->
        {:noreply, assign(socket, :confirming_delete_id, nil)}

      event ->
        case Games.soft_delete_event(event) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:confirming_delete_id, nil)
             |> reload_timeline()}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:confirming_delete_id, nil)
             |> put_flash(:error, "Could not delete event.")}
        end
    end
  end

  ## ---------------------------------------------------------------------
  ## helpers
  ## ---------------------------------------------------------------------

  # Reload the per-point event lists and the score. Called on mount and
  # after every mutation.
  defp reload_timeline(socket) do
    game = Games.get_game_with_points!(socket.assigns.game.id)

    timeline =
      Enum.map(game.points, fn point ->
        %{point: point, events: Games.events_for_point(point)}
      end)
      |> sort_timeline(socket.assigns.sort_order)

    socket
    |> assign(:game, game)
    |> assign(:timeline, timeline)
    |> assign(:score, Games.score(game))
  end

  # `:newest_first` flips both the point order and each point's event
  # order so the most recent activity surfaces at the top. `:oldest_first`
  # is the natural sequence order from the DB.
  defp sort_timeline(timeline, :oldest_first), do: timeline

  defp sort_timeline(timeline, :newest_first) do
    timeline
    |> Enum.reverse()
    |> Enum.map(fn section -> %{section | events: Enum.reverse(section.events)} end)
  end

  # Build the map shape consumed by `<.timeline_event>`.
  @doc false
  def event_view(event, players_by_id, point) do
    %{
      type: event.type,
      player_label: event_player_label(event, players_by_id),
      timestamp: format_time(event.occurred_at),
      point_label: "P#{point.sequence}"
    }
  end

  # Display label for an event row. Catches/goals/drops show passer →
  # receiver; passer-only events show passer; calls/opponent events show
  # an em-dash.
  defp event_player_label(
         %{type: type, passer_user_id: passer_id, receiver_user_id: receiver_id},
         lookup
       )
       when type in [:catch, :goal, :drop] do
    "#{player_label(passer_id, lookup)} → #{player_label(receiver_id, lookup)}"
  end

  defp event_player_label(%{passer_user_id: nil, receiver_user_id: nil}, _lookup), do: "—"

  defp event_player_label(%{passer_user_id: passer_id}, lookup) when not is_nil(passer_id) do
    player_label(passer_id, lookup)
  end

  defp event_player_label(_, _), do: "—"

  defp player_label(nil, _players_by_id), do: "—"

  defp player_label(user_id, players_by_id) do
    case Map.get(players_by_id, user_id) do
      nil -> "—"
      member -> "##{Teams.resolved_jersey_number(member)} #{User.display_name(member.user)}"
    end
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  defp format_time(_), do: ""

  defp find_event(timeline, id) do
    Enum.find_value(timeline, fn %{events: events} ->
      Enum.find(events, &(&1.id == id))
    end)
  end

  defp editing_event(timeline, id), do: find_event(timeline, id)

  defp scoring_badge_classes(:ours), do: "bg-success/20 text-success"
  defp scoring_badge_classes(:theirs), do: "bg-error/20 text-error"
  defp scoring_badge_classes(_), do: "bg-base-200 text-base-content/80"

  defp scoring_badge_icon(:ours), do: "hero-trophy"
  defp scoring_badge_icon(:theirs), do: "hero-flag"
  defp scoring_badge_icon(_), do: "hero-clock"

  defp scoring_badge_label(:ours), do: "We scored"
  defp scoring_badge_label(:theirs), do: "They scored"
  defp scoring_badge_label(_), do: "In progress"
end
