defmodule UltistatsWeb.Layouts do
  @moduledoc """
  App-level layouts and shared layout pieces. The full live-game header
  (sticky score readout + connectivity banner) lands with the live game
  screen — see `docs/UI_DESIGN.md` §Layout.
  """
  use UltistatsWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header
      id="app-nav"
      phx-hook="ScrollAwareNav"
      class="sticky top-0 z-30 bg-base-100 border-b border-base-300 pt-safe transition-transform duration-200 motion-reduce:transition-none will-change-transform"
    >
      <nav class="mx-auto max-w-2xl px-4 h-14 flex items-center justify-between gap-4">
        <.link navigate={~p"/"} class="font-semibold text-base-content">
          Ultistats
        </.link>
        <ul class="flex items-center gap-4 text-sm">
          <li>
            <.link navigate={~p"/teams"} class="hover:underline">Teams</.link>
          </li>
          <li>
            <.link navigate={~p"/games"} class="hover:underline">Games</.link>
          </li>
        </ul>
      </nav>
    </header>

    <main class="min-h-[100dvh] bg-base-100 text-base-content pb-safe">
      <div class="mx-auto max-w-2xl px-4 py-6 space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Reconnecting…"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Trying to reach the server
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Trying to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
