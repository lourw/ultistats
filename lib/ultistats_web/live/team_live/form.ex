defmodule UltistatsWeb.TeamLive.Form do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams
  alias Ultistats.Teams.Team

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="team-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input
          field={@form[:division]}
          type="select"
          label="Division"
          options={division_options()}
        />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save</.button>
          <.button navigate={return_path(@return_to, @team)}>Cancel</.button>
        </footer>
      </.form>

      <section :if={@live_action == :edit} class="mt-12 pt-6 border-t border-base-300">
        <h2 class="text-sm font-semibold text-base-content">Danger zone</h2>
        <p class="mt-1 text-sm text-base-content/70">
          Deleting a team also removes all of its players, line presets, and games.
        </p>
        <button
          type="button"
          id="delete-team"
          phx-click={JS.push("delete_team", value: %{id: @team.id})}
          data-confirm="Delete this team and all of its data? This cannot be undone."
          class="mt-3 min-h-11 inline-flex items-center px-4 rounded-md text-sm font-medium border border-error text-error hover:bg-error/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-error"
        >
          Delete team
        </button>
      </section>
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
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    team = Teams.get_team!(id)
    user = socket.assigns.current_scope.user

    cond do
      not Teams.user_member_of?(user, team) ->
        socket
        |> put_flash(:error, "You don't have permission to do that.")
        |> push_navigate(to: ~p"/teams")

      not Teams.user_admin_of?(user, team) ->
        socket
        |> put_flash(:error, "You don't have permission to do that.")
        |> push_navigate(to: ~p"/teams/#{team}")

      true ->
        socket
        |> assign(:page_title, "Edit #{team.name}")
        |> assign(:team, team)
        |> assign(:form, to_form(Teams.change_team(team)))
    end
  end

  defp apply_action(socket, :new, _params) do
    team = %Team{}

    socket
    |> assign(:page_title, "New team")
    |> assign(:team, team)
    |> assign(:form, to_form(Teams.change_team(team)))
  end

  @impl true
  def handle_event("validate", %{"team" => team_params}, socket) do
    changeset = Teams.change_team(socket.assigns.team, team_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"team" => team_params}, socket) do
    save_team(socket, socket.assigns.live_action, team_params)
  end

  def handle_event("delete_team", %{"id" => id}, socket) do
    team = Teams.get_team!(id)
    user = socket.assigns.current_scope.user

    if Teams.user_admin_of?(user, team) do
      {:ok, _} = Teams.delete_team(team)

      {:noreply,
       socket
       |> put_flash(:info, "Team deleted")
       |> push_navigate(to: ~p"/teams")}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    end
  end

  defp save_team(socket, :edit, team_params) do
    user = socket.assigns.current_scope.user

    if Teams.user_admin_of?(user, socket.assigns.team) do
      case Teams.update_team(socket.assigns.team, team_params) do
        {:ok, team} ->
          {:noreply,
           socket
           |> put_flash(:info, "Team updated successfully")
           |> push_navigate(to: return_path(socket.assigns.return_to, team))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    end
  end

  defp save_team(socket, :new, team_params) do
    user = socket.assigns.current_scope.user

    case Teams.create_team_with_admin(team_params, user) do
      {:ok, %{team: team}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Team created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, team))}

      {:error, :team, %Ecto.Changeset{} = changeset, _changes} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _team), do: ~p"/teams"
  defp return_path("show", team), do: ~p"/teams/#{team}"

  defp division_options do
    [{"Open", :open}, {"Women's", :womens}, {"Mixed", :mixed}]
  end
end
