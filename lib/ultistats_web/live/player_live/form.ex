defmodule UltistatsWeb.PlayerLive.Form do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams
  alias Ultistats.Teams.Player

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage player records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="player-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:jersey_number]} type="text" label="Jersey number" />
        <.input
          field={@form[:gender_role]}
          type="select"
          label="Gender role"
          prompt="Select gender role"
          options={gender_role_options()}
        />
        <.input field={@form[:team_id]} type="hidden" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Player</.button>
          <.button navigate={return_path(@return_to, @player)}>Cancel</.button>
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
    player = Teams.get_player!(id)

    socket
    |> assign(:page_title, "Edit Player")
    |> assign(:player, player)
    |> assign(:form, to_form(Teams.change_player(player)))
  end

  defp apply_action(socket, :new, params) do
    player = %Player{team_id: params["team_id"]}

    socket
    |> assign(:page_title, "New Player")
    |> assign(:player, player)
    |> assign(:form, to_form(Teams.change_player(player)))
  end

  @impl true
  def handle_event("validate", %{"player" => player_params}, socket) do
    changeset = Teams.change_player(socket.assigns.player, player_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"player" => player_params}, socket) do
    save_player(socket, socket.assigns.live_action, player_params)
  end

  defp save_player(socket, :edit, player_params) do
    case Teams.update_player(socket.assigns.player, player_params) do
      {:ok, player} ->
        {:noreply,
         socket
         |> put_flash(:info, "Player updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, player))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_player(socket, :new, player_params) do
    case Teams.create_player(player_params) do
      {:ok, player} ->
        {:noreply,
         socket
         |> put_flash(:info, "Player created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, player))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _player), do: ~p"/players"
  defp return_path("show", player), do: ~p"/players/#{player}"

  defp return_path("team", %Player{team_id: team_id}) when is_binary(team_id),
    do: ~p"/teams/#{team_id}"

  defp return_path("team", _player), do: ~p"/players"

  defp gender_role_options do
    Enum.map(Player.gender_roles(), fn role ->
      {humanize_gender_role(role), role}
    end)
  end

  defp humanize_gender_role(:female_matching), do: "Female-matching (FMP)"
  defp humanize_gender_role(:male_matching), do: "Male-matching (MMP)"
end
