defmodule UltistatsWeb.GameLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Teams}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Games
        <:actions>
          <.button :if={@active_tab == :games} variant="primary" navigate={~p"/games/new"}>
            <.icon name="hero-plus" /> New game
          </.button>
          <.button
            :if={
              @active_tab == :rulesets && @new_ruleset_team_id &&
                MapSet.member?(@admin_team_ids, @new_ruleset_team_id)
            }
            variant="primary"
            navigate={~p"/rulesets/new?team_id=#{@new_ruleset_team_id}"}
          >
            <.icon name="hero-plus" /> New ruleset
          </.button>
        </:actions>
      </.header>

      <div
        role="tablist"
        aria-label="Games sections"
        class="mt-4 flex gap-6 border-b border-base-200"
      >
        <button
          type="button"
          role="tab"
          id="tab-games"
          aria-selected={to_string(@active_tab == :games)}
          phx-click="set_tab"
          phx-value-tab="games"
          class={[
            tab_classes(@active_tab == :games),
            "phx-click-loading:text-primary phx-click-loading:border-primary"
          ]}
        >
          Games
          <span class={[
            "ml-1.5 tabular-nums text-xs px-1.5 py-0.5 rounded-full",
            if(@active_tab == :games,
              do: "bg-primary/10 text-primary",
              else: "bg-base-200 text-base-content/70"
            )
          ]}>
            {length(@games)}
          </span>
        </button>
        <button
          type="button"
          role="tab"
          id="tab-rulesets"
          aria-selected={to_string(@active_tab == :rulesets)}
          phx-click="set_tab"
          phx-value-tab="rulesets"
          class={[
            tab_classes(@active_tab == :rulesets),
            "phx-click-loading:text-primary phx-click-loading:border-primary"
          ]}
        >
          Rulesets
          <span class={[
            "ml-1.5 tabular-nums text-xs px-1.5 py-0.5 rounded-full",
            if(@active_tab == :rulesets,
              do: "bg-primary/10 text-primary",
              else: "bg-base-200 text-base-content/70"
            )
          ]}>
            {length(@rulesets)}
          </span>
        </button>
      </div>

      <section :if={@active_tab == :games} class="mt-4 pb-24" aria-labelledby="tab-games">
        <ul
          :if={@games != []}
          id="games-list"
          class="rounded-md border border-base-200 divide-y divide-base-200 overflow-hidden"
        >
          <li
            :for={game <- @games}
            id={"game-#{game.id}"}
            class="min-h-14 flex items-stretch gap-1 pr-2"
          >
            <.link
              navigate={~p"/games/#{game.id}"}
              class="flex-1 min-w-0 flex items-center gap-2 px-4 py-2.5 hover:bg-base-200 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              <div class="flex-1 min-w-0 space-y-1">
                <div class="font-medium text-sm truncate leading-tight">
                  {team_name(game)} vs {game.opponent_name}
                </div>
                <div class="text-xs text-base-content/70 tabular-nums leading-tight">
                  {format_started_at(game.started_at)}
                </div>
              </div>
              <span class={[
                "text-[11px] font-semibold px-2 py-0.5 rounded-full shrink-0",
                status_pill_classes(game.status)
              ]}>
                {status_label(game.status)}
              </span>
            </.link>
            <.link
              navigate={~p"/games/#{game.id}/timeline"}
              aria-label={"Open timeline for #{team_name(game)} vs #{game.opponent_name}"}
              class="shrink-0 self-center min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              <.icon name="hero-list-bullet" class="size-4" />
            </.link>
            <button
              :if={MapSet.member?(@admin_team_ids, game.team_id)}
              type="button"
              phx-click="delete_game"
              phx-value-id={game.id}
              data-confirm="Delete this game? Points and events will be removed. This can't be undone."
              aria-label={"Delete #{team_name(game)} vs #{game.opponent_name}"}
              class="shrink-0 self-center min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-error/70 hover:text-error active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-error"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </li>
        </ul>

        <p :if={@games == []} class="mt-4 text-base-content/70">
          No games yet, create a new one to start collecting your stats.
        </p>
      </section>

      <section :if={@active_tab == :rulesets} class="mt-4 pb-24" aria-labelledby="tab-rulesets">
        <div :if={length(@rulesets) > 1} class="flex flex-col gap-1 mb-3">
          <span
            id="ruleset-division-filter-label"
            class="text-[11px] uppercase tracking-wide text-base-content/60"
          >
            Division
          </span>
          <div
            role="radiogroup"
            aria-labelledby="ruleset-division-filter-label"
            class="flex flex-wrap items-center gap-1.5"
          >
            <button
              :for={{label, value} <- division_filter_options()}
              type="button"
              phx-click="set_division_filter"
              phx-value-division={value}
              role="radio"
              aria-checked={to_string(value == @division_filter)}
              class={[
                "min-h-7 px-2.5 py-0.5 rounded-full border text-[11px] font-medium",
                "active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                if(value == @division_filter,
                  do: "border-primary bg-primary/10 text-primary",
                  else: "border-base-300 bg-base-100 text-base-content/70"
                )
              ]}
            >
              {label}
            </button>
          </div>
        </div>

        <ul
          :if={@rulesets != []}
          id="rulesets-list"
          class="rounded-md border border-base-200 divide-y divide-base-200 overflow-hidden"
        >
          <li
            :for={r <- visible_rulesets(@rulesets, @division_filter)}
            id={"ruleset-#{r.id}"}
            class="min-h-14 flex items-center gap-2 px-3 py-2"
          >
            <span class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0">
              {score_cap_badge(r.score_cap)}
            </span>
            <div class="flex-1 min-w-0 space-y-1">
              <div class="font-medium text-sm truncate leading-tight">{r.name}</div>
              <div class="text-[11px] text-base-content/60 truncate leading-tight">
                {ruleset_summary_line(r)}
              </div>
            </div>
            <.link
              :if={MapSet.member?(@admin_team_ids, r.team_id)}
              navigate={~p"/rulesets/#{r.id}/edit"}
              aria-label={"Edit #{r.name}"}
              class="shrink-0 min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.link>
          </li>
        </ul>

        <p :if={@rulesets == [] && @new_ruleset_team_id} class="mt-4 text-base-content/70">
          No rulesets yet. Save one as a reusable template for future games.
        </p>

        <p :if={@rulesets == [] and is_nil(@new_ruleset_team_id)} class="mt-4 text-base-content/70">
          No rulesets yet. Add a team first.
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    teams = Teams.list_teams_for_user(user)
    admin_team_ids = MapSet.new(teams, & &1.id) |> filter_admin_teams(user)
    new_ruleset_team_id = pick_default_team_id(admin_team_ids, teams)

    {:ok,
     socket
     |> assign(:active_tab, :games)
     |> assign(:teams, teams)
     |> assign(:admin_team_ids, admin_team_ids)
     |> assign(:new_ruleset_team_id, new_ruleset_team_id)
     |> assign(:division_filter, "all")
     |> assign(:games, list_games_for_user(user))
     |> assign(:rulesets, Games.list_rulesets_for_user(user))}
  end

  defp filter_admin_teams(team_ids_set, user) do
    team_ids_set
    |> Enum.filter(&Teams.user_admin_of?(user, &1))
    |> MapSet.new()
  end

  @impl true
  def handle_event("set_tab", %{"tab" => "games"}, socket) do
    {:noreply, assign(socket, :active_tab, :games)}
  end

  def handle_event("set_tab", %{"tab" => "rulesets"}, socket) do
    {:noreply, assign(socket, :active_tab, :rulesets)}
  end

  def handle_event("set_division_filter", %{"division" => division}, socket)
      when division in ["all", "open", "mixed", "womens"] do
    {:noreply, assign(socket, :division_filter, division)}
  end

  def handle_event("delete_game", %{"id" => game_id}, socket) do
    user = socket.assigns.current_scope.user
    game = Games.get_game!(game_id)

    if Teams.user_admin_of?(user, game.team_id) do
      case Games.delete_game(game) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:games, list_games_for_user(user))
           |> put_flash(:info, "Game deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete game.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to delete that game.")}
    end
  end

  defp list_games_for_user(user) do
    Games.list_games_for_user(user)
  end

  # Prefer a team where the user is an admin (so the FAB can navigate
  # to /rulesets/new). If no admin teams exist, falls back to the first
  # member team (FAB will be hidden anyway by the admin-gate).
  defp pick_default_team_id(_admin_team_ids, []), do: nil

  defp pick_default_team_id(admin_team_ids, [first | _] = teams) do
    case Enum.find(teams, &MapSet.member?(admin_team_ids, &1.id)) do
      nil -> first.id
      t -> t.id
    end
  end

  defp team_name(%{team: %{name: name}}), do: name
  defp team_name(_), do: "—"

  defp score_cap_badge(nil), do: "—"
  defp score_cap_badge(n) when is_integer(n), do: Integer.to_string(n)

  defp status_label(:in_progress), do: "In progress"
  defp status_label(:finished), do: "Final"
  defp status_label(:abandoned), do: "Abandoned"
  defp status_label(other), do: to_string(other)

  defp status_pill_classes(:in_progress), do: "bg-info/10 text-info"
  defp status_pill_classes(:finished), do: "bg-success/10 text-success"
  defp status_pill_classes(:abandoned), do: "bg-base-200 text-base-content/70"
  defp status_pill_classes(_), do: "bg-base-200 text-base-content"

  defp format_started_at(nil), do: "—"

  defp format_started_at(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d · %H:%M")
  end

  defp tab_classes(true),
    do:
      "min-h-11 inline-flex items-center pb-3 -mb-px text-sm font-medium text-primary border-b-2 border-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp tab_classes(false),
    do:
      "min-h-11 inline-flex items-center pb-3 -mb-px text-sm font-medium text-base-content/60 hover:text-base-content border-b-2 border-transparent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  defp division_filter_options do
    [{"All divisions", "all"}, {"Open", "open"}, {"Women's", "womens"}, {"Mixed", "mixed"}]
  end

  defp visible_rulesets(rulesets, "all"), do: rulesets

  defp visible_rulesets(rulesets, division) when division in ["open", "womens", "mixed"] do
    atom = String.to_existing_atom(division)
    Enum.filter(rulesets, &(&1.division == atom))
  end

  defp ruleset_summary_line(r) do
    [
      "to #{score_cap_badge(r.score_cap)}",
      "half #{value_or_dash(r.halftime_target)}",
      "soft #{minutes(r.soft_cap_minutes)}",
      "hard #{minutes(r.hard_cap_minutes)}"
    ]
    |> Enum.join(" · ")
  end

  defp value_or_dash(nil), do: "—"
  defp value_or_dash(n) when is_integer(n), do: Integer.to_string(n)

  defp minutes(nil), do: "—"
  defp minutes(n) when is_integer(n), do: "#{n}m"
end
