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
          <.button :if={@teams_with_stats != []} variant="primary" navigate={~p"/teams/new"}>
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

      <div
        :if={length(@teams_with_stats) > 1}
        class="flex flex-col gap-1 mt-4 mb-3"
      >
        <span
          id="teams-division-filter-label"
          class="text-[11px] uppercase tracking-wide text-base-content/60"
        >
          Division
        </span>
        <div
          role="radiogroup"
          aria-labelledby="teams-division-filter-label"
          class="flex flex-wrap items-center gap-1.5"
        >
          <button
            :for={{label, value} <- division_filter_options()}
            type="button"
            phx-click="set_division_filter"
            phx-value-division={value}
            role="radio"
            aria-checked={to_string(value == @division_filter)}
            class={[
              "min-h-7 px-2.5 py-0.5 rounded-full border text-[11px] font-medium",
              "active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              if(value == @division_filter,
                do: "border-primary bg-primary/10 text-primary",
                else: "border-base-300 bg-base-100 text-base-content/70"
              )
            ]}
          >
            {label}
          </button>
        </div>
      </div>

      <ul
        :if={@teams_with_stats != []}
        id="teams-list"
        class="rounded-md border border-base-200 divide-y divide-base-200 overflow-hidden"
      >
        <li
          :for={%{team: team, stats: s} <- visible_teams(@teams_with_stats, @division_filter)}
          id={"team-#{team.id}"}
        >
          <.link
            navigate={~p"/teams/#{team}"}
            class="min-h-9 flex flex-col justify-center gap-1 px-4 py-2 hover:bg-base-200 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <div class="font-medium text-sm leading-tight">{team.name}</div>
            <div class="text-xs text-base-content/70 flex flex-wrap gap-x-2 gap-y-0.5 tabular-nums leading-tight">
              <span>{s.total_players} players</span>
              <span aria-hidden="true">·</span>
              <span><span class="font-semibold">M</span> {s.male_matching}</span>
              <span><span class="font-semibold">F</span> {s.female_matching}</span>
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
     |> assign(:division_filter, "all")
     |> assign(:teams_with_stats, Teams.list_teams_with_stats_for_user(user))}
  end

  @impl true
  def handle_event("set_division_filter", %{"division" => division}, socket)
      when division in ["all", "open", "mixed", "womens"] do
    {:noreply, assign(socket, :division_filter, division)}
  end

  defp total_games(%{wins: w, losses: l, ties: t, games_in_progress: ip}),
    do: w + l + t + ip

  defp games_label(0), do: "No games yet"
  defp games_label(1), do: "1 game"
  defp games_label(n), do: "#{n} games"

  defp division_filter_options do
    [{"All divisions", "all"}, {"Open", "open"}, {"Women's", "womens"}, {"Mixed", "mixed"}]
  end

  defp visible_teams(teams_with_stats, "all"), do: teams_with_stats

  defp visible_teams(teams_with_stats, division)
       when division in ["open", "womens", "mixed"] do
    atom = String.to_existing_atom(division)
    Enum.filter(teams_with_stats, fn %{team: team} -> team.division == atom end)
  end
end
