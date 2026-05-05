defmodule UltistatsWeb.GameLive.Summary do
  @moduledoc """
  Post-game (and mid-game) summary view — final score plus per-player
  tallies for *this game only* (`docs/MVP_SPEC.md` step 6).

  No cross-game aggregation in MVP. The summary recomputes off the
  same soft-deleted-events read path as the timeline, so editing the
  timeline immediately changes what shows up here on the next mount.
  """
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Teams}
  alias UltistatsWeb.Components.StatsTable

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game = Games.get_game!(id)
    user = socket.assigns.current_scope.user

    if not Teams.user_member_of?(user, game.team_id) do
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to view that game.")
       |> push_navigate(to: ~p"/games")}
    else
      summary = Games.summary_for_game(game)

      {:ok,
       socket
       |> assign(:page_title, "Summary · vs #{game.opponent_name}")
       |> assign(:game, game)
       |> assign(:summary, summary)
       |> assign(:sort_by, :goals)
       |> assign(:sort_dir, :desc)
       |> assign_sorted_players()}
    end
  end

  @impl true
  def handle_event("sort", %{"key" => key}, socket) do
    key_atom = String.to_existing_atom(key)

    if key_atom in StatsTable.sortable_keys() do
      {sort_by, sort_dir} =
        StatsTable.next_sort(key_atom, socket.assigns.sort_by, socket.assigns.sort_dir)

      {:noreply,
       socket
       |> assign(sort_by: sort_by, sort_dir: sort_dir)
       |> assign_sorted_players()}
    else
      {:noreply, socket}
    end
  end

  defp assign_sorted_players(socket) do
    %{summary: summary, sort_by: by, sort_dir: dir} = socket.assigns
    assign(socket, :sorted_players, StatsTable.sort_players(summary.players, by, dir))
  end

  ## ---------------------------------------------------------------------
  ## render
  ## ---------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex flex-col gap-6 pb-safe">
        <.summary_header game={@game} score={@summary.score} />

        <section aria-label="Per-player tallies" class="space-y-2">
          <div class="flex items-baseline justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Per-player tallies
            </h2>
            <div class="flex items-center gap-2">
              <span class="text-xs text-base-content/60 tabular-nums">
                {length(@summary.players)} players
              </span>
              <StatsTable.csv_link
                :if={@summary.players != []}
                path={csv_path(@game, @sort_by, @sort_dir)}
                label="Export"
              />
            </div>
          </div>

          <%= if @summary.players == [] do %>
            <.empty_state game={@game} />
          <% else %>
            <StatsTable.stats_table
              id="game-summary-tallies"
              players={@sorted_players}
              sort_by={@sort_by}
              sort_dir={@sort_dir}
            />
          <% end %>
        </section>

        <.summary_footer game={@game} />
      </div>
    </Layouts.app>
    """
  end

  ## ---------------------------------------------------------------------
  ## sub-renderers
  ## ---------------------------------------------------------------------

  attr :game, :map, required: true
  attr :score, :map, required: true

  defp summary_header(assigns) do
    ~H"""
    <div class="sticky top-0 z-20 -mx-4 px-4 pt-safe bg-base-100/95 backdrop-blur border-b border-base-200">
      <div class="py-3 space-y-3">
        <div class="flex items-center justify-between gap-2">
          <.link
            navigate={back_path(@game)}
            class="inline-flex items-center gap-1 min-h-11 text-sm font-medium text-base-content/80 active:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary rounded-md"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            <span>{back_label(@game)}</span>
          </.link>
          <div class="inline-flex items-center gap-1">
            <.link
              navigate={~p"/games/#{@game.id}/timeline"}
              class="inline-flex items-center gap-1 min-h-11 px-2 text-sm font-medium text-base-content/80 active:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary rounded-md"
            >
              <.icon name="hero-list-bullet" class="size-4" />
              <span>Timeline</span>
            </.link>
            <.link
              :if={@game.ruleset_id}
              navigate={~p"/rulesets/#{@game.ruleset_id}"}
              class="inline-flex items-center gap-1 min-h-11 px-2 text-sm font-medium text-base-content/80 active:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary rounded-md"
            >
              <.icon name="hero-document-text" class="size-4" />
              <span>Ruleset</span>
            </.link>
          </div>
        </div>

        <div class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1 min-w-0">
            <h1 class="text-lg font-semibold truncate">
              Summary <span class="text-base-content/70 font-normal">· vs {@game.opponent_name}</span>
            </h1>
            <p class="text-xs text-base-content/70">
              {format_subtitle(@game)}
            </p>
          </div>
          <.status_pill status={@game.status} />
        </div>

        <.score_readout our_score={@score.ours} their_score={@score.theirs} />
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_pill(assigns) do
    assigns = assign(assigns, :meta, status_pill_meta(assigns.status))

    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 shrink-0 rounded-full px-2 py-1",
        "text-xs font-semibold uppercase tracking-wide",
        @meta.classes
      ]}
      role="status"
      aria-label={"Game status: #{@meta.label}"}
    >
      <.icon name={@meta.icon} class="size-3.5" />
      {@meta.label}
    </span>
    """
  end

  # The live tracker (`/games/:id`) auto-redirects finished games back to
  # this summary, so a "Back to game" link on a finished game would loop.
  # Send it to the games list instead.
  defp back_path(%{status: :finished} = _game), do: ~p"/games"
  defp back_path(game), do: ~p"/games/#{game.id}"

  defp back_label(%{status: :finished}), do: "Back to games"
  defp back_label(_), do: "Back to game"

  defp status_pill_meta(:finished),
    do: %{
      label: "Final",
      icon: "hero-check-circle",
      classes: "bg-success/15 text-success"
    }

  defp status_pill_meta(:in_progress),
    do: %{
      label: "In progress",
      icon: "hero-clock",
      classes: "bg-info/15 text-info"
    }

  defp status_pill_meta(:abandoned),
    do: %{
      label: "Abandoned",
      icon: "hero-x-circle",
      classes: "bg-base-200 text-base-content/70"
    }

  defp status_pill_meta(_),
    do: %{
      label: "Unknown",
      icon: "hero-question-mark-circle",
      classes: "bg-base-200 text-base-content/70"
    }

  attr :game, :map, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="rounded-lg border-2 border-dashed border-base-300 p-6 text-center">
      <.icon name="hero-users" class="size-8 text-base-content/40 mx-auto mb-2" />
      <p class="text-base font-medium">No players on this team yet</p>
      <p class="text-sm text-base-content/70 mt-1">
        Add players to the team's roster to see per-player tallies here.
      </p>
      <div class="mt-4">
        <.link
          navigate={~p"/teams/#{@game.team_id}"}
          class="inline-flex items-center gap-2 min-h-11 px-4 rounded-lg bg-primary text-primary-content font-semibold active:bg-primary/80 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-arrow-right" class="size-4" /> Manage team
        </.link>
      </div>
    </div>
    """
  end

  attr :game, :map, required: true

  defp summary_footer(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3">
      <.link
        navigate={back_path(@game)}
        class="inline-flex items-center gap-2 min-h-11 px-4 rounded-lg border-2 border-base-300 text-base font-semibold bg-base-100 text-base-content active:bg-base-200 transition-colors motion-reduce:transition-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {back_label(@game)}
      </.link>
      <.link
        :if={@game.status == :in_progress}
        navigate={~p"/games/#{@game.id}"}
        class="inline-flex items-center gap-2 min-h-11 px-4 rounded-lg bg-primary text-primary-content text-base font-semibold active:bg-primary/80 transition-colors motion-reduce:transition-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <.icon name="hero-play" class="size-4" /> Continue tracking
      </.link>
    </div>
    """
  end

  ## ---------------------------------------------------------------------
  ## helpers
  ## ---------------------------------------------------------------------

  defp csv_path(game, sort_by, sort_dir) do
    ~p"/games/#{game.id}/summary.csv?sort=#{sort_by}&dir=#{sort_dir}"
  end

  defp format_subtitle(%{format: format} = game) do
    base = humanize_format(format)

    case {game.status, game.ended_at} do
      {:in_progress, _} -> "#{base} · In progress"
      {_, %DateTime{} = dt} -> "#{base} · Ended #{Calendar.strftime(dt, "%b %-d, %H:%M")}"
      _ -> base
    end
  end

  defp humanize_format(:usau_standard), do: "USAU standard"
  defp humanize_format(other), do: to_string(other)
end
