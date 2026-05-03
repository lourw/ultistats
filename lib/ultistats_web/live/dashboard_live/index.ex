defmodule UltistatsWeb.DashboardLive.Index do
  @moduledoc """
  Authenticated landing page. Shows recent games and a leaderboard for
  the user's currently-selected team, with a team switcher when the
  user belongs to more than one team.

  Selected team is URL-param-backed (`?team_id=`) so refreshes and
  shareable links reproduce the same view. When the param is missing
  or names a team the user isn't on, we fall back to the first team
  alphabetically and `push_patch` to fix the URL.
  """
  use UltistatsWeb, :live_view

  alias Ultistats.Accounts.User
  alias Ultistats.{Games, Teams}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    teams = Teams.list_teams_for_user(user)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:teams, teams)
     |> assign(:selected_team, nil)
     |> assign(:leaderboard, [])
     |> assign(:recent_games, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{teams: teams} = socket.assigns
    user = socket.assigns.current_scope.user

    case resolve_selected_team(params["team_id"], teams, user) do
      {:redirect, team} ->
        {:noreply, push_patch(socket, to: ~p"/dashboard?team_id=#{team.id}")}

      {:ok, nil} ->
        {:noreply,
         socket
         |> assign(:selected_team, nil)
         |> assign(:leaderboard, [])
         |> assign(:recent_games, [])}

      {:ok, %_{} = team} ->
        {:noreply,
         socket
         |> assign(:selected_team, team)
         |> assign(:leaderboard, Games.leaderboard_for_team(team))
         |> assign(:recent_games, team |> Games.list_games_for_team() |> Enum.take(5))}
    end
  end

  @impl true
  def handle_event("switch_team", %{"team_id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard?team_id=#{id}")}
  end

  # Picks the team to render based on the URL param, the user's
  # membership list, and the alphabetical-first fallback.
  defp resolve_selected_team(_param, [], _user), do: {:ok, nil}

  defp resolve_selected_team(nil, [first | _], _user), do: {:redirect, first}

  defp resolve_selected_team(team_id, teams, user) when is_binary(team_id) do
    case Enum.find(teams, &(&1.id == team_id)) do
      %_{} = team ->
        if Teams.user_member_of?(user, team), do: {:ok, team}, else: fallback(teams)

      nil ->
        fallback(teams)
    end
  end

  defp resolve_selected_team(_, teams, _user), do: fallback(teams)

  defp fallback([first | _]), do: {:redirect, first}
  defp fallback([]), do: {:ok, nil}

  ## ---------------------------------------------------------------------
  ## render
  ## ---------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Dashboard
        <:subtitle :if={@selected_team}>
          {@selected_team.name}
        </:subtitle>
      </.header>

      <%= cond do %>
        <% @teams == [] -> %>
          <.no_teams_state />
        <% true -> %>
          <div class="space-y-6">
            <.team_switcher :if={length(@teams) > 1} teams={@teams} selected_team={@selected_team} />

            <.recent_games_panel
              :if={@selected_team}
              games={@recent_games}
              selected_team={@selected_team}
            />

            <.leaderboard_panel
              :if={@selected_team}
              leaderboard={@leaderboard}
              recent_games={@recent_games}
            />
          </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp no_teams_state(assigns) do
    ~H"""
    <div id="dashboard-no-teams" class="mt-4 space-y-3">
      <p class="text-base font-medium">Welcome to Ultistats.</p>
      <p class="text-base-content/70">
        Create your first team to start tracking games.
      </p>
      <div>
        <.button variant="primary" navigate={~p"/teams/new"}>
          <.icon name="hero-plus" /> Create team
        </.button>
      </div>
    </div>
    """
  end

  attr :teams, :list, required: true
  attr :selected_team, :map, required: true

  defp team_switcher(assigns) do
    ~H"""
    <section aria-label="Team switcher" class="flex items-center gap-2">
      <label for="dashboard-team-select" class="text-sm text-base-content/70">Team</label>
      <form phx-change="switch_team">
        <select
          id="dashboard-team-select"
          name="team_id"
          class="select select-sm select-bordered min-h-11"
        >
          <option
            :for={team <- @teams}
            value={team.id}
            selected={team.id == @selected_team.id}
          >
            {team.name}
          </option>
        </select>
      </form>
    </section>
    """
  end

  attr :games, :list, required: true
  attr :selected_team, :map, required: true

  defp recent_games_panel(assigns) do
    ~H"""
    <section aria-label="Recent games" class="space-y-2">
      <div class="flex items-baseline justify-between">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
          Recent games
        </h2>
        <.link
          navigate={~p"/games"}
          class="text-xs text-base-content/70 hover:underline"
        >
          All games
        </.link>
      </div>

      <%= if @games == [] do %>
        <div id="dashboard-no-games" class="rounded-lg border-2 border-dashed border-base-300 p-4">
          <p class="text-base font-medium">No games for {@selected_team.name} yet</p>
          <div class="mt-3">
            <.button variant="primary" navigate={~p"/games/new"}>
              <.icon name="hero-plus" /> Start a game
            </.button>
          </div>
        </div>
      <% else %>
        <ul
          id="dashboard-recent-games"
          class="-mx-4 border-y border-base-200 divide-y divide-base-200"
        >
          <li :for={game <- @games} id={"dashboard-game-#{game.id}"}>
            <.link
              navigate={game_link(game)}
              class="min-h-11 flex items-center gap-2 px-4 py-1.5 hover:bg-base-200 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              <div class="flex-1 min-w-0">
                <div class="font-medium text-sm truncate leading-tight">
                  vs {game.opponent_name}
                </div>
                <div class="text-xs text-base-content/70 tabular-nums leading-tight">
                  {format_started_at(game.started_at)}
                </div>
              </div>
              <span class="tabular-nums text-sm font-semibold shrink-0">
                {score_label(game)}
              </span>
              <span class={[
                "text-[11px] font-semibold px-2 py-0.5 rounded-full shrink-0",
                status_pill_classes(game.status)
              ]}>
                {status_label(game.status)}
              </span>
            </.link>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  attr :leaderboard, :list, required: true
  attr :recent_games, :list, required: true

  defp leaderboard_panel(assigns) do
    ~H"""
    <section aria-label="Leaderboard" class="space-y-2">
      <div class="flex items-baseline justify-between">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
          Leaderboard
        </h2>
        <span class="text-xs text-base-content/60 tabular-nums">
          {length(@leaderboard)} players
        </span>
      </div>

      <%= cond do %>
        <% @leaderboard == [] -> %>
          <div class="rounded-lg border-2 border-dashed border-base-300 p-4">
            <p class="text-base-content/70">No players on this team's roster yet.</p>
          </div>
        <% all_zero?(@leaderboard) and @recent_games != [] -> %>
          <p class="text-sm text-base-content/70">No stats recorded yet.</p>
          <.leaderboard_table leaderboard={@leaderboard} />
        <% @recent_games == [] -> %>
          <.leaderboard_table leaderboard={@leaderboard} />
        <% true -> %>
          <.leaderboard_table leaderboard={@leaderboard} />
      <% end %>
    </section>
    """
  end

  attr :leaderboard, :list, required: true

  defp leaderboard_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-lg border border-base-200">
      <table id="dashboard-leaderboard" class="w-full border-collapse text-left text-sm">
        <thead class="border-b border-base-200 bg-base-200/50 text-base-content/70 font-semibold">
          <tr>
            <th scope="col" class="p-3 w-12 text-right tabular-nums">#</th>
            <th scope="col" class="p-3">Player</th>
            <th scope="col" class="p-3 text-right tabular-nums">
              <abbr title="Goals" class="no-underline">G</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums">
              <abbr title="Assists" class="no-underline">A</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums">
              <abbr title="Catches" class="no-underline">C</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums">
              <abbr title="Drops" class="no-underline">D</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums">
              <abbr title="Throwaways" class="no-underline">TA</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums">
              <abbr title="Blocks" class="no-underline">B</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums whitespace-nowrap">
              Pts played
            </th>
          </tr>
        </thead>
        <tbody class="text-base-content">
          <tr
            :for={row <- @leaderboard}
            class={[
              "border-b border-base-200 last:border-b-0",
              row_zero?(row) && "text-base-content/60"
            ]}
          >
            <td class="p-3 text-right tabular-nums font-semibold">
              {jersey_label(row.membership.jersey_number)}
            </td>
            <td class="p-3">
              <span class="font-medium">{User.display_name(row.user)}</span>
            </td>
            <td class="p-3 text-right tabular-nums">{row.goals}</td>
            <td class="p-3 text-right tabular-nums">{row.assists}</td>
            <td class="p-3 text-right tabular-nums">{row.catches}</td>
            <td class="p-3 text-right tabular-nums">{row.drops}</td>
            <td class="p-3 text-right tabular-nums">{row.throwaways}</td>
            <td class="p-3 text-right tabular-nums">{row.blocks}</td>
            <td class="p-3 text-right tabular-nums">{row.points_played}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  ## ---------------------------------------------------------------------
  ## helpers
  ## ---------------------------------------------------------------------

  defp game_link(%{status: :in_progress, id: id}), do: ~p"/games/#{id}"
  defp game_link(%{id: id}), do: ~p"/games/#{id}/summary"

  defp score_label(game) do
    %{ours: ours, theirs: theirs} = Games.score(game)
    "#{ours}–#{theirs}"
  end

  defp status_label(:in_progress), do: "In progress"
  defp status_label(:finished), do: "Final"
  defp status_label(:abandoned), do: "Abandoned"
  defp status_label(other), do: to_string(other)

  defp status_pill_classes(:in_progress), do: "bg-info/10 text-info"
  defp status_pill_classes(:finished), do: "bg-success/10 text-success"
  defp status_pill_classes(:abandoned), do: "bg-base-200 text-base-content/70"
  defp status_pill_classes(_), do: "bg-base-200 text-base-content"

  defp format_started_at(nil), do: "—"

  defp format_started_at(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d · %H:%M")
  end

  defp jersey_label(nil), do: "—"
  defp jersey_label(""), do: "—"
  defp jersey_label(n) when is_binary(n), do: n

  defp row_zero?(row) do
    row.goals == 0 and row.assists == 0 and row.catches == 0 and row.drops == 0 and
      row.throwaways == 0 and row.blocks == 0 and row.points_played == 0
  end

  defp all_zero?(leaderboard), do: Enum.all?(leaderboard, &row_zero?/1)
end
