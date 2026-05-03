defmodule UltistatsWeb.MemberLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.Accounts.User
  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Members
        <:subtitle>
          Members are managed within a team — open a team to add or edit members.
        </:subtitle>
      </.header>

      <p :if={@memberships == []} class="text-base-content/70">
        No members yet. <.link navigate={~p"/teams"} class="underline">Open a team</.link>
        to add some.
      </p>

      <.table :if={@memberships != []} id="members" rows={@memberships}>
        <:col :let={m} label="Jersey">{Teams.resolved_jersey_number(m) || "—"}</:col>
        <:col :let={m} label="Name">{User.display_name(m.user)}</:col>
        <:col :let={m} label="Gender">{humanize_gender_role(m.user.gender_role)}</:col>
        <:col :let={m} label="Position">{humanize_position(Teams.resolved_position(m))}</:col>
        <:col :let={m} label="Role">{humanize_role(m.role)}</:col>
        <:col :let={m} label="Player?">{if m.is_player, do: "Yes", else: "No"}</:col>
        <:col :let={m} label="Team">{m.team.name}</:col>
        <:action :let={m}>
          <.link navigate={~p"/members/#{m.id}/edit"} aria-label={"Edit #{User.display_name(m.user)}"}>
            <.icon name="hero-pencil-square" class="size-5" />
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    user_teams = Teams.list_teams_for_user(user)
    team_ids = MapSet.new(user_teams, & &1.id)

    memberships =
      Teams.list_team_memberships()
      |> Enum.filter(&MapSet.member?(team_ids, &1.team_id))

    {:ok,
     socket
     |> assign(:page_title, "Listing Members")
     |> assign(:memberships, memberships)}
  end

  defp humanize_gender_role(:female_matching), do: "Female-matching"
  defp humanize_gender_role(:male_matching), do: "Male-matching"
  defp humanize_gender_role(other), do: to_string(other)

  defp humanize_position(:handler), do: "Handler"
  defp humanize_position(:cutter), do: "Cutter"
  defp humanize_position(:hybrid), do: "Hybrid"
  defp humanize_position(other), do: to_string(other)

  defp humanize_role(:admin), do: "Admin"
  defp humanize_role(:member), do: "Member"
  defp humanize_role(other), do: to_string(other)
end
