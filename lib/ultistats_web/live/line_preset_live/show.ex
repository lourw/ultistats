defmodule UltistatsWeb.LinePresetLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.Accounts.User
  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Line preset {@line_preset.name}
        <:subtitle>{length(@line_preset.users)} players selected.</:subtitle>
        <:actions>
          <.button navigate={~p"/line_presets"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            :if={@is_admin?}
            variant="primary"
            navigate={~p"/line_presets/#{@line_preset}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit line preset
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@line_preset.name}</:item>
      </.list>

      <section class="mt-6">
        <h2 class="text-base font-semibold mb-3">Players</h2>
        <ul :if={@line_preset.users != []} class="divide-y divide-base-300">
          <li :for={user <- @line_preset.users} class="flex items-center gap-3 py-2">
            <span class="font-medium">{User.display_name(user)}</span>
          </li>
        </ul>
        <p :if={@line_preset.users == []} class="text-base-content/70">
          No players selected for this preset yet.
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    line_preset = Teams.get_line_preset!(id)
    user = socket.assigns.current_scope.user

    if Teams.user_member_of?(user, line_preset.team_id) do
      {:ok,
       socket
       |> assign(:page_title, "Show Line preset")
       |> assign(:line_preset, line_preset)
       |> assign(:is_admin?, Teams.user_admin_of?(user, line_preset.team_id))}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to view that line preset.")
       |> push_navigate(to: ~p"/line_presets")}
    end
  end
end
