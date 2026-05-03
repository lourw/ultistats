defmodule UltistatsWeb.TeamLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Teams
        <:actions>
          <.button variant="primary" navigate={~p"/teams/new"}>
            <.icon name="hero-plus" /> New team
          </.button>
        </:actions>
      </.header>

      <p :if={@teams_with_stats == []} class="text-base-content/70">
        No teams yet. <.link navigate={~p"/teams/new"} class="underline">Create your first team</.link>.
      </p>

      <ul :if={@teams_with_stats != []} id="teams-list" class="divide-y divide-base-200">
        <li :for={%{team: team, stats: s} <- @teams_with_stats} id={"team-#{team.id}"} class="py-3">
          <.link
            navigate={~p"/teams/#{team}"}
            class="block hover:bg-base-200 rounded-md px-2 -mx-2 py-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <div class="font-medium text-base">{team.name}</div>
            <div class="mt-1 text-sm text-base-content/70 flex flex-wrap gap-x-3 gap-y-1 tabular-nums">
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
    {:ok,
     socket
     |> assign(:page_title, "Teams")
     |> assign(:teams_with_stats, Teams.list_teams_with_stats())}
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
