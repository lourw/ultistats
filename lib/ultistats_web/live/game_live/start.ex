defmodule UltistatsWeb.GameLive.Start do
  use UltistatsWeb, :live_view

  alias Ultistats.Games
  alias Ultistats.Games.{Game, Ruleset}
  alias Ultistats.Teams

  # Field names mirrored from `Ruleset` schema. We render an input for
  # each one and forward the values through to `Games.start_game/1` as
  # `rule_overrides` (atom-keyed map) on submit.
  @rule_int_fields [
    :score_cap,
    :halftime_target,
    :halftime_cap_minutes,
    :soft_cap_minutes,
    :hard_cap_minutes,
    :timeouts_per_half
  ]

  @rule_atom_fields [:gender_ratio_rule, :default_starting_ratio]

  # Form-level defaults. Single-gender (open / women's) is the most
  # common case so the form starts with `gender_ratio_rule: "none"`. The
  # Division control re-applies these on switch to "Mixed".
  @open_defaults %{
    "score_cap" => "15",
    "halftime_target" => "8",
    "halftime_cap_minutes" => "",
    "soft_cap_minutes" => "",
    "hard_cap_minutes" => "",
    "timeouts_per_half" => "2",
    "gender_ratio_rule" => "none",
    "default_starting_ratio" => ""
  }

  @mixed_overrides %{
    "gender_ratio_rule" => "endzone",
    "default_starting_ratio" => "four_men_three_women"
  }

  # `@usau_defaults` is the legacy alias other clauses still reference;
  # treat it as the form's no-template starting state, which is now
  # single-gender by default.
  @usau_defaults @open_defaults

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Start a game
        <:subtitle>Pick the team, name the opponent, and call the first pull.</:subtitle>
      </.header>

      <div :if={@teams == []} id="no-teams-empty-state" class="mt-6">
        <div class="rounded-md bg-base-200 p-4">
          <p class="font-medium">Create a team first</p>
          <p class="text-sm text-base-content/70 mt-1">
            You need at least one team before you can start a game.
          </p>
          <div class="mt-3">
            <.button variant="primary" navigate={~p"/teams/new"}>
              <.icon name="hero-plus" /> New team
            </.button>
          </div>
        </div>
      </div>

      <.form
        :if={@teams != []}
        for={@form}
        id="game-form"
        phx-change="validate"
        phx-submit="save"
      >
        <div class="flex flex-col gap-3">
          <.input
            :if={length(@teams) > 1}
            field={@form[:team_id]}
            type="select"
            label="Team"
            prompt="Select team"
            options={team_options(@teams)}
          />
          <.input :if={length(@teams) == 1} field={@form[:team_id]} type="hidden" />

          <.input field={@form[:opponent_name]} type="text" label="Opponent" maxlength="80" />

          <fieldset>
            <legend class="block text-sm font-medium text-base-content mb-2">Division</legend>
            <div role="radiogroup" aria-label="Division" class="grid grid-cols-3 gap-2">
              <button
                :for={{value, label} <- division_options()}
                type="button"
                role="radio"
                aria-checked={to_string(@division == value)}
                phx-click="set_division"
                phx-value-division={value}
                class={division_chip_classes(@division == value)}
              >
                {label}
              </button>
            </div>
          </fieldset>

          <.input
            field={@form[:first_pull]}
            type="select"
            label="First pull"
            options={first_pull_options()}
          />

          <.input field={@form[:format]} type="hidden" />

          <.input
            field={@form[:ruleset_id]}
            type="select"
            label="Ruleset"
            prompt="USAU standard (no template)"
            options={ruleset_options(@team_rulesets)}
          />

          <p :if={@ruleset_error} class="text-sm text-error">{@ruleset_error}</p>

          <fieldset class="flex flex-col gap-3">
            <legend class="block text-sm font-medium text-base-content">
              Rules for this game
            </legend>

            <.input
              id="game_rule_overrides_score_cap"
              name="rule_overrides[score_cap]"
              value={Map.get(@rule_overrides, "score_cap", "")}
              type="number"
              label="Score cap"
              min="1"
              max="30"
              inputmode="numeric"
              placeholder="leave blank for no score cap"
            />
            <.input
              id="game_rule_overrides_halftime_target"
              name="rule_overrides[halftime_target]"
              value={Map.get(@rule_overrides, "halftime_target", "")}
              type="number"
              label="Halftime target"
              min="1"
              inputmode="numeric"
              placeholder="leave blank for no halftime by score"
            />
            <.input
              id="game_rule_overrides_halftime_cap_minutes"
              name="rule_overrides[halftime_cap_minutes]"
              value={Map.get(@rule_overrides, "halftime_cap_minutes", "")}
              type="number"
              label="Halftime cap (minutes)"
              min="1"
              max="240"
              inputmode="numeric"
              placeholder="leave blank for no timed halftime"
            />
            <.input
              id="game_rule_overrides_soft_cap_minutes"
              name="rule_overrides[soft_cap_minutes]"
              value={Map.get(@rule_overrides, "soft_cap_minutes", "")}
              type="number"
              label="Soft cap (minutes)"
              min="1"
              inputmode="numeric"
              placeholder="leave blank for no soft cap"
            />
            <.input
              id="game_rule_overrides_hard_cap_minutes"
              name="rule_overrides[hard_cap_minutes]"
              value={Map.get(@rule_overrides, "hard_cap_minutes", "")}
              type="number"
              label="Hard cap (minutes)"
              min="1"
              inputmode="numeric"
              placeholder="leave blank for no hard cap"
            />
            <.input
              id="game_rule_overrides_timeouts_per_half"
              name="rule_overrides[timeouts_per_half]"
              value={Map.get(@rule_overrides, "timeouts_per_half", "")}
              type="number"
              label="Timeouts per half"
              min="0"
              max="5"
              inputmode="numeric"
            />
            <.input
              id="game_rule_overrides_gender_ratio_rule"
              name="rule_overrides[gender_ratio_rule]"
              value={Map.get(@rule_overrides, "gender_ratio_rule", "")}
              type="select"
              label="Gender ratio rule"
              options={ratio_rule_options()}
            />
            <.input
              :if={Map.get(@rule_overrides, "gender_ratio_rule") != "none"}
              id="game_rule_overrides_default_starting_ratio"
              name="rule_overrides[default_starting_ratio]"
              value={Map.get(@rule_overrides, "default_starting_ratio", "")}
              type="select"
              label="Default starting ratio"
              options={starting_ratio_options()}
            />
          </fieldset>
        </div>

        <footer class="sticky bottom-0 -mx-4 mt-8 flex items-center gap-3 border-t border-base-300 bg-base-100/95 px-4 py-3 backdrop-blur supports-[backdrop-filter]:bg-base-100/80">
          <.button phx-disable-with="Starting..." variant="primary">Start game</.button>
          <.button navigate={cancel_path(@cancel_team_id)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_scope.user
    teams = Teams.list_teams_for_user(user)
    requested_team_id = params["team_id"]

    selected_team_id = pick_team_id(teams, requested_team_id)
    division = team_division(teams, selected_team_id)

    game = %Game{
      team_id: selected_team_id,
      format: :usau_standard,
      first_pull: :ours
    }

    {:ok,
     socket
     |> assign(:page_title, "Start a game")
     |> assign(:teams, teams)
     |> assign(:cancel_team_id, selected_team_id)
     |> assign(:team_rulesets, list_rulesets(selected_team_id, division))
     |> assign(:selected_ruleset_id, "")
     |> assign(:division, division)
     |> assign(:rule_overrides, defaults_for_division(division))
     |> assign(:ruleset_error, nil)
     |> assign(:form, to_form(Games.change_game(game)))}
  end

  @impl true
  def handle_event("validate", %{"game" => game_params} = params, socket) do
    # Ruleset/team changes refresh dependent state (templates list,
    # rule-field defaults).
    new_team_id =
      game_params
      |> Map.get("team_id")
      |> nilify_blank()
      |> Kernel.||(socket.assigns.cancel_team_id)

    new_ruleset_id = Map.get(game_params, "ruleset_id", "")

    division =
      if new_team_id != socket.assigns.cancel_team_id do
        team_division(socket.assigns.teams, new_team_id)
      else
        socket.assigns.division
      end

    team_rulesets =
      if new_team_id != socket.assigns.cancel_team_id do
        list_rulesets(new_team_id, division)
      else
        socket.assigns.team_rulesets
      end

    rule_overrides =
      cond do
        # Team changed — the previously-selected ruleset is no longer
        # valid. Reset to division-appropriate defaults.
        new_team_id != socket.assigns.cancel_team_id ->
          defaults_for_division(division)

        # Ruleset selection changed — prefill from the new selection.
        new_ruleset_id != socket.assigns.selected_ruleset_id ->
          prefill_overrides(new_ruleset_id, team_rulesets)

        # Same ruleset, user is editing fields — keep their edits.
        true ->
          merge_overrides(socket.assigns.rule_overrides, params["rule_overrides"])
      end

    changeset =
      %Game{}
      |> Games.change_game(merge_defaults(game_params))
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:cancel_team_id, new_team_id)
     |> assign(:division, division)
     |> assign(:team_rulesets, team_rulesets)
     |> assign(:selected_ruleset_id, new_ruleset_id)
     |> assign(:rule_overrides, rule_overrides)
     |> assign(:ruleset_error, nil)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("save", %{"game" => game_params} = params, socket) do
    rule_overrides_params = Map.get(params, "rule_overrides", %{})

    case validate_picker(game_params, socket.assigns.team_rulesets) do
      :ok ->
        attrs =
          game_params
          |> merge_defaults()
          |> Map.put(:rule_overrides, parse_overrides(rule_overrides_params))
          |> normalize_ruleset_id()

        case Games.start_game(attrs) do
          {:ok, game} ->
            {:noreply,
             socket
             |> put_flash(:info, "Game started")
             |> push_navigate(to: ~p"/games/#{game.id}")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
        end

      {:error, msg} ->
        {:noreply, assign(socket, :ruleset_error, msg)}
    end
  end

  # Division segmented control — Open (default), Mixed, Women's. Updates
  # the form's rule_overrides to the appropriate gender-ratio defaults
  # *unless* a ruleset template is currently selected (the template wins).
  def handle_event("set_division", %{"division" => division}, socket)
      when division in ["open", "mixed", "womens"] do
    overrides =
      cond do
        # A picked template owns the ratio fields — Division is a quick-pick
        # that only kicks in when no template is selected.
        socket.assigns.selected_ruleset_id != "" ->
          socket.assigns.rule_overrides

        division == "mixed" ->
          Map.merge(socket.assigns.rule_overrides, @mixed_overrides)

        # open + womens: single-gender, no ratio
        true ->
          socket.assigns.rule_overrides
          |> Map.put("gender_ratio_rule", "none")
          |> Map.put("default_starting_ratio", "")
      end

    team_rulesets = list_rulesets(socket.assigns.cancel_team_id, division)

    {:noreply,
     socket
     |> assign(:division, division)
     |> assign(:rule_overrides, overrides)
     |> assign(:team_rulesets, team_rulesets)
     |> assign(:selected_ruleset_id, "")}
  end

  # Force MVP-fixed defaults regardless of what the form posts (format hidden,
  # but defensive — the start-game flow doesn't expose configurability).
  defp merge_defaults(params) do
    params
    |> Map.put_new("format", "usau_standard")
    |> Map.put_new("first_pull", "ours")
  end

  defp pick_team_id([], _requested), do: nil

  defp pick_team_id(teams, requested_id) when is_binary(requested_id) do
    if Enum.any?(teams, &(&1.id == requested_id)) do
      requested_id
    else
      pick_team_id(teams, nil)
    end
  end

  defp pick_team_id([single], _), do: single.id
  defp pick_team_id(_teams, _), do: nil

  defp team_options(teams) do
    Enum.map(teams, &{&1.name, &1.id})
  end

  defp first_pull_options do
    [
      {"We pull (start on defense)", :ours},
      {"They pull (start on offense)", :theirs}
    ]
  end

  defp division_options do
    [{"open", "Open"}, {"mixed", "Mixed"}, {"womens", "Women's"}]
  end

  defp division_chip_classes(true),
    do:
      "min-h-11 inline-flex items-center justify-center px-3 rounded-md text-sm font-semibold bg-primary text-primary-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp division_chip_classes(false),
    do:
      "min-h-11 inline-flex items-center justify-center px-3 rounded-md text-sm font-semibold border border-base-300 text-base-content/80 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp ruleset_options([]), do: []
  defp ruleset_options(rulesets), do: Enum.map(rulesets, &{&1.name, &1.id})

  defp ratio_rule_options do
    [
      {"Endzone (USAU genzone)", "endzone"},
      {"Alternating (ABBA)", "alternating"},
      {"Fixed", "fixed"},
      {"None", "none"}
    ]
  end

  defp starting_ratio_options do
    [{"4M / 3F", "four_men_three_women"}, {"3M / 4F", "three_men_four_women"}]
  end

  defp list_rulesets(nil), do: []
  defp list_rulesets(team_id) when is_binary(team_id), do: Games.list_rulesets_for_team(team_id)

  defp list_rulesets(nil, _division), do: []

  defp list_rulesets(team_id, division)
       when is_binary(team_id) and division in ["open", "mixed", "womens"] do
    Games.list_rulesets_for_team(team_id, String.to_existing_atom(division))
  end

  defp list_rulesets(team_id, division)
       when is_binary(team_id) and division in [:open, :mixed, :womens] do
    Games.list_rulesets_for_team(team_id, division)
  end

  defp list_rulesets(team_id, _division), do: list_rulesets(team_id)

  defp team_division(_teams, nil), do: "open"

  defp team_division(teams, team_id) do
    case Enum.find(teams, &(&1.id == team_id)) do
      %{division: division} when not is_nil(division) -> Atom.to_string(division)
      _ -> "open"
    end
  end

  defp defaults_for_division("mixed"), do: Map.merge(@open_defaults, @mixed_overrides)
  defp defaults_for_division(_other), do: @open_defaults

  defp prefill_overrides("", _team_rulesets), do: @usau_defaults

  defp prefill_overrides(ruleset_id, team_rulesets) when is_binary(ruleset_id) do
    case Enum.find(team_rulesets, &(&1.id == ruleset_id)) do
      %Ruleset{} = r -> ruleset_to_overrides(r)
      _ -> @usau_defaults
    end
  end

  defp ruleset_to_overrides(%Ruleset{} = r) do
    %{
      "score_cap" => stringify(r.score_cap),
      "halftime_target" => stringify(r.halftime_target),
      "halftime_cap_minutes" => stringify(r.halftime_cap_minutes),
      "soft_cap_minutes" => stringify(r.soft_cap_minutes),
      "hard_cap_minutes" => stringify(r.hard_cap_minutes),
      "timeouts_per_half" => stringify(r.timeouts_per_half),
      "gender_ratio_rule" => stringify(r.gender_ratio_rule),
      "default_starting_ratio" => stringify(r.default_starting_ratio)
    }
  end

  defp stringify(nil), do: ""
  defp stringify(v) when is_binary(v), do: v
  defp stringify(v) when is_atom(v), do: Atom.to_string(v)
  defp stringify(v) when is_integer(v), do: Integer.to_string(v)

  defp merge_overrides(prev, nil), do: prev

  defp merge_overrides(prev, posted) when is_map(prev) and is_map(posted) do
    Enum.reduce(prev, %{}, fn {key, _val}, acc ->
      Map.put(acc, key, Map.get(posted, key, Map.get(prev, key)))
    end)
  end

  defp validate_picker(%{"ruleset_id" => ""}, _team_rulesets), do: :ok
  defp validate_picker(%{"ruleset_id" => nil}, _team_rulesets), do: :ok

  defp validate_picker(%{"ruleset_id" => id}, team_rulesets) when is_binary(id) do
    if Enum.any?(team_rulesets, &(&1.id == id)) do
      :ok
    else
      {:error, "That ruleset is no longer available for this team."}
    end
  end

  defp validate_picker(_, _), do: :ok

  defp normalize_ruleset_id(%{"ruleset_id" => ""} = attrs), do: Map.delete(attrs, "ruleset_id")
  defp normalize_ruleset_id(%{"ruleset_id" => nil} = attrs), do: Map.delete(attrs, "ruleset_id")
  defp normalize_ruleset_id(attrs), do: attrs

  # Convert the string-keyed form params for rule overrides into an
  # atom-keyed map suitable for `Games.start_game/1`. Empty strings drop
  # out (treated as "no override / use template/default value").
  defp parse_overrides(params) when is_map(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      with atom when atom in @rule_int_fields or atom in @rule_atom_fields <-
             safe_to_existing_atom(key),
           parsed when not is_nil(parsed) <- parse_value(atom, value) do
        Map.put(acc, atom, parsed)
      else
        _ -> acc
      end
    end)
  end

  defp parse_overrides(_), do: %{}

  defp parse_value(_field, ""), do: nil
  defp parse_value(_field, nil), do: nil

  defp parse_value(field, value) when field in @rule_int_fields and is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_value(field, value) when field in @rule_atom_fields and is_binary(value) do
    safe_to_existing_atom(value)
  end

  defp parse_value(_, _), do: nil

  defp safe_to_existing_atom(s) when is_binary(s) do
    String.to_existing_atom(s)
  rescue
    ArgumentError -> nil
  end

  defp safe_to_existing_atom(_), do: nil

  defp cancel_path(team_id) when is_binary(team_id) and team_id != "",
    do: ~p"/teams/#{team_id}"

  defp cancel_path(_), do: ~p"/teams"

  defp nilify_blank(nil), do: nil
  defp nilify_blank(""), do: nil
  defp nilify_blank(s) when is_binary(s), do: s
end
