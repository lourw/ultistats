defmodule UltistatsWeb.TeamLive.Show do
  use UltistatsWeb, :live_view

  import UltistatsWeb.UIComponents, only: [line_preset_card: 1]

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
        class="mt-2 inline-flex rounded-md border border-base-300 p-1 bg-base-100"
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
          Roster · <span class="tabular-nums">{length(@players)}</span>
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
          Line presets · <span class="tabular-nums">{length(@line_presets)}</span>
        </button>
      </div>

      <section :if={@active_tab == :roster} class="mt-4" aria-labelledby="tab-roster">
        <div class="flex items-center justify-end mb-3">
          <.button
            variant="primary"
            navigate={~p"/players/new?team_id=#{@team.id}&return_to=team"}
          >
            <.icon name="hero-plus" /> Add player
          </.button>
        </div>

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
            <div class="flex items-center gap-3 shrink-0">
              <.link navigate={~p"/players/#{player}/edit?return_to=team"} class="link link-hover">
                Edit
              </.link>
              <.link
                phx-click={JS.push("delete_player", value: %{id: player.id})}
                data-confirm="Remove this player from the roster?"
                class="link link-hover text-error"
              >
                Delete
              </.link>
            </div>
          </li>
        </ul>

        <p :if={@players == []} class="mt-4 text-base-content/70">
          No players yet. Add the first one to start building the roster.
        </p>
      </section>

      <section :if={@active_tab == :presets} class="mt-4" aria-labelledby="tab-presets">
        <div class="flex items-center justify-end mb-3">
          <.button
            variant="primary"
            navigate={~p"/line_presets/new?team_id=#{@team.id}&return_to=team"}
          >
            <.icon name="hero-plus" /> Add preset
          </.button>
        </div>

        <ul :if={@line_presets != []} id="team-line-presets" class="flex flex-col gap-3">
          <li
            :for={preset <- @line_presets}
            id={"line-preset-#{preset.id}"}
            class="flex items-center gap-3"
          >
            <div class="flex-1 min-w-0">
              <.line_preset_card
                preset={preset}
                selected?={false}
                gender_warning?={false}
                phx-click={JS.navigate(~p"/line_presets/#{preset}/edit?return_to=team")}
              />
            </div>
            <button
              type="button"
              phx-click={JS.push("delete_line_preset", value: %{id: preset.id})}
              data-confirm={"Delete the \"#{preset.name}\" preset?"}
              aria-label={"Delete preset #{preset.name}"}
              class="min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-error active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary shrink-0"
            >
              <.icon name="hero-trash" class="size-5" />
            </button>
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

  def handle_event("delete_player", %{"id" => id}, socket) do
    player = Teams.get_player!(id)
    {:ok, _} = Teams.delete_player(player)

    {:noreply,
     socket
     |> put_flash(:info, "Player removed from roster")
     |> assign(:players, Teams.list_players_for_team(socket.assigns.team))}
  end

  def handle_event("delete_line_preset", %{"id" => id}, socket) do
    preset = Teams.get_line_preset!(id)
    {:ok, _} = Teams.delete_line_preset(preset)

    {:noreply,
     socket
     |> put_flash(:info, "Line preset deleted")
     |> assign(:line_presets, Teams.list_line_presets_for_team(socket.assigns.team))}
  end

  defp tab_classes(true),
    do:
      "min-h-11 inline-flex items-center px-4 py-1.5 rounded text-sm font-medium bg-primary text-primary-content"

  defp tab_classes(false),
    do:
      "min-h-11 inline-flex items-center px-4 py-1.5 rounded text-sm font-medium text-base-content/70 hover:text-base-content"

  defp gender_glyph(:female_matching), do: "♀"
  defp gender_glyph(:male_matching), do: "♂"
  defp gender_glyph(_), do: ""

  defp humanize_gender_role(:female_matching), do: "Female-matching"
  defp humanize_gender_role(:male_matching), do: "Male-matching"
  defp humanize_gender_role(other), do: to_string(other)
end
