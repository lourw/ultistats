defmodule UltistatsWeb.PlayerLive.Form do
  use UltistatsWeb, :live_view

  import UltistatsWeb.UIComponents, only: [gender_radio: 1, position_radio: 1]

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
        <ul class="flex flex-col gap-3">
          <li
            :for={row <- @rows}
            id={"player-row-#{row.key}"}
            data-row-key={row.key}
            class="rounded-lg border border-base-300 bg-base-100 p-3 space-y-3"
          >
            <div class="flex items-start gap-2">
              <div class="flex-1 min-w-0">
                <label for={"row-#{row.key}-first_name"} class="sr-only">First name</label>
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
              </div>
              <div class="flex-1 min-w-0">
                <label for={"row-#{row.key}-last_name"} class="sr-only">Last name</label>
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
              </div>
              <div class="w-20 shrink-0">
                <label for={"row-#{row.key}-jersey"} class="sr-only">Jersey number</label>
                <input
                  type="text"
                  id={"row-#{row.key}-jersey"}
                  name={"row[#{row.key}][jersey_number]"}
                  value={row.jersey_number}
                  autocomplete="off"
                  inputmode="numeric"
                  maxlength="4"
                  placeholder="#"
                  class={[
                    compact_input_classes(Map.get(row.errors, :jersey_number)),
                    "tabular-nums text-center"
                  ]}
                />
                <p :if={msg = Map.get(row.errors, :jersey_number)} class="mt-1 text-xs text-error">
                  {msg}
                </p>
              </div>
              <button
                type="button"
                phx-click="remove_row"
                phx-value-key={row.key}
                aria-label="Remove row"
                disabled={length(@rows) == 1}
                class="min-h-11 min-w-11 shrink-0 inline-flex items-center justify-center rounded-md text-error active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-30 disabled:cursor-not-allowed"
              >
                <.icon name="hero-trash" class="size-5" />
              </button>
            </div>

            <div class="flex flex-wrap items-start gap-x-6 gap-y-2">
              <div>
                <p class="mb-1 text-xs font-medium text-base-content/70">Gender</p>
                <.gender_radio
                  field={gender_field(row)}
                  phx-click="set_gender"
                  phx-value-row={row.key}
                />
                <p :if={msg = Map.get(row.errors, :gender_role)} class="mt-1 text-xs text-error">
                  {msg}
                </p>
              </div>
              <div>
                <p class="mb-1 text-xs font-medium text-base-content/70">Position</p>
                <.position_radio
                  field={position_field(row)}
                  phx-click="set_position"
                  phx-value-row={row.key}
                />
                <p :if={msg = Map.get(row.errors, :position)} class="mt-1 text-xs text-error">
                  {msg}
                </p>
              </div>
            </div>
          </li>
        </ul>

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
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage player records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="player-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:first_name]} type="text" label="First name" />
        <.input field={@form[:last_name]} type="text" label="Last name" />
        <.input field={@form[:jersey_number]} type="text" label="Jersey number" />

        <div class="space-y-1 mb-2">
          <p class="block text-sm font-medium text-base-content">Gender</p>
          <.gender_radio field={@form[:gender_role]} phx-click="set_gender_edit" />
        </div>

        <div class="space-y-1 mb-2">
          <p class="block text-sm font-medium text-base-content">Position</p>
          <.position_radio field={@form[:position]} phx-click="set_position_edit" />
        </div>

        <.input field={@form[:team_id]} type="hidden" />
        <footer class="mt-4 flex items-center gap-3">
          <.button phx-disable-with="Saving..." variant="primary">Save Player</.button>
          <.button navigate={return_path(@return_to, @player)}>Cancel</.button>
        </footer>
      </.form>
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

  def handle_event("set_position", %{"row" => row, "position" => position}, socket) do
    row_key = parse_key(row)
    pos = parse_position(position)

    rows =
      Enum.map(socket.assigns.rows, fn r ->
        if r.key == row_key, do: %{r | position: pos || r.position}, else: r
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

  def handle_event("set_position_edit", %{"position" => position}, socket) do
    pos_str = position || ""

    params =
      (socket.assigns.form.params || %{})
      |> Map.put("position", pos_str)

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
              jersey_number: Map.get(fields, "jersey_number", r.jersey_number) || "",
              position: parse_position(Map.get(fields, "position")) || r.position
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
    {[empty_row(0)], 1}
  end

  defp empty_row(key) do
    %{
      key: key,
      first_name: "",
      last_name: "",
      gender_role: nil,
      position: :cutter,
      jersey_number: "",
      errors: %{}
    }
  end

  defp parse_key(key) when is_integer(key), do: key
  defp parse_key(key) when is_binary(key), do: String.to_integer(key)

  defp parse_gender("female_matching"), do: :female_matching
  defp parse_gender("male_matching"), do: :male_matching
  defp parse_gender(_), do: nil

  defp parse_position("handler"), do: :handler
  defp parse_position("cutter"), do: :cutter
  defp parse_position("hybrid"), do: :hybrid
  defp parse_position(_), do: nil

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
        position: r.position,
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

  defp position_field(row) do
    %Phoenix.HTML.FormField{
      id: "row-#{row.key}-position",
      name: "row[#{row.key}][position]",
      errors: [],
      field: :position,
      form: nil,
      value: position_field_value(row.position)
    }
  end

  defp position_field_value(nil), do: nil
  defp position_field_value(pos) when is_atom(pos), do: Atom.to_string(pos)
  defp position_field_value(pos) when is_binary(pos), do: pos

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
