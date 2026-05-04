defmodule UltistatsWeb.TeamLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.Accounts.User
  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <header class="flex flex-wrap items-center justify-between gap-x-4 gap-y-3 pb-4">
        <h1 class="flex w-full items-center gap-2 text-lg font-semibold leading-8 text-base-content sm:w-auto sm:flex-1">
          <.link
            navigate={~p"/teams"}
            aria-label="Back to teams"
            class="shrink-0 min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <span>{@team.name}</span>
          <.link
            :if={@is_admin?}
            navigate={~p"/teams/#{@team}/edit?return_to=show"}
            aria-label="Edit team"
            class="shrink-0 min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-pencil-square" class="size-4" />
          </.link>
        </h1>
        <div class="flex flex-wrap items-center gap-2">
          <button
            :if={@is_admin?}
            type="button"
            phx-hook="CopyJoinLink"
            id={"team-#{@team.id}-copy-join-link"}
            data-claim-url={join_url(@team)}
            aria-label={"Copy join link for #{@team.name}"}
            class="min-h-11 inline-flex items-center gap-1.5 px-2.5 rounded-md text-sm font-medium border border-base-300 text-base-content/80 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-link" class="size-4" /> Copy join link
          </button>
          <.button
            :if={@is_admin? and @active_tab == :roster}
            variant="primary"
            navigate={~p"/members/new?team_id=#{@team.id}&return_to=team"}
            class="px-3 gap-1.5"
          >
            <.icon name="hero-plus" /> Add roster
          </.button>
          <.button
            :if={@is_admin? and @active_tab == :presets}
            variant="primary"
            navigate={~p"/line_presets/new?team_id=#{@team.id}&return_to=team"}
            class="px-3 gap-1.5"
          >
            <.icon name="hero-plus" /> Add line
          </.button>
        </div>
      </header>

      <div
        role="tablist"
        aria-label="Team sections"
        class="mt-4 flex gap-6 border-b border-base-200"
      >
        <button
          type="button"
          role="tab"
          id="tab-roster"
          aria-selected={to_string(@active_tab == :roster)}
          phx-click="set_tab"
          phx-value-tab="roster"
          class={tab_classes(@active_tab == :roster)}
        >
          Roster
          <span class={[
            "ml-1.5 tabular-nums text-xs px-1.5 py-0.5 rounded-full",
            if(@active_tab == :roster,
              do: "bg-primary/10 text-primary",
              else: "bg-base-200 text-base-content/70"
            )
          ]}>
            {length(@players) + length(@non_players)}
          </span>
        </button>
        <button
          type="button"
          role="tab"
          id="tab-presets"
          aria-selected={to_string(@active_tab == :presets)}
          phx-click="set_tab"
          phx-value-tab="presets"
          class={tab_classes(@active_tab == :presets)}
        >
          Lines
          <span class={[
            "ml-1.5 tabular-nums text-xs px-1.5 py-0.5 rounded-full",
            if(@active_tab == :presets,
              do: "bg-primary/10 text-primary",
              else: "bg-base-200 text-base-content/70"
            )
          ]}>
            {length(@line_presets)}
          </span>
        </button>
      </div>

      <section :if={@active_tab == :roster} class="mt-4 pb-6" aria-labelledby="tab-roster">
        <div
          :if={@players != [] or @non_players != []}
          class="flex items-center gap-2 flex-wrap mb-6"
        >
          <div class="flex items-center gap-1" role="radiogroup" aria-label="Sort members">
            <span class="text-[11px] uppercase tracking-wide text-base-content/60 mr-1">
              Sort
            </span>
            <button
              type="button"
              phx-click="set_member_sort"
              phx-value-sort="jersey"
              aria-pressed={to_string(@member_sort == :jersey)}
              class={sort_chip_classes(@member_sort == :jersey)}
            >
              Jersey
            </button>
            <button
              type="button"
              phx-click="set_member_sort"
              phx-value-sort="first_name"
              aria-pressed={to_string(@member_sort == :first_name)}
              class={sort_chip_classes(@member_sort == :first_name)}
            >
              First name
            </button>
          </div>

          <label class="ml-auto inline-flex items-center gap-1.5 cursor-pointer text-[11px]">
            <input
              type="checkbox"
              phx-click="toggle_split_by_position"
              checked={@split_by_position?}
              class="checkbox checkbox-xs checkbox-primary"
            />
            <span class="text-base-content/70">Split by position</span>
          </label>
        </div>

        <div :if={@players != []} id="team-roster-players" class="space-y-4">
          <.roster_section
            :for={role <- [:male_matching, :female_matching]}
            :if={Enum.any?(@players, &(&1.user.gender_role == role))}
            role={role}
            members={
              @players
              |> Enum.filter(&(&1.user.gender_role == role))
              |> sort_members(@member_sort)
            }
            is_admin?={@is_admin?}
            split_by_position?={@split_by_position?}
          />
        </div>

        <div :if={@non_players != []} class="mt-8">
          <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide mb-2">
            Non-players
          </h2>
          <ul
            id="team-roster-non-players"
            class="-mx-4 border-y border-base-200 divide-y divide-base-200"
          >
            <li
              :for={membership <- sort_members(@non_players, @member_sort)}
              id={"member-#{membership.id}"}
              class="min-h-9 flex items-center gap-2 px-4 py-0.5"
            >
              <span class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0">
                {Teams.resolved_jersey_number(membership) || "—"}
              </span>
              <span class="font-medium text-sm truncate flex-1 leading-tight">
                {User.display_name(membership.user)}
              </span>
              <span
                :if={membership.role == :admin}
                class="inline-flex items-center rounded-full bg-primary/10 text-primary text-[10px] font-semibold px-1.5 py-0.5 shrink-0"
              >
                Admin
              </span>
              <.link
                :if={@is_admin?}
                navigate={~p"/members/#{membership.id}/edit?return_to=team"}
                aria-label={"Edit #{User.display_name(membership.user)}"}
                class="shrink-0 min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </.link>
            </li>
          </ul>
        </div>

        <p :if={@players == [] and @non_players == []} class="mt-4 text-base-content/70">
          Your roster is empty. Create players or share the invite link with your team.
        </p>
      </section>

      <section :if={@active_tab == :presets} class="mt-4 pb-6" aria-labelledby="tab-presets">
        <ul
          :if={@line_presets != []}
          id="team-line-presets"
          class="-mx-4 border-y border-base-200 divide-y divide-base-200"
        >
          <li :for={preset <- @line_presets} id={"line-preset-#{preset.id}"}>
            <details class="group">
              <summary class="min-h-9 flex items-center gap-2 px-4 py-0.5 cursor-pointer list-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">
                <.icon
                  name="hero-chevron-right"
                  class="size-3.5 shrink-0 text-base-content/40 transition-transform group-open:rotate-90 motion-reduce:transition-none"
                />
                <span class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0">
                  {length(preset.users)}
                </span>
                <span class="font-medium text-sm truncate flex-1 leading-tight">
                  {preset.name}
                </span>
                <span
                  class="text-[11px] tabular-nums text-base-content/60 shrink-0 inline-flex items-center gap-1.5"
                  aria-label={"#{role_count(preset, :male_matching)} male-matching, #{role_count(preset, :female_matching)} female-matching"}
                >
                  <span aria-hidden="true">♂</span> {role_count(preset, :male_matching)}
                  <span aria-hidden="true">♀</span> {role_count(preset, :female_matching)}
                </span>
                <.link
                  :if={@is_admin?}
                  navigate={~p"/line_presets/#{preset}/edit?return_to=team"}
                  aria-label={"Edit #{preset.name}"}
                  onclick="event.stopPropagation()"
                  class="shrink-0 min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                >
                  <.icon name="hero-pencil-square" class="size-4" />
                </.link>
              </summary>

              <div
                :if={preset.users != []}
                class="px-4 pb-3 pl-12 space-y-3"
                aria-label={"Players on #{preset.name}"}
              >
                <section
                  :for={role <- [:male_matching, :female_matching]}
                  :if={Enum.any?(preset.users, &(&1.gender_role == role))}
                  class="space-y-1"
                >
                  <h3 class="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
                    <span class="text-sm leading-none" aria-hidden="true">
                      {gender_glyph(role)}
                    </span>
                    <span>{humanize_gender_role(role)}</span>
                    <span class="tabular-nums text-base-content/50">
                      {role_count(preset, role)}
                    </span>
                  </h3>
                  <ul class="space-y-0.5">
                    <li
                      :for={
                        user <-
                          preset.users
                          |> Enum.filter(&(&1.gender_role == role))
                          |> Enum.sort_by(&user_jersey_sort_key/1)
                      }
                      class="min-h-9 flex items-center gap-2"
                    >
                      <span class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0">
                        {user.jersey_number || "—"}
                      </span>
                      <span class="font-medium text-sm truncate leading-tight">
                        {User.display_name(user)}
                      </span>
                    </li>
                  </ul>
                </section>
              </div>

              <p
                :if={preset.users == []}
                class="px-4 pb-2 pl-12 text-xs italic text-base-content/60"
              >
                No players on this line yet.
              </p>
            </details>
          </li>
        </ul>

        <p :if={@line_presets == []} class="mt-4 text-base-content/70">
          No line presets yet. Create your first to set lines quickly mid-game.
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    team = Teams.get_team!(id)
    user = socket.assigns.current_scope.user

    if Teams.user_member_of?(user, team) do
      members = Teams.list_team_members_for_team(team)
      {players, non_players} = Enum.split_with(members, & &1.is_player)

      {:ok,
       socket
       |> assign(:page_title, team.name)
       |> assign(:team, team)
       |> assign(:is_admin?, Teams.user_admin_of?(user, team))
       |> assign(:active_tab, :roster)
       |> assign(:member_sort, :jersey)
       |> assign(:split_by_position?, false)
       |> assign(:players, players)
       |> assign(:non_players, non_players)
       |> assign(:line_presets, Teams.list_line_presets_for_team(team))}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to view that team.")
       |> push_navigate(to: ~p"/teams")}
    end
  end

  @impl true
  def handle_event("set_tab", %{"tab" => "roster"}, socket) do
    {:noreply, assign(socket, :active_tab, :roster)}
  end

  def handle_event("set_tab", %{"tab" => "presets"}, socket) do
    {:noreply, assign(socket, :active_tab, :presets)}
  end

  def handle_event("set_member_sort", %{"sort" => sort}, socket)
      when sort in ["jersey", "first_name"] do
    {:noreply, assign(socket, :member_sort, String.to_existing_atom(sort))}
  end

  def handle_event("toggle_split_by_position", _params, socket) do
    {:noreply, assign(socket, :split_by_position?, not socket.assigns.split_by_position?)}
  end

  attr :role, :atom, required: true, values: [:male_matching, :female_matching]
  attr :members, :list, required: true
  attr :is_admin?, :boolean, required: true
  attr :split_by_position?, :boolean, required: true

  defp roster_section(assigns) do
    groups =
      if assigns.split_by_position? do
        position_groups(assigns.members)
      else
        [{nil, assigns.members}]
      end

    assigns = assign(assigns, :groups, groups)

    ~H"""
    <section class="space-y-1">
      <h3 class="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
        <span class="text-sm leading-none" aria-hidden="true">{gender_glyph(@role)}</span>
        <span>{humanize_gender_role(@role)}</span>
        <span class="tabular-nums text-base-content/50">
          {length(@members)}
        </span>
      </h3>

      <div :for={{position, members} <- @groups} class="space-y-1">
        <h4
          :if={@split_by_position?}
          class="-mx-4 flex items-center gap-1.5 px-4 py-1 text-[10px] font-semibold uppercase tracking-wide bg-base-200 text-base-content/70"
        >
          <span class={[
            "inline-flex items-center justify-center size-4 rounded-full text-[10px] font-semibold",
            position_pill_classes(position)
          ]}>
            {position_letter(position)}
          </span>
          <span>{humanize_position(position) || "Unspecified"}</span>
        </h4>

        <ul class="-mx-4 border-y border-base-200 divide-y divide-base-200">
          <li
            :for={membership <- members}
            id={"member-#{membership.id}"}
            class="min-h-9 flex items-center gap-2 px-4 py-0.5"
          >
            <span class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0">
              {Teams.resolved_jersey_number(membership) || "—"}
            </span>
            <span class="flex items-center gap-1.5 flex-1 min-w-0">
              <span class="font-medium text-sm truncate leading-tight">
                {User.display_name(membership.user)}
              </span>
              <span
                :if={pos = Teams.resolved_position(membership)}
                class={[
                  "inline-flex items-center justify-center size-5 rounded-full shrink-0",
                  "text-[10px] font-semibold tabular-nums",
                  position_pill_classes(pos)
                ]}
                aria-label={humanize_position(pos)}
                title={humanize_position(pos)}
              >
                {position_letter(pos)}
              </span>
            </span>
            <span
              :if={membership.role == :admin}
              class="inline-flex items-center rounded-full bg-primary/10 text-primary text-[10px] font-semibold px-1.5 py-0.5 shrink-0"
            >
              Admin
            </span>
            <.link
              :if={@is_admin?}
              navigate={~p"/members/#{membership.id}/edit?return_to=team"}
              aria-label={"Edit #{User.display_name(membership.user)}"}
              class="shrink-0 min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.link>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  defp position_groups(members) do
    grouped =
      Enum.group_by(members, fn m ->
        Teams.resolved_position(m) || :unspecified
      end)

    [:handler, :cutter, :hybrid, :unspecified]
    |> Enum.map(fn key ->
      {if(key == :unspecified, do: nil, else: key), Map.get(grouped, key, [])}
    end)
    |> Enum.reject(fn {_, members} -> members == [] end)
  end

  defp position_letter(:handler), do: "H"
  defp position_letter(:cutter), do: "C"
  defp position_letter(:hybrid), do: "X"
  defp position_letter(_), do: "?"

  defp position_pill_classes(:handler), do: "bg-success/15 text-success"
  defp position_pill_classes(:cutter), do: "bg-warning/15 text-warning"
  defp position_pill_classes(:hybrid), do: "bg-info/15 text-info"
  defp position_pill_classes(_), do: "bg-base-200 text-base-content/70"

  defp humanize_position(:handler), do: "Handler"
  defp humanize_position(:cutter), do: "Cutter"
  defp humanize_position(:hybrid), do: "Hybrid"

  defp humanize_position(other) when is_atom(other),
    do: other |> Atom.to_string() |> String.capitalize()

  defp humanize_position(_), do: nil

  defp join_url(team) do
    ~p"/join/#{Teams.generate_team_join_token(team)}"
  end

  defp sort_chip_classes(true),
    do:
      "min-h-9 inline-flex items-center px-2 rounded-md text-xs font-semibold bg-primary text-primary-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp sort_chip_classes(false),
    do:
      "min-h-9 inline-flex items-center px-2 rounded-md text-xs font-semibold border border-base-300 text-base-content/80 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp sort_members(members, :first_name),
    do: Enum.sort_by(members, &String.downcase(&1.user.first_name || ""))

  defp sort_members(members, :jersey) do
    Enum.sort_by(members, &jersey_sort_key/1)
  end

  # Numeric jersey numbers sort numerically; non-numeric (or nil) fall to
  # the bottom in lexicographic order. Uses the resolved jersey number
  # so a per-team override beats the user's default.
  defp jersey_sort_key(membership) do
    case Teams.resolved_jersey_number(membership) do
      nil ->
        {1, ""}

      j ->
        case Integer.parse(j) do
          {n, ""} -> {0, n}
          _ -> {1, j}
        end
    end
  end

  defp user_jersey_sort_key(%User{jersey_number: nil}), do: {1, ""}

  defp user_jersey_sort_key(%User{jersey_number: j}) do
    case Integer.parse(j) do
      {n, ""} -> {0, n}
      _ -> {1, j}
    end
  end

  defp tab_classes(true),
    do:
      "min-h-11 inline-flex items-center pb-3 -mb-px text-sm font-medium text-primary border-b-2 border-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp tab_classes(false),
    do:
      "min-h-11 inline-flex items-center pb-3 -mb-px text-sm font-medium text-base-content/60 hover:text-base-content border-b-2 border-transparent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp role_count(preset, role) do
    Enum.count(preset.users, &(&1.gender_role == role))
  end

  defp gender_glyph(:female_matching), do: "♀"
  defp gender_glyph(:male_matching), do: "♂"
  defp gender_glyph(_), do: ""

  defp humanize_gender_role(:female_matching), do: "Female-matching"
  defp humanize_gender_role(:male_matching), do: "Male-matching"
  defp humanize_gender_role(other), do: to_string(other)
end
