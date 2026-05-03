defmodule UltistatsWeb.GameLive.Start do
  use UltistatsWeb, :live_view

  alias Ultistats.Games
  alias Ultistats.Games.Game
  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Start a game
        <:subtitle>Pick the team, name the opponent, and call the first pull.</:subtitle>
      </.header>

      <div :if={@teams == []} id="no-teams-empty-state" class="mt-6">
        <div class="rounded-md bg-base-200 p-4">
          <p class="font-medium">Create a team first</p>
          <p class="text-sm text-base-content/70 mt-1">
            You need at least one team before you can start a game.
          </p>
          <div class="mt-3">
            <.button variant="primary" navigate={~p"/teams/new"}>
              <.icon name="hero-plus" /> New team
            </.button>
          </div>
        </div>
      </div>

      <.form
        :if={@teams != []}
        for={@form}
        id="game-form"
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          :if={length(@teams) > 1}
          field={@form[:team_id]}
          type="select"
          label="Team"
          prompt="Select team"
          options={team_options(@teams)}
        />
        <.input :if={length(@teams) == 1} field={@form[:team_id]} type="hidden" />

        <.input field={@form[:opponent_name]} type="text" label="Opponent" maxlength="80" />

        <.input
          field={@form[:first_pull]}
          type="select"
          label="First pull"
          options={first_pull_options()}
        />

        <.input field={@form[:format]} type="hidden" />

        <p class="text-sm text-base-content/70 mt-2">
          USAU standard format — first to 15, halftime at 8.
        </p>

        <footer class="mt-6">
          <.button phx-disable-with="Starting..." variant="primary">Start game</.button>
          <.button navigate={cancel_path(@cancel_team_id)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    teams = Teams.list_teams()
    requested_team_id = params["team_id"]

    selected_team_id = pick_team_id(teams, requested_team_id)

    game = %Game{
      team_id: selected_team_id,
      format: :usau_standard,
      first_pull: :ours
    }

    {:ok,
     socket
     |> assign(:page_title, "Start a game")
     |> assign(:teams, teams)
     |> assign(:cancel_team_id, selected_team_id)
     |> assign(:form, to_form(Games.change_game(game)))}
  end

  @impl true
  def handle_event("validate", %{"game" => game_params}, socket) do
    changeset =
      %Game{}
      |> Games.change_game(merge_defaults(game_params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"game" => game_params}, socket) do
    case Games.start_game(merge_defaults(game_params)) do
      {:ok, game} ->
        {:noreply,
         socket
         |> put_flash(:info, "Game started")
         |> push_navigate(to: ~p"/games/#{game.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  # Force MVP-fixed defaults regardless of what the form posts (format hidden,
  # but defensive — the start-game flow doesn't expose configurability).
  defp merge_defaults(params) do
    params
    |> Map.put_new("format", "usau_standard")
    |> Map.put_new("first_pull", "ours")
  end

  defp pick_team_id([], _requested), do: nil

  defp pick_team_id(teams, requested_id) when is_binary(requested_id) do
    if Enum.any?(teams, &(&1.id == requested_id)) do
      requested_id
    else
      pick_team_id(teams, nil)
    end
  end

  defp pick_team_id([single], _), do: single.id
  defp pick_team_id(_teams, _), do: nil

  defp team_options(teams) do
    Enum.map(teams, &{&1.name, &1.id})
  end

  defp first_pull_options do
    [{"We pull", :ours}, {"They pull", :theirs}]
  end

  defp cancel_path(team_id) when is_binary(team_id), do: ~p"/teams/#{team_id}"
  defp cancel_path(_), do: ~p"/teams"
end
