defmodule UltistatsWeb.GameLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Repo}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Games
        <:subtitle>Most-recent first.</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/games/new"}>
            <.icon name="hero-plus" /> New game
          </.button>
        </:actions>
      </.header>

      <p :if={@games == []} class="text-base-content/70">
        No games yet. <.link navigate={~p"/games/new"} class="underline">Start one</.link>.
      </p>

      <ul :if={@games != []} id="games-list" class="divide-y divide-base-200">
        <li :for={game <- @games} id={"game-#{game.id}"} class="py-3">
          <.link
            navigate={~p"/games/#{game.id}"}
            class="flex items-center justify-between gap-3 hover:bg-base-200 rounded-md px-2 -mx-2 py-1"
          >
            <div class="min-w-0">
              <div class="font-medium truncate">
                {team_name(game)} vs {game.opponent_name}
              </div>
              <div class="text-sm text-base-content/70 tabular-nums">
                {format_started_at(game.started_at)} · {status_label(game.status)}
              </div>
            </div>
            <span class={[
              "text-xs font-semibold px-2 py-1 rounded-full shrink-0",
              status_pill_classes(game.status)
            ]}>
              {status_label(game.status)}
            </span>
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    games =
      Games.list_games()
      |> Repo.preload(:team)
      |> Enum.sort_by(& &1.started_at, {:desc, DateTime})

    {:ok, assign(socket, :games, games)}
  end

  defp team_name(%{team: %{name: name}}), do: name
  defp team_name(_), do: "—"

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
end
