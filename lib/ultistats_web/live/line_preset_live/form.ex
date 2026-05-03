defmodule UltistatsWeb.LinePresetLive.Form do
  use UltistatsWeb, :live_view

  import UltistatsWeb.UIComponents, only: [player_chip: 1]

  alias Ultistats.Teams
  alias Ultistats.Teams.LinePreset
  alias Ultistats.Teams.Player

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Pick the players that make up this line preset.</:subtitle>
      </.header>

      <.form for={@form} id="line_preset-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Preset name" />
        <.input field={@form[:team_id]} type="hidden" />

        <section class="mt-6">
          <h2 class="text-base font-semibold mb-3">
            Roster ({selected_count(@selected_player_ids)} selected of {length(@team_players)})
          </h2>

          <div :if={@team_players == []} class="text-base-content/70">
            This team has no players yet. Add some to the roster first.
          </div>

          <div :if={@team_players != []} class="flex flex-wrap gap-2">
            <.player_chip
              :for={player <- @team_players}
              player={chip_player(player)}
              selected?={MapSet.member?(@selected_player_ids, player.id)}
              phx-click="toggle_player"
              phx-value-id={player.id}
            />
          </div>
        </section>

        <footer class="mt-6 flex gap-2">
          <.button phx-disable-with="Saving..." variant="primary">Save Line preset</.button>
          <.button navigate={return_path(@return_to, @line_preset)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to("team"), do: "team"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    line_preset = Teams.get_line_preset!(id)
    team_players = Teams.list_players_for_team(line_preset.team_id)

    selected_player_ids =
      line_preset.players
      |> Enum.map(& &1.id)
      |> MapSet.new()

    socket
    |> assign(:page_title, "Edit Line preset")
    |> assign(:line_preset, line_preset)
    |> assign(:team_players, team_players)
    |> assign(:selected_player_ids, selected_player_ids)
    |> assign(:form, to_form(Teams.change_line_preset(line_preset)))
  end

  defp apply_action(socket, :new, params) do
    line_preset = %LinePreset{team_id: params["team_id"], players: []}

    team_players =
      case params["team_id"] do
        nil -> []
        team_id -> Teams.list_players_for_team(team_id)
      end

    socket
    |> assign(:page_title, "New Line preset")
    |> assign(:line_preset, line_preset)
    |> assign(:team_players, team_players)
    |> assign(:selected_player_ids, MapSet.new())
    |> assign(:form, to_form(Teams.change_line_preset(line_preset)))
  end

  @impl true
  def handle_event("toggle_player", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_player_ids, id) do
        MapSet.delete(socket.assigns.selected_player_ids, id)
      else
        # Defensive: only allow toggling players in the team roster.
        if Enum.any?(socket.assigns.team_players, &(&1.id == id)) do
          MapSet.put(socket.assigns.selected_player_ids, id)
        else
          socket.assigns.selected_player_ids
        end
      end

    {:noreply, assign(socket, :selected_player_ids, selected)}
  end

  def handle_event("validate", %{"line_preset" => line_preset_params}, socket) do
    changeset = Teams.change_line_preset(socket.assigns.line_preset, line_preset_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"line_preset" => line_preset_params}, socket) do
    save_line_preset(socket, socket.assigns.live_action, line_preset_params)
  end

  defp save_line_preset(socket, :edit, line_preset_params) do
    attrs = with_player_ids(line_preset_params, socket.assigns.selected_player_ids)

    case Teams.update_line_preset(socket.assigns.line_preset, attrs) do
      {:ok, line_preset} ->
        {:noreply,
         socket
         |> put_flash(:info, "Line preset updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, line_preset))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_line_preset(socket, :new, line_preset_params) do
    attrs = with_player_ids(line_preset_params, socket.assigns.selected_player_ids)

    case Teams.create_line_preset(attrs) do
      {:ok, line_preset} ->
        {:noreply,
         socket
         |> put_flash(:info, "Line preset created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, line_preset))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp with_player_ids(params, selected) when is_map(params) do
    Map.put(params, "player_ids", MapSet.to_list(selected))
  end

  defp selected_count(%MapSet{} = set), do: MapSet.size(set)

  # Adapt a Player struct to the shape `<.player_chip>` expects
  # (`:number` + `:name`).
  defp chip_player(player) do
    %{number: player.jersey_number, name: Player.display_name(player)}
  end

  defp return_path("index", _line_preset), do: ~p"/line_presets"
  defp return_path("show", line_preset), do: ~p"/line_presets/#{line_preset}"

  defp return_path("team", %LinePreset{team_id: team_id}) when is_binary(team_id),
    do: ~p"/teams/#{team_id}"

  defp return_path("team", _line_preset), do: ~p"/line_presets"
end
