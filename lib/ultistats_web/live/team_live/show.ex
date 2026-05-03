defmodule UltistatsWeb.TeamLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams
  alias Ultistats.Teams.Player

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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
          <.button variant="primary" navigate={~p"/teams/#{@team}/edit?return_to=show"}>
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
            {length(@players)}
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
        <ul :if={@players != []} id="team-roster" class="divide-y divide-base-300">
          <li
            :for={player <- @players}
            id={"player-#{player.id}"}
            class="flex items-center justify-between gap-3 py-3"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span
                :if={player.jersey_number}
                class="inline-flex items-center justify-center w-8 h-7 px-1 rounded-full bg-base-200 text-base-content text-sm font-semibold tabular-nums shrink-0"
              >
                {player.jersey_number}
              </span>
              <span class="font-medium truncate">{Player.display_name(player)}</span>
              <span class="text-lg leading-none shrink-0" aria-hidden="true">
                {gender_glyph(player.gender_role)}
              </span>
              <span class="sr-only">{humanize_gender_role(player.gender_role)}</span>
            </div>
            <.link
              navigate={~p"/players/#{player}/edit?return_to=team"}
              aria-label={"Edit #{Player.display_name(player)}"}
              class="shrink-0 min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              <.icon name="hero-pencil-square" class="size-5" />
            </.link>
          </li>
        </ul>

        <p :if={@players == []} class="mt-4 text-base-content/70">
          No players yet. Add the first one to start building the roster.
        </p>
      </section>

      <section :if={@active_tab == :presets} class="mt-4 pb-24" aria-labelledby="tab-presets">
        <ul :if={@line_presets != []} id="team-line-presets" class="divide-y divide-base-300">
          <li
            :for={preset <- @line_presets}
            id={"line-preset-#{preset.id}"}
            class="flex items-center justify-between gap-3 py-3"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span class="inline-flex items-center justify-center min-w-8 h-7 px-2 rounded-full bg-base-200 text-base-content text-sm font-semibold tabular-nums shrink-0">
                {length(preset.players)}
              </span>
              <span class="font-medium truncate">{preset.name}</span>
            </div>
            <.link
              navigate={~p"/line_presets/#{preset}/edit?return_to=team"}
              aria-label={"Edit #{preset.name}"}
              class="shrink-0 min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              <.icon name="hero-pencil-square" class="size-5" />
            </.link>
          </li>
        </ul>

        <p :if={@line_presets == []} class="mt-4 text-base-content/70">
          No line presets yet. Create your first to set lines quickly mid-game.
        </p>
      </section>

      <.link
        :if={@active_tab == :roster}
        navigate={~p"/players/new?team_id=#{@team.id}&return_to=team"}
        aria-label="Add player"
        class="fixed bottom-6 right-6 z-40 size-14 rounded-full bg-primary text-primary-content shadow-lg flex items-center justify-center hover:bg-primary/90 active:scale-[0.97] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary motion-reduce:active:scale-100"
      >
        <.icon name="hero-plus" class="size-6" />
      </.link>

      <.link
        :if={@active_tab == :presets}
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

    {:ok,
     socket
     |> assign(:page_title, team.name)
     |> assign(:team, team)
     |> assign(:active_tab, :roster)
     |> assign(:players, Teams.list_players_for_team(team))
     |> assign(:line_presets, Teams.list_line_presets_for_team(team))}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => "roster"}, socket) do
    {:noreply, assign(socket, :active_tab, :roster)}
  end

  def handle_event("set_tab", %{"tab" => "presets"}, socket) do
    {:noreply, assign(socket, :active_tab, :presets)}
  end

  defp tab_classes(true),
    do:
      "min-h-11 inline-flex items-center pb-3 -mb-px text-sm font-medium text-primary border-b-2 border-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp tab_classes(false),
    do:
      "min-h-11 inline-flex items-center pb-3 -mb-px text-sm font-medium text-base-content/60 hover:text-base-content border-b-2 border-transparent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp gender_glyph(:female_matching), do: "♀"
  defp gender_glyph(:male_matching), do: "♂"
  defp gender_glyph(_), do: ""

  defp humanize_gender_role(:female_matching), do: "Female-matching"
  defp humanize_gender_role(:male_matching), do: "Male-matching"
  defp humanize_gender_role(other), do: to_string(other)
end
