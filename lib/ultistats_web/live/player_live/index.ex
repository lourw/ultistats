defmodule UltistatsWeb.PlayerLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Players
        <:actions>
          <.button variant="primary" navigate={~p"/players/new"}>
            <.icon name="hero-plus" /> New Player
          </.button>
        </:actions>
      </.header>

      <.table
        id="players"
        rows={@streams.players}
        row_click={fn {_id, player} -> JS.navigate(~p"/players/#{player}") end}
      >
        <:col :let={{_id, player}} label="Jersey">{player.jersey_number}</:col>
        <:col :let={{_id, player}} label="Name">{player.name}</:col>
        <:col :let={{_id, player}} label="Gender role">
          {humanize_gender_role(player.gender_role)}
        </:col>
        <:col :let={{_id, player}} label="Team">{team_name(player.team)}</:col>
        <:action :let={{_id, player}}>
          <div class="sr-only">
            <.link navigate={~p"/players/#{player}"}>Show</.link>
          </div>
          <.link navigate={~p"/players/#{player}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, player}}>
          <.link
            phx-click={JS.push("delete", value: %{id: player.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Players")
     |> stream(:players, list_players())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    player = Teams.get_player!(id)
    {:ok, _} = Teams.delete_player(player)

    {:noreply, stream_delete(socket, :players, player)}
  end

  defp list_players() do
    Teams.list_players()
  end

  defp humanize_gender_role(:female_matching), do: "Female-matching"
  defp humanize_gender_role(:male_matching), do: "Male-matching"
  defp humanize_gender_role(other), do: to_string(other)

  defp team_name(%Ultistats.Teams.Team{name: name}), do: name
  defp team_name(_), do: "—"
end
