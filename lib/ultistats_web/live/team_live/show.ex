defmodule UltistatsWeb.TeamLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.Accounts
  alias Ultistats.Accounts.User
  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        <span class="inline-flex items-center gap-3">
          <.link
            navigate={~p"/teams"}
            aria-label="Back to teams"
            class="min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          {@team.name}
        </span>
        <:actions>
          <.button
            :if={@is_admin?}
            variant="primary"
            navigate={~p"/teams/#{@team}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit team
          </.button>
        </:actions>
      </.header>

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

      <section :if={@active_tab == :roster} class="mt-4 pb-24" aria-labelledby="tab-roster">
        <div
          :if={@players != [] or @non_players != []}
          class="flex items-center justify-end gap-1 mb-2"
        >
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
              <button
                :if={@is_admin? and is_nil(membership.user.claimed_at)}
                type="button"
                phx-hook="CopyClaimLink"
                id={"claim-link-non-player-#{membership.id}"}
                data-claim-url={claim_url(membership.user)}
                aria-label={"Copy claim link for #{User.display_name(membership.user)}"}
                class="shrink-0 min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              >
                <.icon name="hero-link" class="size-4" />
              </button>
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
          No members yet. Add the first one to start building the roster.
        </p>
      </section>

      <section :if={@active_tab == :presets} class="mt-4 pb-24" aria-labelledby="tab-presets">
        <ul
          :if={@line_presets != []}
          id="team-line-presets"
          class="-mx-4 border-y border-base-200 divide-y divide-base-200"
        >
          <li
            :for={preset <- @line_presets}
            id={"line-preset-#{preset.id}"}
            class="min-h-9 flex items-center gap-2 px-4 py-0.5"
          >
            <span class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0">
              {length(preset.users)}
            </span>
            <span class="font-medium text-sm truncate flex-1 leading-tight">{preset.name}</span>
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
              class="shrink-0 min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.link>
          </li>
        </ul>

        <p :if={@line_presets == []} class="mt-4 text-base-content/70">
          No line presets yet. Create your first to set lines quickly mid-game.
        </p>
      </section>

      <.link
        :if={@is_admin? and @active_tab == :roster}
        navigate={~p"/members/new?team_id=#{@team.id}&return_to=team"}
        aria-label="Add member"
        class="fixed bottom-6 right-6 z-40 size-14 rounded-full bg-primary text-primary-content shadow-lg flex items-center justify-center hover:bg-primary/90 active:scale-[0.97] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary motion-reduce:active:scale-100"
      >
        <.icon name="hero-plus" class="size-6" />
      </.link>

      <.link
        :if={@is_admin? and @active_tab == :presets}
        navigate={~p"/line_presets/new?team_id=#{@team.id}&return_to=team"}
        aria-label="Add line"
        class="fixed bottom-6 right-6 z-40 size-14 rounded-full bg-primary text-primary-content shadow-lg flex items-center justify-center hover:bg-primary/90 active:scale-[0.97] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary motion-reduce:active:scale-100"
      >
        <.icon name="hero-plus" class="size-6" />
      </.link>
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

  attr :role, :atom, required: true, values: [:male_matching, :female_matching]
  attr :members, :list, required: true
  attr :is_admin?, :boolean, required: true

  defp roster_section(assigns) do
    ~H"""
    <section class="space-y-1">
      <h3 class="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
        <span class="text-sm leading-none" aria-hidden="true">{gender_glyph(@role)}</span>
        <span>{humanize_gender_role(@role)}</span>
        <span class="tabular-nums text-base-content/50">
          {length(@members)}
        </span>
      </h3>

      <ul class="-mx-4 border-y border-base-200 divide-y divide-base-200">
        <li
          :for={membership <- @members}
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
          <button
            :if={@is_admin? and is_nil(membership.user.claimed_at)}
            type="button"
            phx-hook="CopyClaimLink"
            id={"claim-link-#{membership.id}"}
            data-claim-url={claim_url(membership.user)}
            aria-label={"Copy claim link for #{User.display_name(membership.user)}"}
            class="shrink-0 min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-link" class="size-4" />
          </button>
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
    </section>
    """
  end

  defp claim_url(user) do
    ~p"/claim/#{Accounts.generate_stub_claim_token(user)}"
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
