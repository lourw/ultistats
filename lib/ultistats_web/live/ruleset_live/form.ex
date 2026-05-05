defmodule UltistatsWeb.RulesetLive.Form do
  use UltistatsWeb, :live_view

  import UltistatsWeb.UIComponents, only: [gender_ratio_radio: 1]

  alias Ultistats.{Games, Teams}
  alias Ultistats.Games.Ruleset

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>
          Save a reusable rule template — score cap, halftime, caps, timeouts, gender ratio.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="ruleset-form"
        phx-change="validate"
        phx-submit="save"
        phx-debounce="300"
        class="flex flex-col gap-3"
      >
        <.input field={@form[:name]} type="text" label="Name" />

        <.input
          field={@form[:score_cap]}
          type="number"
          label="Score cap"
          min="1"
          max="30"
          inputmode="numeric"
          placeholder="e.g. 15 (leave blank for no score cap)"
        />

        <.input
          field={@form[:halftime_target]}
          type="number"
          label="Halftime target"
          min="1"
          inputmode="numeric"
          placeholder="e.g. 8 (leave blank for no halftime by score)"
        />

        <.input
          field={@form[:halftime_cap_minutes]}
          type="number"
          label="Halftime cap (minutes)"
          min="1"
          max="240"
          inputmode="numeric"
          placeholder="leave blank for no timed halftime"
        />

        <.input
          field={@form[:soft_cap_minutes]}
          type="number"
          label="Soft cap (minutes)"
          min="1"
          inputmode="numeric"
          placeholder="leave blank for no soft cap"
        />

        <.input
          field={@form[:hard_cap_minutes]}
          type="number"
          label="Hard cap (minutes)"
          min="1"
          inputmode="numeric"
          placeholder="leave blank for no hard cap"
        />

        <.input
          field={@form[:line_size]}
          type="number"
          label="Line size (players per point)"
          min="1"
          max="15"
          inputmode="numeric"
        />

        <.input
          field={@form[:timeouts_per_half]}
          type="number"
          label="Timeouts per half"
          min="0"
          max="5"
          inputmode="numeric"
        />

        <fieldset class="space-y-1">
          <legend class="block text-sm font-medium text-base-content">Division</legend>
          <div class="inline-flex flex-wrap items-center gap-2" role="radiogroup">
            <label
              :for={{label, value} <- division_options()}
              class={division_radio_label_classes(division(@form) == Atom.to_string(value))}
            >
              <input
                type="radio"
                name={@form[:division].name}
                id={"#{@form[:division].id}_#{value}"}
                value={value}
                checked={division(@form) == Atom.to_string(value)}
                class="accent-primary size-5 shrink-0"
              />
              <span class="text-sm leading-none">{label}</span>
            </label>
          </div>
        </fieldset>

        <div :if={division(@form) == "mixed"} class="space-y-1 mb-2">
          <p class="block text-sm font-medium text-base-content">Gender ratio rule</p>
          <.gender_ratio_radio field={@form[:gender_ratio_rule]} phx-click="set_ratio_rule" />
        </div>

        <div
          :if={division(@form) == "mixed" and ratio_rule(@form) != "none"}
          class="grid grid-cols-2 gap-3 mb-2"
        >
          <.input
            field={@form[:starting_male_count]}
            type="number"
            label="Starting M"
            min="0"
            max="15"
            inputmode="numeric"
          />
          <.input
            field={@form[:starting_female_count]}
            type="number"
            label="Starting F"
            min="0"
            max="15"
            inputmode="numeric"
          />
        </div>

        <.input field={@form[:team_id]} type="hidden" />

        <footer class="mt-4 pt-4 border-t border-base-300 flex items-center gap-3">
          <.button phx-disable-with="Saving..." variant="primary">Save Ruleset</.button>
          <.button navigate={return_path(@return_to, @ruleset)}>Cancel</.button>
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
  defp return_to(_), do: "team"

  defp apply_action(socket, :edit, %{"id" => id}) do
    ruleset = Games.get_ruleset!(id)
    current_user = socket.assigns.current_scope.user

    cond do
      not Teams.user_member_of?(current_user, ruleset.team_id) ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have permission to do that.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/teams")

      not Teams.user_admin_of?(current_user, ruleset.team_id) ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have permission to do that.")
        |> Phoenix.LiveView.push_navigate(to: ~p"/teams/#{ruleset.team_id}")

      true ->
        socket
        |> assign(:page_title, "Edit Ruleset")
        |> assign(:ruleset, ruleset)
        |> assign(:form, to_form(Games.change_ruleset(ruleset)))
    end
  end

  defp apply_action(socket, :new, %{"team_id" => team_id} = _params) when is_binary(team_id) do
    current_user = socket.assigns.current_scope.user

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
        ruleset = %Ruleset{
          team_id: team_id,
          kind: :template,
          division: :open,
          timeouts_per_half: 2,
          line_size: 7,
          gender_ratio_rule: :endzone,
          starting_male_count: 4,
          starting_female_count: 3
        }

        socket
        |> assign(:page_title, "New Ruleset")
        |> assign(:ruleset, ruleset)
        |> assign(:form, to_form(Games.change_ruleset(ruleset)))
    end
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> Phoenix.LiveView.put_flash(:error, "Pick a team first to add a ruleset.")
    |> Phoenix.LiveView.push_navigate(to: ~p"/teams")
  end

  @impl true
  def handle_event("validate", %{"ruleset" => ruleset_params}, socket) do
    ruleset_params = clear_ratio_when_not_mixed(ruleset_params)
    changeset = Games.change_ruleset(socket.assigns.ruleset, ruleset_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"ruleset" => ruleset_params}, socket) do
    save_ruleset(socket, socket.assigns.live_action, clear_ratio_when_not_mixed(ruleset_params))
  end

  def handle_event("set_ratio_rule", %{"rule" => rule}, socket) do
    rule_str = rule || ""

    params =
      (socket.assigns.form.params || %{})
      |> Map.put("gender_ratio_rule", rule_str)

    changeset =
      socket.assigns.ruleset
      |> Games.change_ruleset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  defp save_ruleset(socket, :edit, ruleset_params) do
    user = socket.assigns.current_scope.user

    if not Teams.user_admin_of?(user, socket.assigns.ruleset.team_id) do
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    else
      case Games.update_ruleset(socket.assigns.ruleset, ruleset_params) do
        {:ok, ruleset} ->
          {:noreply,
           socket
           |> put_flash(:info, "Ruleset updated successfully")
           |> push_navigate(to: return_path(socket.assigns.return_to, ruleset))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  defp save_ruleset(socket, :new, ruleset_params) do
    user = socket.assigns.current_scope.user
    team_id = socket.assigns.ruleset.team_id

    if not Teams.user_admin_of?(user, team_id) do
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    else
      attrs = Map.put_new(ruleset_params, "kind", "template")

      case Games.create_ruleset(attrs) do
        {:ok, ruleset} ->
          {:noreply,
           socket
           |> put_flash(:info, "Ruleset created successfully")
           |> push_navigate(to: return_path(socket.assigns.return_to, ruleset))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  # Reads the current ratio rule string off the form for the
  # "hide starting ratio when none" branch in render/1.
  defp ratio_rule(%Phoenix.HTML.Form{} = form) do
    case form[:gender_ratio_rule].value do
      nil -> ""
      v when is_atom(v) -> Atom.to_string(v)
      v when is_binary(v) -> v
    end
  end

  # Reads the current division string off the form so the render gates
  # the gender-ratio block on `:mixed`.
  defp division(%Phoenix.HTML.Form{} = form) do
    case form[:division].value do
      nil -> ""
      v when is_atom(v) -> Atom.to_string(v)
      v when is_binary(v) -> v
    end
  end

  # Non-mixed divisions (open / women's) don't carry a ratio. Force the
  # rule to `:none` and clear both starting counts so the row submits a
  # valid changeset regardless of whatever the (now-hidden) inputs held
  # before the division switch.
  defp clear_ratio_when_not_mixed(%{"division" => "mixed"} = params), do: params

  defp clear_ratio_when_not_mixed(params) when is_map(params) do
    params
    |> Map.put("gender_ratio_rule", "none")
    |> Map.put("starting_male_count", "")
    |> Map.put("starting_female_count", "")
  end

  defp return_path("show", ruleset), do: ~p"/rulesets/#{ruleset}"

  defp return_path("team", %Ruleset{team_id: team_id}) when is_binary(team_id),
    do: ~p"/teams/#{team_id}"

  defp return_path("team", _ruleset), do: ~p"/games"

  defp division_options do
    [{"Open", :open}, {"Women's", :womens}, {"Mixed", :mixed}]
  end

  defp division_radio_label_classes(selected?) do
    [
      "min-h-11 inline-flex items-center gap-2 px-3 py-1.5 rounded-md text-sm font-medium",
      "border border-base-300 cursor-pointer select-none",
      "focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-primary",
      if(selected?,
        do: "bg-primary/10 border-primary text-base-content",
        else: "bg-base-100 text-base-content active:bg-base-200"
      )
    ]
  end
end
