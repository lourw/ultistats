defmodule UltistatsWeb.PlayerLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams
  alias Ultistats.Teams.Player

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Player {@player.id}
        <:subtitle>This is a player record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/players"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/players/#{@player}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit player
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{Player.display_name(@player)}</:item>
        <:item title="Jersey number">{@player.jersey_number}</:item>
        <:item title="Gender role">{humanize_gender_role(@player.gender_role)}</:item>
        <:item title="Position">{humanize_position(@player.position)}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Player")
     |> assign(:player, Teams.get_player!(id))}
  end

  defp humanize_gender_role(:female_matching), do: "Female-matching (FMP)"
  defp humanize_gender_role(:male_matching), do: "Male-matching (MMP)"
  defp humanize_gender_role(other), do: to_string(other)

  defp humanize_position(:handler), do: "Handler"
  defp humanize_position(:cutter), do: "Cutter"
  defp humanize_position(:hybrid), do: "Hybrid"
  defp humanize_position(other), do: to_string(other)
end
