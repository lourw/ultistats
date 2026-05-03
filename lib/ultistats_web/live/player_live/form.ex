defmodule UltistatsWeb.PlayerLive.Form do
  use UltistatsWeb, :live_view

  import UltistatsWeb.UIComponents, only: [gender_radio: 1]

  alias Ultistats.Teams
  alias Ultistats.Teams.Player

  @impl true
  def render(%{live_action: :new} = assigns), do: render_bulk_new(assigns)
  def render(%{live_action: :edit} = assigns), do: render_edit(assigns)

  defp render_bulk_new(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Add players to {@team.name}
        <:subtitle>
          First name, last name and gender are required. Jersey numbers are optional.
        </:subtitle>
      </.header>

      <form id="bulk-player-form" phx-change="validate" phx-submit="save_all">
        <div class="overflow-x-auto">
          <table class="w-full border-collapse text-sm">
            <thead class="border-b border-base-300 text-base-content/70">
              <tr>
                <th class="p-2 text-left font-medium">First</th>
                <th class="p-2 text-left font-medium">Last</th>
                <th class="p-2 text-left font-medium w-44">Gender</th>
                <th class="p-2 text-left font-medium w-20">Jersey</th>
                <th class="p-2 w-12"><span class="sr-only">Remove</span></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @rows}
                id={"player-row-#{row.key}"}
                class="border-b border-base-200 align-top"
                data-row-key={row.key}
              >
                <td class="p-2">
                  <label for={"row-#{row.key}-first_name"} class="sr-only">
                    First name
                  </label>
                  <input
                    type="text"
                    id={"row-#{row.key}-first_name"}
                    name={"row[#{row.key}][first_name]"}
                    value={row.first_name}
                    autocomplete="off"
                    placeholder="First"
                    class={compact_input_classes(Map.get(row.errors, :first_name))}
                  />
                  <p :if={msg = Map.get(row.errors, :first_name)} class="mt-1 text-xs text-error">
                    {msg}
                  </p>
                </td>
                <td class="p-2">
                  <label for={"row-#{row.key}-last_name"} class="sr-only">
                    Last name
                  </label>
                  <input
                    type="text"
                    id={"row-#{row.key}-last_name"}
                    name={"row[#{row.key}][last_name]"}
                    value={row.last_name}
                    autocomplete="off"
                    placeholder="Last"
                    class={compact_input_classes(Map.get(row.errors, :last_name))}
                  />
                  <p :if={msg = Map.get(row.errors, :last_name)} class="mt-1 text-xs text-error">
                    {msg}
                  </p>
                </td>
                <td class="p-2 w-44">
                  <.gender_radio
                    field={gender_field(row)}
                    phx-click="set_gender"
                    phx-value-row={row.key}
                  />
                  <p
                    :if={msg = Map.get(row.errors, :gender_role)}
                    class="mt-1 text-xs text-error"
                  >
                    {msg}
                  </p>
                </td>
                <td class="p-2 w-20">
                  <label for={"row-#{row.key}-jersey"} class="sr-only">
                    Jersey number
                  </label>
                  <input
                    type="text"
                    id={"row-#{row.key}-jersey"}
                    name={"row[#{row.key}][jersey_number]"}
                    value={row.jersey_number}
                    autocomplete="off"
                    inputmode="numeric"
                    maxlength="4"
                    placeholder="—"
                    class={[
                      compact_input_classes(Map.get(row.errors, :jersey_number)),
                      "tabular-nums"
                    ]}
                  />
                  <p
                    :if={msg = Map.get(row.errors, :jersey_number)}
                    class="mt-1 text-xs text-error"
                  >
                    {msg}
                  </p>
                </td>
                <td class="p-2 w-12 text-right">
                  <button
                    type="button"
                    phx-click="remove_row"
                    phx-value-key={row.key}
                    aria-label="Remove row"
                    disabled={length(@rows) == 1}
                    class="min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-error active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-30 disabled:cursor-not-allowed"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="mt-3">
          <.button type="button" phx-click="add_row">
            <.icon name="hero-plus" /> Add row
          </.button>
        </div>

        <footer class="mt-6 flex items-center gap-3">
          <.button type="submit" variant="primary" phx-disable-with="Saving...">
            Save all
          </.button>
          <.button navigate={~p"/teams/#{@team}"}>Cancel</.button>
        </footer>
      </form>
    </Layouts.app>
    """
  end

  defp render_edit(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="player-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:first_name]} type="text" label="First name" />
        <.input field={@form[:last_name]} type="text" label="Last name" />
        <.input field={@form[:jersey_number]} type="text" label="Jersey number" />
        <.gender_radio field={@form[:gender_role]} phx-click="set_gender_edit" />
        <.input field={@form[:team_id]} type="hidden" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save</.button>
          <.button navigate={return_path(@return_to, @player)}>Cancel</.button>
        </footer>
      </.form>

      <section class="mt-12 pt-6 border-t border-base-300">
        <h2 class="text-sm font-semibold text-base-content">Danger zone</h2>
        <p class="mt-1 text-sm text-base-content/70">
          Removing a player drops them from the roster, line presets, and any pinned-player events on past games (events stay; their player attribution becomes empty).
        </p>
        <button
          type="button"
          id="delete-player"
          phx-click={JS.push("delete_player", value: %{id: @player.id})}
          data-confirm="Remove this player? This cannot be undone."
          class="mt-3 min-h-11 inline-flex items-center px-4 rounded-md text-sm font-medium border border-error text-error hover:bg-error/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-error"
        >
          Remove player
        </button>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to("team"), do: "team"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    player = Teams.get_player!(id)

    socket
    |> assign(:page_title, "Edit Player")
    |> assign(:player, player)
    |> assign(:form, to_form(Teams.change_player(player)))
  end

  defp apply_action(socket, :new, params) do
    case params["team_id"] do
      nil ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "Pick a team first to add a player.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/teams")

      team_id ->
        team = Teams.get_team!(team_id)
        {rows, next_key} = initial_rows()

        socket
        |> assign(:page_title, "Add players")
        |> assign(:team, team)
        |> assign(:rows, rows)
        |> assign(:next_key, next_key)
    end
  end

  ## ---- bulk-add events --------------------------------------------------

  @impl true
  def handle_event("add_row", _params, socket) do
    %{rows: rows, next_key: key} = socket.assigns
    {:noreply, socket |> assign(:rows, rows ++ [empty_row(key)]) |> assign(:next_key, key + 1)}
  end

  def handle_event("remove_row", %{"key" => key}, socket) do
    key = parse_key(key)
    rows = socket.assigns.rows

    rows =
      if length(rows) <= 1 do
        rows
      else
        Enum.reject(rows, &(&1.key == key))
      end

    {:noreply, assign(socket, :rows, rows)}
  end

  def handle_event("set_gender", %{"row" => row, "gender" => gender}, socket) do
    row_key = parse_key(row)
    role = parse_gender(gender)

    rows =
      Enum.map(socket.assigns.rows, fn r ->
        if r.key == row_key, do: %{r | gender_role: role}, else: r
      end)

    {:noreply, assign(socket, :rows, rows)}
  end

  def handle_event("save_all", params, socket) do
    rows = sync_rows_from_params(socket.assigns.rows, params)
    socket = assign(socket, :rows, rows)
    %{team: team} = socket.assigns

    if Enum.all?(rows, &blank_row?/1) do
      {:noreply, put_flash(socket, :error, "Add at least one player")}
    else
      case Teams.bulk_create_players(team, rows_to_attrs(rows)) do
        {:ok, players} ->
          {:noreply,
           socket
           |> put_flash(:info, "Created #{length(players)} players")
           |> push_navigate(to: ~p"/teams/#{team}")}

        {:error, {failing_index, changeset}} ->
          rows = attach_changeset_errors(rows, failing_index, changeset)
          {:noreply, assign(socket, :rows, rows)}
      end
    end
  end

  ## ---- single-edit events ----------------------------------------------

  def handle_event("set_gender_edit", %{"gender" => gender}, socket) do
    role_str = gender || ""

    params =
      (socket.assigns.form.params || %{})
      |> Map.put("gender_role", role_str)

    changeset =
      socket.assigns.player
      |> Teams.change_player(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  # Bulk-add validate (rows) — sync names/jersey numbers into @rows.
  def handle_event("validate", %{"row" => row_params}, socket) do
    rows = sync_rows_from_params(socket.assigns.rows, %{"row" => row_params})
    {:noreply, assign(socket, :rows, rows)}
  end

  # Single-edit validate — recompute changeset.
  def handle_event("validate", %{"player" => player_params}, socket) do
    changeset = Teams.change_player(socket.assigns.player, player_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", %{"player" => player_params}, socket) do
    save_player(socket, socket.assigns.live_action, player_params)
  end

  def handle_event("delete_player", %{"id" => id}, socket) do
    player = Teams.get_player!(id)
    {:ok, _} = Teams.delete_player(player)

    {:noreply,
     socket
     |> put_flash(:info, "Player removed")
     |> push_navigate(to: return_path(socket.assigns.return_to, player))}
  end

  defp sync_rows_from_params(rows, %{"row" => row_params}) do
    Enum.map(rows, fn r ->
      case Map.get(row_params, Integer.to_string(r.key)) do
        nil ->
          r

        fields ->
          %{
            r
            | first_name: Map.get(fields, "first_name", r.first_name) || "",
              last_name: Map.get(fields, "last_name", r.last_name) || "",
              jersey_number: Map.get(fields, "jersey_number", r.jersey_number) || ""
          }
      end
    end)
  end

  defp sync_rows_from_params(rows, _params), do: rows

  defp save_player(socket, :edit, player_params) do
    case Teams.update_player(socket.assigns.player, player_params) do
      {:ok, player} ->
        {:noreply,
         socket
         |> put_flash(:info, "Player updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, player))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _player), do: ~p"/players"
  defp return_path("show", player), do: ~p"/players/#{player}"

  defp return_path("team", %Player{team_id: team_id}) when is_binary(team_id),
    do: ~p"/teams/#{team_id}"

  defp return_path("team", _player), do: ~p"/players"

  ## ---- bulk-add helpers -------------------------------------------------

  defp initial_rows do
    rows = Enum.map(0..2, &empty_row/1)
    {rows, 3}
  end

  defp empty_row(key) do
    %{
      key: key,
      first_name: "",
      last_name: "",
      gender_role: nil,
      jersey_number: "",
      errors: %{}
    }
  end

  defp parse_key(key) when is_integer(key), do: key
  defp parse_key(key) when is_binary(key), do: String.to_integer(key)

  defp parse_gender("female_matching"), do: :female_matching
  defp parse_gender("male_matching"), do: :male_matching
  defp parse_gender(_), do: nil

  # A row is blank only when both names are blank — a row with one filled
  # name should still try to insert and surface a validation error.
  defp blank_row?(%{first_name: first, last_name: last}) do
    String.trim(first || "") == "" and String.trim(last || "") == ""
  end

  defp rows_to_attrs(rows) do
    Enum.map(rows, fn r ->
      %{
        first_name: r.first_name,
        last_name: r.last_name,
        gender_role: r.gender_role,
        jersey_number: nilify(r.jersey_number)
      }
    end)
  end

  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(value) when is_binary(value), do: value

  defp attach_changeset_errors(rows, failing_index, changeset) do
    # `failing_index` is the index into the *non-blank* rows passed to
    # bulk_create_players. Map it back to the original row in `rows`.
    non_blank_indices =
      rows
      |> Enum.with_index()
      |> Enum.reject(fn {r, _} -> blank_row?(r) end)
      |> Enum.map(fn {_, i} -> i end)

    target = Enum.at(non_blank_indices, failing_index)
    errors = changeset_errors_to_map(changeset)

    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, i} ->
      if i == target, do: %{row | errors: errors}, else: %{row | errors: %{}}
    end)
  end

  defp changeset_errors_to_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
      end)
    end)
    |> Enum.into(%{}, fn {field, [first_msg | _]} -> {field, first_msg} end)
  end

  defp gender_field(row) do
    %Phoenix.HTML.FormField{
      id: "row-#{row.key}-gender_role",
      name: "row[#{row.key}][gender_role]",
      errors: [],
      field: :gender_role,
      form: nil,
      value: gender_field_value(row.gender_role)
    }
  end

  defp gender_field_value(nil), do: nil
  defp gender_field_value(role) when is_atom(role), do: Atom.to_string(role)
  defp gender_field_value(role) when is_binary(role), do: role

  # Compact input style for the bulk-add table: reduced padding and
  # text size for density, but min-h-11 to preserve the 44px tap target
  # per UI_DESIGN.md §Tap targets.
  defp compact_input_classes(error?) do
    [
      "block w-full rounded-md border border-base-300 bg-base-100 px-2 py-1.5",
      "text-sm text-base-content placeholder:text-base-content/50 min-h-11",
      "focus:outline-2 focus:outline-offset-2 focus:outline-primary",
      error? && "border-error focus:outline-error"
    ]
  end
end
