defmodule UltistatsWeb.LinePresetLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.Teams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Line presets
      </.header>

      <.table
        id="line_presets"
        rows={@streams.line_presets}
        row_click={fn {_id, line_preset} -> JS.navigate(~p"/line_presets/#{line_preset}") end}
      >
        <:col :let={{_id, line_preset}} label="Name">{line_preset.name}</:col>
        <:col :let={{_id, line_preset}} label="Players">{length(line_preset.players)}</:col>
        <:action :let={{_id, line_preset}}>
          <div class="sr-only">
            <.link navigate={~p"/line_presets/#{line_preset}"}>Show</.link>
          </div>
          <.link navigate={~p"/line_presets/#{line_preset}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, line_preset}}>
          <.link
            phx-click={JS.push("delete", value: %{id: line_preset.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Line presets")
     |> stream(:line_presets, list_line_presets())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    line_preset = Teams.get_line_preset!(id)
    {:ok, _} = Teams.delete_line_preset(line_preset)

    {:noreply, stream_delete(socket, :line_presets, line_preset)}
  end

  defp list_line_presets() do
    Teams.list_line_presets()
  end
end
