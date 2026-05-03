defmodule UltistatsWeb.GameLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.Games

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Game vs {@game.opponent_name}
        <:subtitle>
          {format_label(@game.format)} · started {format_started_at(@game.started_at)}
        </:subtitle>
      </.header>

      <div id="game-status-banner" class="bg-base-200 p-4 rounded-md mt-4">
        <p class="font-medium">Game in progress</p>
      </div>

      <p class="text-sm text-base-content/70 mt-4">
        Live tracking UI lands in the next ticket. For now this is the show page after game start.
      </p>

      <div class="mt-6">
        <.button navigate={~p"/teams/#{@game.team_id}"}>
          <.icon name="hero-arrow-left" /> Back to team
        </.button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game = Games.get_game!(id)

    {:ok,
     socket
     |> assign(:page_title, "Game vs #{game.opponent_name}")
     |> assign(:game, game)}
  end

  defp format_label(:usau_standard), do: "USAU standard"
  defp format_label(other), do: to_string(other)

  defp format_started_at(nil), do: "—"

  defp format_started_at(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end
end
