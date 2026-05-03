defmodule UltistatsWeb.GameLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Repo, Teams}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Games
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
          class={tab_classes(@active_tab == :games)}
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
          class={tab_classes(@active_tab == :rulesets)}
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
        <ul :if={@games != []} id="games-list" class="divide-y divide-base-300">
          <li :for={game <- @games} id={"game-#{game.id}"} class="py-3">
            <.link
              navigate={~p"/games/#{game.id}"}
              class="flex items-center justify-between gap-3 min-h-11 -mx-2 px-2 rounded-md hover:bg-base-200 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              <div class="min-w-0">
                <div class="font-medium truncate">
                  {team_name(game)} vs {game.opponent_name}
                </div>
                <div class="text-sm text-base-content/70 tabular-nums">
                  {format_started_at(game.started_at)}
                </div>
              </div>
              <span class={[
                "text-xs font-semibold px-2 py-1 rounded-full shrink-0",
                status_pill_classes(game.status)
              ]}>
                {status_label(game.status)}
              </span>
            </.link>
          </li>
        </ul>

        <p :if={@games == []} class="mt-4 text-base-content/70">
          No games yet. Tap the + button to start one.
        </p>
      </section>

      <section :if={@active_tab == :rulesets} class="mt-4 pb-24" aria-labelledby="tab-rulesets">
        <div :if={length(@teams) > 1} class="flex items-center gap-2 mb-3">
          <label for="ruleset-team-select" class="text-sm text-base-content/70">Team</label>
          <form phx-change="select_ruleset_team">
            <select
              id="ruleset-team-select"
              name="team_id"
              class="select select-sm select-bordered min-h-11"
            >
              <option :for={team <- @teams} value={team.id} selected={team.id == @new_ruleset_team_id}>
                {team.name}
              </option>
            </select>
          </form>
        </div>

        <ul :if={@rulesets != []} id="rulesets-list" class="divide-y divide-base-300">
          <li
            :for={r <- @rulesets}
            id={"ruleset-#{r.id}"}
            class="flex items-center justify-between gap-3 py-3"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span class="inline-flex items-center justify-center min-w-8 h-7 px-2 rounded-full bg-base-200 text-base-content text-sm font-semibold tabular-nums shrink-0">
                {score_cap_badge(r.score_cap)}
              </span>
              <div class="min-w-0">
                <div class="font-medium truncate">{r.name}</div>
                <div class="text-xs text-base-content/60 truncate">
                  {team_label(r)}
                </div>
              </div>
            </div>
            <.link
              navigate={~p"/rulesets/#{r.id}/edit"}
              aria-label={"Edit #{r.name}"}
              class="shrink-0 min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              <.icon name="hero-pencil-square" class="size-5" />
            </.link>
          </li>
        </ul>

        <p :if={@rulesets == [] and @new_ruleset_team_id} class="mt-4 text-base-content/70">
          No rulesets yet. Save one as a reusable template for future games.
        </p>

        <p :if={@rulesets == [] and is_nil(@new_ruleset_team_id)} class="mt-4 text-base-content/70">
          No rulesets yet. Add a team first.
        </p>
      </section>

      <.link
        :if={@active_tab == :games}
        navigate={~p"/games/new"}
        aria-label="Add game"
        class="fixed bottom-6 right-6 z-40 size-14 rounded-full bg-primary text-primary-content shadow-lg flex items-center justify-center hover:bg-primary/90 active:scale-[0.97] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary motion-reduce:active:scale-100"
      >
        <.icon name="hero-plus" class="size-6" />
      </.link>

      <.link
        :if={@active_tab == :rulesets and @new_ruleset_team_id}
        navigate={~p"/rulesets/new?team_id=#{@new_ruleset_team_id}"}
        aria-label="Add ruleset"
        class="fixed bottom-6 right-6 z-40 size-14 rounded-full bg-primary text-primary-content shadow-lg flex items-center justify-center hover:bg-primary/90 active:scale-[0.97] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary motion-reduce:active:scale-100"
      >
        <.icon name="hero-plus" class="size-6" />
      </.link>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    teams = Teams.list_teams()
    new_ruleset_team_id = pick_default_team_id(teams)

    {:ok,
     socket
     |> assign(:active_tab, :games)
     |> assign(:teams, teams)
     |> assign(:new_ruleset_team_id, new_ruleset_team_id)
     |> assign(:games, list_games())
     |> assign(:rulesets, Games.list_rulesets_across_teams())}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => "games"}, socket) do
    {:noreply, assign(socket, :active_tab, :games)}
  end

  def handle_event("set_tab", %{"tab" => "rulesets"}, socket) do
    {:noreply, assign(socket, :active_tab, :rulesets)}
  end

  def handle_event("select_ruleset_team", %{"team_id" => team_id}, socket) do
    {:noreply, assign(socket, :new_ruleset_team_id, team_id)}
  end

  defp list_games do
    Games.list_games()
    |> Repo.preload(:team)
    |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
  end

  defp pick_default_team_id([]), do: nil
  defp pick_default_team_id([t | _]), do: t.id

  defp team_name(%{team: %{name: name}}), do: name
  defp team_name(_), do: "—"

  defp team_label(%{team: %{name: name}}) when is_binary(name), do: name
  defp team_label(_), do: "—"

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
end
