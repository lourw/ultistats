defmodule UltistatsWeb.RulesetLive.Form do
  use UltistatsWeb, :live_view

  import UltistatsWeb.UIComponents, only: [gender_ratio_radio: 1, starting_ratio_radio: 1]

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
          field={@form[:timeouts_per_half]}
          type="number"
          label="Timeouts per half"
          min="0"
          max="5"
          inputmode="numeric"
        />

        <.input
          field={@form[:division]}
          type="select"
          label="Division"
          options={division_options()}
        />

        <div class="space-y-1">
          <p class="block text-sm font-medium text-base-content">Gender ratio rule</p>
          <.gender_ratio_radio field={@form[:gender_ratio_rule]} phx-click="set_ratio_rule" />
        </div>

        <div :if={ratio_rule(@form) != "none"} class="space-y-1">
          <p class="block text-sm font-medium text-base-content">Default starting ratio</p>
          <.starting_ratio_radio
            field={@form[:default_starting_ratio]}
            phx-click="set_starting_ratio"
          />
        </div>

        <.input field={@form[:team_id]} type="hidden" />

        <footer class="mt-4 flex items-center gap-3">
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
  defp return_to("team"), do: "team"
  defp return_to(_), do: "index"

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
        team = Teams.get_team!(team_id)

        ruleset = %Ruleset{
          team_id: team_id,
          kind: :template,
          division: team.division || :open,
          timeouts_per_half: 2,
          gender_ratio_rule: :endzone,
          default_starting_ratio: :four_men_three_women
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
    changeset = Games.change_ruleset(socket.assigns.ruleset, ruleset_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"ruleset" => ruleset_params}, socket) do
    save_ruleset(socket, socket.assigns.live_action, ruleset_params)
  end

  def handle_event("set_ratio_rule", %{"rule" => rule}, socket) do
    rule_str = rule || ""

    params =
      (socket.assigns.form.params || %{})
      |> Map.put("gender_ratio_rule", rule_str)
      |> maybe_clear_starting_ratio(rule_str)

    changeset =
      socket.assigns.ruleset
      |> Games.change_ruleset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("set_starting_ratio", %{"ratio" => ratio}, socket) do
    ratio_str = ratio || ""

    params =
      (socket.assigns.form.params || %{})
      |> Map.put("default_starting_ratio", ratio_str)

    changeset =
      socket.assigns.ruleset
      |> Games.change_ruleset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  defp maybe_clear_starting_ratio(params, "none"),
    do: Map.put(params, "default_starting_ratio", "")

  defp maybe_clear_starting_ratio(params, _), do: params

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

  defp return_path("index", _ruleset), do: ~p"/rulesets"
  defp return_path("show", ruleset), do: ~p"/rulesets/#{ruleset}"

  defp return_path("team", %Ruleset{team_id: team_id}) when is_binary(team_id),
    do: ~p"/teams/#{team_id}"

  defp return_path("team", _ruleset), do: ~p"/rulesets"

  defp division_options do
    [{"Open", :open}, {"Women's", :womens}, {"Mixed", :mixed}]
  end
end
