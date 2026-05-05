defmodule UltistatsWeb.LinePresetLive.Form do
  use UltistatsWeb, :live_view

  alias Ultistats.Accounts.User
  alias Ultistats.Teams
  alias Ultistats.Teams.LinePreset

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.form
        for={@form}
        id="line_preset-form"
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col gap-3"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Line name"
          class="block w-full rounded-md border border-base-300 bg-base-100 px-3 py-1 text-base-content placeholder:text-base-content/50 min-h-9 focus:outline-2 focus:outline-offset-2 focus:outline-primary disabled:opacity-50"
        />
        <.input field={@form[:team_id]} type="hidden" />

        <section class="flex flex-col gap-3">
          <div :if={@team_members == []} class="text-base-content/70">
            This team has no players yet. Add some to the roster first.
          </div>

          <div
            :if={@team_members != []}
            class="flex items-center gap-2 text-xs text-base-content/60"
          >
            <span>Sort:</span>
            <div
              role="group"
              aria-label="Sort players"
              class="inline-flex rounded-md border border-base-300 overflow-hidden"
            >
              <button
                type="button"
                phx-click="set_sort"
                phx-value-by="jersey"
                aria-pressed={to_string(@sort_by == :jersey)}
                class={[
                  sort_button_classes(@sort_by == :jersey),
                  "phx-click-loading:bg-primary phx-click-loading:text-primary-content"
                ]}
              >
                Jersey
              </button>
              <button
                type="button"
                phx-click="set_sort"
                phx-value-by="first_name"
                aria-pressed={to_string(@sort_by == :first_name)}
                class={[
                  sort_button_classes(@sort_by == :first_name),
                  "phx-click-loading:bg-primary phx-click-loading:text-primary-content"
                ]}
              >
                First name
              </button>
            </div>
          </div>

          <div :if={@team_members != []} id="preset-roster" class="flex flex-col gap-6">
            <.preset_roster_section
              :for={{role, members} <- @members_by_role}
              role={role}
              members={members}
              selected_ids={@selected_user_ids}
            />
          </div>
        </section>

        <div
          :if={@team_members != []}
          class="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs"
          aria-label="Selected players by position"
        >
          <span class="text-base-content/60">Selected</span>
          <span class="tabular-nums font-semibold text-base-content">
            {MapSet.size(@selected_user_ids)}
          </span>
          <span class="text-base-content/30" aria-hidden="true">·</span>
          <span
            :for={pos <- [:handler, :cutter, :hybrid, :unspecified]}
            :if={@position_counts[pos] not in [nil, 0] or pos != :unspecified}
            class="inline-flex items-center gap-1"
          >
            <span
              class={[
                "inline-flex items-center justify-center size-5 rounded-full text-[10px] font-semibold tabular-nums",
                position_pill_classes(pos)
              ]}
              aria-label={humanize_position(pos) || "Unspecified"}
              title={humanize_position(pos) || "Unspecified"}
            >
              {position_letter(pos)}
            </span>
            <span class="tabular-nums text-base-content/80">
              {@position_counts[pos] || 0}
            </span>
          </span>
        </div>

        <footer class="mt-3 flex gap-2">
          <.button phx-disable-with="Saving..." variant="primary">Save</.button>
          <.button navigate={return_path(@return_to, @line_preset)}>Cancel</.button>
        </footer>
      </.form>

      <section :if={@live_action == :edit} class="mt-12 pt-6 border-t border-base-300">
        <h2 class="text-sm font-semibold text-base-content">Danger zone</h2>
        <p class="mt-1 text-sm text-base-content/70">
          Deleting a line doesn't affect the underlying players.
        </p>
        <button
          type="button"
          id="delete-line-preset"
          phx-click={JS.push("delete_line_preset", value: %{id: @line_preset.id})}
          data-confirm="Delete this line?"
          class="mt-3 min-h-11 inline-flex items-center px-4 rounded-md text-sm font-medium border border-error text-error hover:bg-error/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-error"
        >
          Delete line
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
    line_preset = Teams.get_line_preset!(id)
    current_user = socket.assigns.current_scope.user

    cond do
      not Teams.user_member_of?(current_user, line_preset.team_id) ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have permission to do that.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/teams")

      not Teams.user_admin_of?(current_user, line_preset.team_id) ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have permission to do that.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/teams/#{line_preset.team_id}")

      true ->
        team_members = Teams.list_players_for_team(line_preset.team_id)

        selected_user_ids =
          line_preset.users
          |> Enum.map(& &1.id)
          |> MapSet.new()

        sort_by = socket.assigns[:sort_by] || :jersey

        socket
        |> assign(:page_title, "Edit line")
        |> assign(:line_preset, line_preset)
        |> assign(:team_members, team_members)
        |> assign(:selected_user_ids, selected_user_ids)
        |> assign(:form, to_form(Teams.change_line_preset(line_preset)))
        |> assign(:sort_by, sort_by)
        |> assign(:members_by_role, members_by_role(team_members, sort_by))
        |> assign(:position_counts, position_counts(team_members, selected_user_ids))
    end
  end

  defp apply_action(socket, :new, params) do
    current_user = socket.assigns.current_scope.user
    team_id = params["team_id"]

    cond do
      is_nil(team_id) ->
        line_preset = %LinePreset{team_id: nil}

        socket
        |> assign(:page_title, "New line")
        |> assign(:line_preset, line_preset)
        |> assign(:team_members, [])
        |> assign(:selected_user_ids, MapSet.new())
        |> assign(:form, to_form(Teams.change_line_preset(line_preset)))
        |> assign_new(:sort_by, fn -> :jersey end)
        |> assign(:members_by_role, [])
        |> assign(:position_counts, %{})

      not Teams.user_member_of?(current_user, team_id) ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have permission to do that.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/teams")

      not Teams.user_admin_of?(current_user, team_id) ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have permission to do that.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/teams/#{team_id}")

      true ->
        line_preset = %LinePreset{team_id: team_id}
        team_members = Teams.list_players_for_team(team_id)
        sort_by = socket.assigns[:sort_by] || :jersey

        socket
        |> assign(:page_title, "New line")
        |> assign(:line_preset, line_preset)
        |> assign(:team_members, team_members)
        |> assign(:selected_user_ids, MapSet.new())
        |> assign(:form, to_form(Teams.change_line_preset(line_preset)))
        |> assign(:sort_by, sort_by)
        |> assign(:members_by_role, members_by_role(team_members, sort_by))
        |> assign(:position_counts, %{})
    end
  end

  @impl true
  def handle_event("toggle_player", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_user_ids, id) do
        MapSet.delete(socket.assigns.selected_user_ids, id)
      else
        # Defensive: only allow toggling users in the team roster.
        if Enum.any?(socket.assigns.team_members, &(&1.user_id == id)) do
          MapSet.put(socket.assigns.selected_user_ids, id)
        else
          socket.assigns.selected_user_ids
        end
      end

    {:noreply,
     socket
     |> assign(:selected_user_ids, selected)
     |> assign(:position_counts, position_counts(socket.assigns.team_members, selected))}
  end

  def handle_event("validate", %{"line_preset" => line_preset_params}, socket) do
    changeset = Teams.change_line_preset(socket.assigns.line_preset, line_preset_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"line_preset" => line_preset_params}, socket) do
    save_line_preset(socket, socket.assigns.live_action, line_preset_params)
  end

  def handle_event("set_sort", %{"by" => "jersey"}, socket) do
    {:noreply, apply_sort(socket, :jersey)}
  end

  def handle_event("set_sort", %{"by" => "first_name"}, socket) do
    {:noreply, apply_sort(socket, :first_name)}
  end

  def handle_event("delete_line_preset", %{"id" => id}, socket) do
    preset = Teams.get_line_preset!(id)
    user = socket.assigns.current_scope.user

    if Teams.user_admin_of?(user, preset.team_id) do
      {:ok, _} = Teams.delete_line_preset(preset)

      {:noreply,
       socket
       |> put_flash(:info, "Line deleted")
       |> push_navigate(to: return_path(socket.assigns.return_to, preset))}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    end
  end

  defp apply_sort(socket, sort_by) do
    socket
    |> assign(:sort_by, sort_by)
    |> assign(:members_by_role, members_by_role(socket.assigns.team_members, sort_by))
  end

  defp save_line_preset(socket, :edit, line_preset_params) do
    user = socket.assigns.current_scope.user

    if not Teams.user_admin_of?(user, socket.assigns.line_preset.team_id) do
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    else
      attrs = with_user_ids(line_preset_params, socket.assigns.selected_user_ids)

      case Teams.update_line_preset(socket.assigns.line_preset, attrs) do
        {:ok, line_preset} ->
          {:noreply,
           socket
           |> put_flash(:info, "Line updated")
           |> push_navigate(to: return_path(socket.assigns.return_to, line_preset))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  defp save_line_preset(socket, :new, line_preset_params) do
    user = socket.assigns.current_scope.user
    team_id = socket.assigns.line_preset.team_id

    if not Teams.user_admin_of?(user, team_id) do
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    else
      attrs = with_user_ids(line_preset_params, socket.assigns.selected_user_ids)

      case Teams.create_line_preset(attrs) do
        {:ok, line_preset} ->
          {:noreply,
           socket
           |> put_flash(:info, "Line created")
           |> push_navigate(to: return_path(socket.assigns.return_to, line_preset))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  defp with_user_ids(params, selected) when is_map(params) do
    Map.put(params, "user_ids", MapSet.to_list(selected))
  end

  attr :role, :atom, required: true, values: [:female_matching, :male_matching]
  attr :members, :list, required: true
  attr :selected_ids, MapSet, required: true

  defp preset_roster_section(assigns) do
    selected_in_section =
      Enum.count(assigns.members, &MapSet.member?(assigns.selected_ids, &1.user_id))

    assigns = assign(assigns, :selected_in_section, selected_in_section)

    ~H"""
    <section class="space-y-1">
      <h3 class="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-wide text-base-content/60 px-4">
        <span>{role_label(@role)}</span>
        <span class="tabular-nums text-base-content/50">
          {@selected_in_section} of {length(@members)}
        </span>
      </h3>

      <ul class="-mx-4 border-y border-base-200 divide-y divide-base-200">
        <li :for={member <- @members} id={"preset-player-#{member.user_id}"}>
          <button
            type="button"
            phx-click="toggle_player"
            phx-value-id={member.user_id}
            aria-pressed={to_string(MapSet.member?(@selected_ids, member.user_id))}
            class={[
              "w-full min-h-9 pl-10 pr-4 py-0.5 flex items-center gap-2 text-left",
              "transition-colors motion-reduce:transition-none active:bg-base-200",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              "phx-click-loading:bg-primary/10",
              if(MapSet.member?(@selected_ids, member.user_id), do: "bg-primary/10", else: "")
            ]}
          >
            <span
              :if={Teams.resolved_jersey_number(member)}
              class={[
                "tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full text-[11px] shrink-0",
                if(MapSet.member?(@selected_ids, member.user_id),
                  do: "bg-primary text-primary-content",
                  else: "bg-base-200 text-base-content"
                )
              ]}
            >
              {Teams.resolved_jersey_number(member)}
            </span>
            <span class="flex items-center gap-1.5 flex-1 min-w-0">
              <span class="font-medium text-sm truncate leading-tight">
                {User.display_name(member.user)}
              </span>
              <span
                :if={pos = Teams.resolved_position(member)}
                class={[
                  "inline-flex items-center justify-center size-5 rounded-full shrink-0",
                  "text-[10px] font-semibold tabular-nums",
                  position_pill_classes(pos)
                ]}
                aria-label={humanize_position(pos)}
                title={humanize_position(pos)}
              >
                {position_letter(pos)}
              </span>
            </span>
            <.icon
              :if={MapSet.member?(@selected_ids, member.user_id)}
              name="hero-check-circle-solid"
              class="size-4 text-primary shrink-0"
            />
          </button>
        </li>
      </ul>
    </section>
    """
  end

  defp role_label(:male_matching), do: "Male-matching"
  defp role_label(:female_matching), do: "Female-matching"

  defp position_counts(team_members, selected_ids) do
    team_members
    |> Enum.filter(&MapSet.member?(selected_ids, &1.user_id))
    |> Enum.group_by(fn m -> Teams.resolved_position(m) || :unspecified end)
    |> Map.new(fn {k, v} -> {k, length(v)} end)
  end

  # Pre-grouped + sorted members per gender role, computed once per
  # roster/sort change so the template doesn't redo it on every render.
  defp members_by_role(team_members, sort_by) do
    for role <- [:male_matching, :female_matching],
        members =
          team_members
          |> Enum.filter(&(&1.user.gender_role == role))
          |> sort_members(sort_by),
        members != [] do
      {role, members}
    end
  end

  defp position_letter(:handler), do: "H"
  defp position_letter(:cutter), do: "C"
  defp position_letter(:hybrid), do: "X"
  defp position_letter(_), do: "?"

  defp position_pill_classes(:handler), do: "bg-success/15 text-success"
  defp position_pill_classes(:cutter), do: "bg-warning/15 text-warning"
  defp position_pill_classes(:hybrid), do: "bg-info/15 text-info"
  defp position_pill_classes(_), do: "bg-base-200 text-base-content/70"

  defp humanize_position(:handler), do: "Handler"
  defp humanize_position(:cutter), do: "Cutter"
  defp humanize_position(:hybrid), do: "Hybrid"
  defp humanize_position(_), do: nil

  # Numeric ordering on jersey_number when parseable (so "9" < "10");
  # non-numeric jerseys fall back to a lexicographic compare against
  # other non-numerics; nil/blank jerseys sort to the end.
  defp sort_members(members, :jersey) do
    Enum.sort_by(members, &jersey_sort_key/1)
  end

  defp sort_members(members, :first_name) do
    Enum.sort_by(members, &String.downcase(&1.user.first_name || ""))
  end

  defp jersey_sort_key(member) do
    case Teams.resolved_jersey_number(member) do
      nil ->
        {2, 0, ""}

      "" ->
        {2, 0, ""}

      j when is_binary(j) ->
        case Integer.parse(j) do
          {n, ""} -> {0, n, j}
          _ -> {1, 0, j}
        end
    end
  end

  defp sort_button_classes(true),
    do:
      "min-h-9 px-3 py-1 text-xs font-semibold bg-primary text-primary-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp sort_button_classes(false),
    do:
      "min-h-9 px-3 py-1 text-xs font-semibold text-base-content/70 hover:text-base-content hover:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp return_path("index", _line_preset), do: ~p"/line_presets"
  defp return_path("show", line_preset), do: ~p"/line_presets/#{line_preset}"

  defp return_path("team", %LinePreset{team_id: team_id}) when is_binary(team_id),
    do: ~p"/teams/#{team_id}"

  defp return_path("team", _line_preset), do: ~p"/line_presets"
end
