defmodule UltistatsWeb.TeamLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Team {@team.name}
        <:subtitle>This is a team record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/teams"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/teams/#{@team}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit team
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@team.name}</:item>
      </.list>

      <section class="mt-8">
        <.header>
          Roster ({roster_count_label(@players)})
          <:actions>
            <.button
              variant="primary"
              navigate={~p"/players/new?team_id=#{@team.id}&return_to=team"}
            >
              <.icon name="hero-plus" /> Add player
            </.button>
          </:actions>
        </.header>

        <ul :if={@players != []} id="team-roster" class="divide-y divide-base-300">
          <li
            :for={player <- @players}
            id={"player-#{player.id}"}
            class="flex items-center justify-between gap-3 py-3"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span class="badge badge-neutral font-mono shrink-0">#{player.jersey_number}</span>
              <span class="font-medium truncate">{player.name}</span>
              <span class={["badge badge-sm", gender_badge_class(player.gender_role)]}>
                {humanize_gender_role(player.gender_role)}
              </span>
            </div>
            <div class="flex items-center gap-3 shrink-0">
              <.link navigate={~p"/players/#{player}/edit?return_to=team"} class="link link-hover">
                Edit
              </.link>
              <.link
                phx-click={JS.push("delete_player", value: %{id: player.id})}
                data-confirm="Remove this player from the roster?"
                class="link link-hover text-error"
              >
                Delete
              </.link>
            </div>
          </li>
        </ul>

        <p :if={@players == []} class="mt-4 text-base-content/70">
          No players yet. Add the first one to start building the roster.
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    team = Teams.get_team!(id)

    {:ok,
     socket
     |> assign(:page_title, "Show Team")
     |> assign(:team, team)
     |> assign(:players, Teams.list_players_for_team(team))}
  end

  @impl true
  def handle_event("delete_player", %{"id" => id}, socket) do
    player = Teams.get_player!(id)
    {:ok, _} = Teams.delete_player(player)

    {:noreply,
     socket
     |> put_flash(:info, "Player removed from roster")
     |> assign(:players, Teams.list_players_for_team(socket.assigns.team))}
  end

  defp roster_count_label([_]), do: "1 player"
  defp roster_count_label(players), do: "#{length(players)} players"

  defp humanize_gender_role(:female_matching), do: "FMP"
  defp humanize_gender_role(:male_matching), do: "MMP"
  defp humanize_gender_role(other), do: to_string(other)

  defp gender_badge_class(:female_matching), do: "badge-secondary"
  defp gender_badge_class(:male_matching), do: "badge-primary"
  defp gender_badge_class(_), do: "badge-ghost"
end
