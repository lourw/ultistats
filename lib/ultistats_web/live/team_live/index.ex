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
              <span>{games_label(total_games(s))}</span>
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

  defp total_games(%{wins: w, losses: l, ties: t, games_in_progress: ip}),
    do: w + l + t + ip

  defp games_label(0), do: "No games yet"
  defp games_label(1), do: "1 game"
  defp games_label(n), do: "#{n} games"
end
