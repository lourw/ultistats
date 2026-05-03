defmodule UltistatsWeb.TeamLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Teams
        <:actions>
          <.button variant="primary" navigate={~p"/teams/new"}>
            <.icon name="hero-plus" /> New team
          </.button>
        </:actions>
      </.header>

      <div :if={@teams_with_stats == []} id="no-teams-empty-state" class="mt-4">
        <p class="text-base-content/70">
          You're not on any teams yet. Create one to get started.
        </p>
        <div class="mt-3">
          <.button variant="primary" navigate={~p"/teams/new"}>
            <.icon name="hero-plus" /> Create team
          </.button>
        </div>
      </div>

      <ul
        :if={@teams_with_stats != []}
        id="teams-list"
        class="-mx-4 border-y border-base-200 divide-y divide-base-200"
      >
        <li :for={%{team: team, stats: s} <- @teams_with_stats} id={"team-#{team.id}"}>
          <.link
            navigate={~p"/teams/#{team}"}
            class="min-h-9 flex flex-col justify-center px-4 py-1.5 hover:bg-base-200 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <div class="font-medium text-sm leading-tight">{team.name}</div>
            <div class="text-xs text-base-content/70 flex flex-wrap gap-x-2 gap-y-0.5 tabular-nums leading-tight">
              <span>{s.total_players} players</span>
              <span aria-hidden="true">·</span>
              <span>♂ {s.male_matching}</span>
              <span>♀ {s.female_matching}</span>
              <span aria-hidden="true">·</span>
              <span>{format_record(s)}</span>
              <span :if={s.games_in_progress > 0} class="text-info">
                {s.games_in_progress} in progress
              </span>
            </div>
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Teams")
     |> assign(:teams_with_stats, Teams.list_teams_with_stats_for_user(user))}
  end

  # Record formatting:
  # - "W–L" (en dash) for the common case of finished wins/losses
  # - "W–L–T" when ties exist
  # - "No games yet" when there are zero games at all
  # - "" when only in-progress games exist (the "in progress" badge carries the info)
  defp format_record(%{wins: 0, losses: 0, ties: 0, games_in_progress: 0}), do: "No games yet"
  defp format_record(%{wins: 0, losses: 0, ties: 0}), do: ""
  defp format_record(%{wins: w, losses: l, ties: 0}), do: "#{w}–#{l}"
  defp format_record(%{wins: w, losses: l, ties: t}), do: "#{w}–#{l}–#{t}"
end
