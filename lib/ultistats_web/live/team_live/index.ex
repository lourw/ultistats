defmodule UltistatsWeb.TeamLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Teams
        <:actions>
          <.button variant="primary" navigate={~p"/teams/new"}>
            <.icon name="hero-plus" /> New Team
          </.button>
        </:actions>
      </.header>

      <.table
        id="teams"
        rows={@streams.teams}
        row_click={fn {_id, team} -> JS.navigate(~p"/teams/#{team}") end}
      >
        <:col :let={{_id, team}} label="Name">{team.name}</:col>
        <:action :let={{_id, team}}>
          <div class="sr-only">
            <.link navigate={~p"/teams/#{team}"}>Show</.link>
          </div>
          <.link navigate={~p"/teams/#{team}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, team}}>
          <.link
            phx-click={JS.push("delete", value: %{id: team.id}) |> hide("##{id}")}
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
     |> assign(:page_title, "Listing Teams")
     |> stream(:teams, list_teams())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    team = Teams.get_team!(id)
    {:ok, _} = Teams.delete_team(team)

    {:noreply, stream_delete(socket, :teams, team)}
  end

  defp list_teams() do
    Teams.list_teams()
  end
end
