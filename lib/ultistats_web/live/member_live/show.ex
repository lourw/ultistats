defmodule UltistatsWeb.MemberLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.Accounts.User
  alias Ultistats.Repo
  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {User.display_name(@membership.user)}
        <:subtitle>Team membership for {@membership.team.name}.</:subtitle>
        <:actions>
          <.button navigate={~p"/members"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            :if={@is_admin?}
            variant="primary"
            navigate={~p"/members/#{@membership.id}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit
          </.button>
          <button
            :if={@is_admin?}
            type="button"
            id="delete-member"
            phx-click={JS.push("delete_member", value: %{id: @membership.id})}
            data-confirm="Remove this member from the team?"
            class="min-h-11 inline-flex items-center px-4 rounded-md text-sm font-medium border border-error text-error hover:bg-error/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-error"
          >
            Delete
          </button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{User.display_name(@membership.user)}</:item>
        <:item title="Team">{@membership.team.name}</:item>
        <:item title="Jersey number">{Teams.resolved_jersey_number(@membership) || "—"}</:item>
        <:item title="Gender">{humanize_gender_role(@membership.user.gender_role)}</:item>
        <:item title="Position">{humanize_position(Teams.resolved_position(@membership))}</:item>
        <:item title="Role">{humanize_role(@membership.role)}</:item>
        <:item title="Player on roster">{if @membership.is_player, do: "Yes", else: "No"}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    membership = Teams.get_team_membership!(id) |> Repo.preload(:team)
    user = socket.assigns.current_scope.user

    if Teams.user_member_of?(user, membership.team_id) do
      {:ok,
       socket
       |> assign(:page_title, User.display_name(membership.user))
       |> assign(:membership, membership)
       |> assign(:is_admin?, Teams.user_admin_of?(user, membership.team_id))}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to view that member.")
       |> push_navigate(to: ~p"/members")}
    end
  end

  @impl true
  def handle_event("delete_member", %{"id" => id}, socket) do
    membership = Teams.get_team_membership!(id)
    user = socket.assigns.current_scope.user

    if Teams.user_admin_of?(user, membership.team_id) do
      {:ok, _} = Teams.remove_team_member(membership)

      {:noreply,
       socket
       |> put_flash(:info, "Member removed")
       |> push_navigate(to: ~p"/members")}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    end
  end

  defp humanize_gender_role(:female_matching), do: "Female-matching (FMP)"
  defp humanize_gender_role(:male_matching), do: "Male-matching (MMP)"
  defp humanize_gender_role(other), do: to_string(other)

  defp humanize_position(:handler), do: "Handler"
  defp humanize_position(:cutter), do: "Cutter"
  defp humanize_position(:hybrid), do: "Hybrid"
  defp humanize_position(other), do: to_string(other)

  defp humanize_role(:admin), do: "Admin"
  defp humanize_role(:member), do: "Member"
  defp humanize_role(other), do: to_string(other)
end
