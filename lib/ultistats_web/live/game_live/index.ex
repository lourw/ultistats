defmodule UltistatsWeb.GameLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Repo, Teams}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Games
        <:subtitle>Most-recent first.</:subtitle>
        <:actions>
          <.button :if={@active_tab == :games} variant="primary" navigate={~p"/games/new"}>
            <.icon name="hero-plus" /> New game
          </.button>
          <.button
            :if={@active_tab == :rulesets and @new_ruleset_team_id}
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
        class="mt-2 inline-flex rounded-md border border-base-300 p-1 bg-base-100"
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
          Games · <span class="tabular-nums">{length(@games)}</span>
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
          Rulesets · <span class="tabular-nums">{length(@rulesets)}</span>
        </button>
      </div>

      <section :if={@active_tab == :games} class="mt-4" aria-labelledby="tab-games">
        <p :if={@games == []} class="text-base-content/70">
          No games yet. <.link navigate={~p"/games/new"} class="underline">Start one</.link>.
        </p>

        <ul :if={@games != []} id="games-list" class="divide-y divide-base-200">
          <li :for={game <- @games} id={"game-#{game.id}"} class="py-3">
            <.link
              navigate={~p"/games/#{game.id}"}
              class="flex items-center justify-between gap-3 hover:bg-base-200 rounded-md px-2 -mx-2 py-1"
            >
              <div class="min-w-0">
                <div class="font-medium truncate">
                  {team_name(game)} vs {game.opponent_name}
                </div>
                <div class="text-sm text-base-content/70 tabular-nums">
                  {format_started_at(game.started_at)} · {status_label(game.status)}
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
      </section>

      <section :if={@active_tab == :rulesets} class="mt-4" aria-labelledby="tab-rulesets">
        <div :if={length(@teams) > 1} class="flex items-center gap-2 mb-3">
          <label for="ruleset-team-select" class="text-sm text-base-content/70">Team</label>
          <form phx-change="select_ruleset_team">
            <select
              id="ruleset-team-select"
              name="team_id"
              class="select select-sm select-bordered"
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
            <div class="min-w-0 flex-1">
              <.link
                navigate={~p"/rulesets/#{r.id}"}
                class="font-medium text-base hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              >
                {r.name}
              </.link>
              <div class="text-sm text-base-content/70 tabular-nums">
                {team_label(r)}
              </div>
            </div>
            <div class="flex items-center gap-3 shrink-0">
              <.link navigate={~p"/rulesets/#{r.id}/edit"} class="link link-hover">
                Edit
              </.link>
              <.link
                phx-click={JS.push("delete_or_archive_ruleset", value: %{id: r.id})}
                data-confirm={"Delete the \"#{r.name}\" ruleset?"}
                class="link link-hover text-error"
              >
                Delete
              </.link>
            </div>
          </li>
        </ul>

        <p :if={@rulesets == []} class="mt-4 text-base-content/70">
          No rulesets yet. Save one as a reusable template for future games.
        </p>
      </section>
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

  def handle_event("delete_or_archive_ruleset", %{"id" => id}, socket) do
    ruleset = Games.get_ruleset!(id)

    flash_msg =
      case Games.delete_ruleset(ruleset) do
        {:ok, _} ->
          "Ruleset deleted"

        {:error, :referenced_by_games} ->
          {:ok, _} = Games.archive_ruleset(ruleset)
          "Ruleset has games attached, archived instead"
      end

    {:noreply,
     socket
     |> put_flash(:info, flash_msg)
     |> assign(:rulesets, Games.list_rulesets_across_teams())}
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
      "min-h-11 inline-flex items-center px-4 py-1.5 rounded text-sm font-medium bg-primary text-primary-content"

  defp tab_classes(false),
    do:
      "min-h-11 inline-flex items-center px-4 py-1.5 rounded text-sm font-medium text-base-content/70 hover:text-base-content"
end
