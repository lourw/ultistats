defmodule UltistatsWeb.LinePresetLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams
  alias Ultistats.Teams.Player

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Line preset {@line_preset.name}
        <:subtitle>{length(@line_preset.players)} players selected.</:subtitle>
        <:actions>
          <.button navigate={~p"/line_presets"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/line_presets/#{@line_preset}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit line preset
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@line_preset.name}</:item>
      </.list>

      <section class="mt-6">
        <h2 class="text-base font-semibold mb-3">Players</h2>
        <ul :if={@line_preset.players != []} class="divide-y divide-base-300">
          <li :for={player <- @line_preset.players} class="flex items-center gap-3 py-2">
            <span class="badge badge-neutral font-mono">#{player.jersey_number}</span>
            <span class="font-medium">{Player.display_name(player)}</span>
          </li>
        </ul>
        <p :if={@line_preset.players == []} class="text-base-content/70">
          No players selected for this preset yet.
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Line preset")
     |> assign(:line_preset, Teams.get_line_preset!(id))}
  end
end
