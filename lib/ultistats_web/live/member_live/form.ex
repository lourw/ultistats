defmodule UltistatsWeb.MemberLive.Form do
  use UltistatsWeb, :live_view

  import UltistatsWeb.UIComponents, only: [gender_radio: 1, position_radio: 1, role_radio: 1]

  alias Ultistats.Accounts.User
  alias Ultistats.Teams
  alias Ultistats.Teams.TeamMembership

  @impl true
  def render(%{live_action: :new} = assigns), do: render_bulk_new(assigns)
  def render(%{live_action: :edit} = assigns), do: render_edit(assigns)

  defp render_bulk_new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Add members to {@team.name}
        <:subtitle>
          First name, last name and gender are required. Jersey numbers are optional.
        </:subtitle>
      </.header>

      <form id="bulk-member-form" phx-change="validate" phx-submit="save_all">
        <ul class="flex flex-col gap-3">
          <li
            :for={row <- @rows}
            id={"member-row-#{row.key}"}
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

            <div class="flex flex-wrap items-center gap-x-6 gap-y-2">
              <label class="inline-flex items-center gap-2 min-h-11 cursor-pointer">
                <input type="hidden" name={"row[#{row.key}][is_player]"} value="false" />
                <input
                  type="checkbox"
                  name={"row[#{row.key}][is_player]"}
                  value="true"
                  checked={row.is_player}
                  class="accent-primary size-5"
                />
                <span class="text-sm">Include in lines</span>
              </label>
              <label class="inline-flex items-center gap-2 min-h-11 cursor-pointer">
                <input type="hidden" name={"row[#{row.key}][is_admin]"} value="false" />
                <input
                  type="checkbox"
                  name={"row[#{row.key}][is_admin]"}
                  value="true"
                  checked={row.role == :admin}
                  class="accent-primary size-5"
                />
                <span class="text-sm">Admin</span>
              </label>
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
          <.button navigate={cancel_path(@return_to, @team)}>Cancel</.button>
        </footer>
      </form>
    </Layouts.app>
    """
  end

  defp render_edit(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Edit team-membership fields. The user's profile is theirs to edit.</:subtitle>
      </.header>

      <.form for={@form} id="member-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <input type="hidden" name="member[team_id]" value={@membership.team_id} />

        <div class="rounded-lg border border-base-200 bg-base-100/60 px-4 py-3">
          <p class="text-xs uppercase tracking-wide text-base-content/60">Member</p>
          <p class="text-base font-semibold text-base-content">
            {User.display_name(@user)}
          </p>
          <p class="text-xs text-base-content/60">{humanize_gender_role(@user.gender_role)}</p>
        </div>

        <div class="space-y-1">
          <p class="block text-sm font-medium text-base-content">Jersey number</p>
          <.input field={@form[:jersey_number]} type="text" inputmode="numeric" maxlength="4" />
        </div>

        <div class="space-y-1">
          <p class="block text-sm font-medium text-base-content">Position</p>
          <.position_radio field={@form[:position]} phx-click="set_position_edit" />
        </div>

        <div class="space-y-1">
          <p class="block text-sm font-medium text-base-content">Role</p>
          <.role_radio field={role_form_field(@form)} phx-click="set_role_edit" />
        </div>

        <div class="space-y-1">
          <p class="block text-sm font-medium text-base-content">Include in lines</p>
          <label class="inline-flex items-center gap-2 min-h-11 cursor-pointer">
            <input type="hidden" name="member[is_player]" value="false" />
            <input
              type="checkbox"
              name="member[is_player]"
              value="true"
              checked={@form[:is_player].value in [true, "true"]}
              class="accent-primary size-5"
            />
            <span class="text-sm text-base-content/70">
              Non-players don't show up in line selection or in line presets.
            </span>
          </label>
        </div>

        <footer class="sticky bottom-0 -mx-4 mt-8 flex items-center gap-3 border-t border-base-300 bg-base-100/95 px-4 py-3 backdrop-blur supports-[backdrop-filter]:bg-base-100/80">
          <.button phx-disable-with="Saving..." variant="primary">Save member</.button>
          <.button navigate={return_path(@return_to, @membership)}>Cancel</.button>
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
    membership = Teams.get_team_membership!(id)
    user = membership.user
    current_user = socket.assigns.current_scope.user

    cond do
      not Teams.user_member_of?(current_user, membership.team_id) ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have permission to do that.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/teams")

      not Teams.user_admin_of?(current_user, membership.team_id) ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have permission to do that.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/teams/#{membership.team_id}")

      true ->
        # Position / jersey on the form reflect the membership row,
        # falling back to the user's defaults so the form shows the
        # currently effective value even when the membership has no
        # override.
        form_data = %{
          "position" => Teams.resolved_position(membership),
          "jersey_number" => Teams.resolved_jersey_number(membership),
          "is_player" => membership.is_player,
          "role" => membership.role
        }

        socket
        |> assign(:page_title, "Edit member")
        |> assign(:membership, membership)
        |> assign(:user, user)
        |> assign(:form, to_form(form_data, as: "member"))
    end
  end

  defp apply_action(socket, :new, params) do
    current_user = socket.assigns.current_scope.user

    case params["team_id"] do
      nil ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "Pick a team first to add a member.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/teams")

      team_id ->
        cond do
          not Teams.user_member_of?(current_user, team_id) ->
            socket
            |> Phoenix.LiveView.put_flash(:error, "You don't have permission to do that.")
            |> Phoenix.LiveView.push_navigate(to: ~p"/teams")

          not Teams.user_admin_of?(current_user, team_id) ->
            socket
            |> Phoenix.LiveView.put_flash(:error, "You don't have permission to do that.")
            |> Phoenix.LiveView.push_navigate(to: ~p"/teams/#{team_id}")

          true ->
            team = Teams.get_team!(team_id)
            {rows, next_key} = initial_rows()

            socket
            |> assign(:page_title, "Add members")
            |> assign(:team, team)
            |> assign(:rows, rows)
            |> assign(:next_key, next_key)
        end
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
    current_user = socket.assigns.current_scope.user

    cond do
      not Teams.user_admin_of?(current_user, team) ->
        {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}

      Enum.all?(rows, &blank_row?/1) ->
        {:noreply, put_flash(socket, :error, "Add at least one member")}

      true ->
        case Teams.bulk_create_members_with_stub_users(team, rows_to_attrs(rows)) do
          {:ok, results} ->
            {:noreply,
             socket
             |> put_flash(:info, "Created #{length(results)} members")
             |> push_navigate(to: ~p"/teams/#{team}")}

          {:error, {failing_index, _step, changeset}} ->
            rows = attach_changeset_errors(rows, failing_index, changeset)
            {:noreply, assign(socket, :rows, rows)}
        end
    end
  end

  ## ---- single-edit events ----------------------------------------------

  def handle_event("set_position_edit", %{"position" => position}, socket) do
    pos_str = position || ""

    params =
      (socket.assigns.form.params || %{})
      |> Map.put("position", pos_str)

    {:noreply, assign(socket, :form, to_form(params, as: "member"))}
  end

  def handle_event("set_role_edit", %{"role" => role}, socket) do
    role_str = role || ""

    params =
      (socket.assigns.form.params || %{})
      |> Map.put("role", role_str)

    {:noreply, assign(socket, :form, to_form(params, as: "member"))}
  end

  # Bulk-add validate (rows) — sync names/jersey numbers/checkbox state into @rows.
  def handle_event("validate", %{"row" => row_params} = _params, socket) do
    rows = sync_rows_from_params(socket.assigns.rows, %{"row" => row_params})
    {:noreply, assign(socket, :rows, rows)}
  end

  # Single-edit validate — keep params intact (we don't run a changeset
  # here; submission goes through update_member_with_user/2 which will
  # surface server-side errors).
  def handle_event("validate", %{"member" => member_params}, socket) do
    {:noreply, assign(socket, form: to_form(member_params, as: "member"))}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", %{"member" => member_params}, socket) do
    save_member(socket, member_params)
  end

  defp save_member(socket, member_params) do
    attrs = build_edit_attrs(member_params)
    current_user = socket.assigns.current_scope.user
    membership = socket.assigns.membership

    if not Teams.user_admin_of?(current_user, membership.team_id) do
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    else
      do_save_member(socket, attrs, member_params)
    end
  end

  defp do_save_member(socket, attrs, member_params) do
    case Teams.update_member_with_user(socket.assigns.membership, attrs) do
      {:ok, %{membership: membership}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Member updated")
         |> push_navigate(to: edit_return_path(socket.assigns.return_to, membership))}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        # Surface validation errors back into the form. We rebuild
        # form params from the submitted values plus the failed
        # changeset's field errors.
        errors_map =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {k, v}, acc ->
              String.replace(acc, "%{#{k}}", to_string(v))
            end)
          end)

        form =
          to_form(member_params,
            as: "member",
            errors:
              Enum.flat_map(errors_map, fn {field, [first | _]} -> [{field, {first, []}}] end)
          )

        {:noreply, assign(socket, :form, form)}
    end
  end

  defp build_edit_attrs(member_params) do
    is_player = member_params["is_player"] in [true, "true"]

    %{
      position: parse_position(member_params["position"]),
      jersey_number: nilify(member_params["jersey_number"]),
      is_player: is_player,
      role: parse_role(member_params)
    }
  end

  defp parse_role(%{"role" => role}) when role in ["admin", :admin], do: :admin
  defp parse_role(%{"role" => role}) when role in ["member", :member], do: :member
  defp parse_role(%{"is_admin" => v}) when v in [true, "true"], do: :admin
  defp parse_role(_), do: :member

  # Build a `Phoenix.HTML.FormField` for the role pill so the edit form
  # can drive `<.role_radio>` from either the persisted membership role
  # (atom) or a transient string value re-stuffed by `set_role_edit`.
  defp role_form_field(form) do
    %Phoenix.HTML.FormField{
      id: "member_role",
      name: "member[role]",
      errors: [],
      field: :role,
      form: form,
      value: form[:role].value
    }
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
              position: parse_position(Map.get(fields, "position")) || r.position,
              is_player: Map.get(fields, "is_player") in ["true", true],
              role: if(Map.get(fields, "is_admin") in ["true", true], do: :admin, else: :member)
          }
      end
    end)
  end

  defp sync_rows_from_params(rows, _params), do: rows

  defp cancel_path("team", %_{id: team_id}), do: ~p"/teams/#{team_id}"
  defp cancel_path(_, _team), do: ~p"/members"

  defp return_path("team", %TeamMembership{} = membership),
    do: ~p"/teams/#{membership.team_id}"

  defp return_path("show", %TeamMembership{} = membership), do: ~p"/members/#{membership.id}"
  defp return_path(_, _membership), do: ~p"/members"

  # On a successful edit, we want to land somewhere sensible. "team"
  # returns to the team show; "show" returns to the membership show;
  # default returns to the members index.
  defp edit_return_path("team", membership), do: ~p"/teams/#{membership.team_id}"
  defp edit_return_path("show", membership), do: ~p"/members/#{membership.id}"
  defp edit_return_path(_, _membership), do: ~p"/members"

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
      is_player: true,
      role: :member,
      errors: %{}
    }
  end

  defp parse_key(key) when is_integer(key), do: key
  defp parse_key(key) when is_binary(key), do: String.to_integer(key)

  defp parse_gender("female_matching"), do: :female_matching
  defp parse_gender("male_matching"), do: :male_matching
  defp parse_gender(value) when value in [:female_matching, :male_matching], do: value
  defp parse_gender(_), do: nil

  defp parse_position("handler"), do: :handler
  defp parse_position("cutter"), do: :cutter
  defp parse_position("hybrid"), do: :hybrid
  defp parse_position(value) when value in [:handler, :cutter, :hybrid], do: value
  defp parse_position(_), do: nil

  # A row is blank only when both names are blank — a row with one
  # filled name should still try to insert and surface a validation
  # error.
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
        jersey_number: nilify(r.jersey_number),
        is_player: r.is_player,
        role: r.role
      }
    end)
  end

  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(value) when is_binary(value), do: value

  defp attach_changeset_errors(rows, failing_index, changeset) do
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

  defp humanize_gender_role(:female_matching), do: "Female-matching"
  defp humanize_gender_role(:male_matching), do: "Male-matching"
  defp humanize_gender_role(_), do: "—"
end
