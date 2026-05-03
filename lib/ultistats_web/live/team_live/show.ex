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
        Team {@team.name}
        <:subtitle>This is a team record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/teams"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/teams/#{@team}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit team
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@team.name}</:item>
      </.list>

      <section class="mt-8">
        <.header>
          Roster ({roster_count_label(@players)})
          <:actions>
            <.button
              variant="primary"
              navigate={~p"/players/new?team_id=#{@team.id}&return_to=team"}
            >
              <.icon name="hero-plus" /> Add player
            </.button>
          </:actions>
        </.header>

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

      <section class="mt-8">
        <.header>
          Line presets ({preset_count_label(@line_presets)})
          <:actions>
            <.button
              variant="primary"
              navigate={~p"/line_presets/new?team_id=#{@team.id}&return_to=team"}
            >
              <.icon name="hero-plus" /> Add preset
            </.button>
          </:actions>
        </.header>

        <ul :if={@line_presets != []} id="team-line-presets" class="mt-4 flex flex-col gap-3">
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
     |> assign(:page_title, "Show Team")
     |> assign(:team, team)
     |> assign(:players, Teams.list_players_for_team(team))
     |> assign(:line_presets, Teams.list_line_presets_for_team(team))}
  end

  @impl true
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

  defp roster_count_label([_]), do: "1 player"
  defp roster_count_label(players), do: "#{length(players)} players"

  defp preset_count_label([_]), do: "1 preset"
  defp preset_count_label(presets), do: "#{length(presets)} presets"

  defp gender_glyph(:female_matching), do: "♀"
  defp gender_glyph(:male_matching), do: "♂"
  defp gender_glyph(_), do: ""

  defp humanize_gender_role(:female_matching), do: "Female-matching"
  defp humanize_gender_role(:male_matching), do: "Male-matching"
  defp humanize_gender_role(other), do: to_string(other)
end
