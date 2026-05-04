defmodule UltistatsWeb.RulesetLive.Index do
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Teams}
  alias Ultistats.Games.Ruleset

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Rulesets across all teams
        <:subtitle>Reusable rule templates: caps, halftime, timeouts, gender ratio.</:subtitle>
      </.header>

      <form
        :if={@all_rows != []}
        phx-change="apply_filters"
        class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-end sm:gap-3"
      >
        <div class="flex-1 min-w-0">
          <label for="division-filter" class="block text-sm font-medium text-base-content">
            Division
          </label>
          <select
            id="division-filter"
            name="division"
            class="block w-full rounded-md border border-base-300 bg-base-100 px-3 py-2 text-base-content min-h-11 focus:outline-2 focus:outline-offset-2 focus:outline-primary"
          >
            <option value="" selected={@division_filter == :all}>All divisions</option>
            <option value="open" selected={@division_filter == :open}>Open</option>
            <option value="womens" selected={@division_filter == :womens}>Women's</option>
            <option value="mixed" selected={@division_filter == :mixed}>Mixed</option>
          </select>
        </div>

        <div class="flex-1 min-w-0">
          <label for="team-filter" class="block text-sm font-medium text-base-content">
            Team
          </label>
          <select
            id="team-filter"
            name="team"
            class="block w-full rounded-md border border-base-300 bg-base-100 px-3 py-2 text-base-content min-h-11 focus:outline-2 focus:outline-offset-2 focus:outline-primary"
          >
            <option value="" selected={@team_filter == :all}>All teams</option>
            <option value="system" selected={@team_filter == :system}>System</option>
            <option
              :for={t <- @user_teams}
              value={t.id}
              selected={@team_filter == t.id}
            >
              {t.name}
            </option>
          </select>
        </div>
      </form>

      <ul
        :if={@rows != []}
        id="rulesets-list"
        class="-mx-4 mt-4 pb-24 border-y border-base-200 divide-y divide-base-200"
      >
        <li
          :for={%{ruleset: r, team_label: team_label} <- @rows}
          id={"ruleset-#{r.id}"}
          class="min-h-9 flex items-center gap-2 px-4 py-0.5"
        >
          <span class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0">
            {score_cap_badge(r.score_cap)}
          </span>
          <div class="flex-1 min-w-0">
            <div class="font-medium text-sm truncate leading-tight">{r.name}</div>
            <div class="text-[11px] text-base-content/60 truncate leading-tight">
              {team_label} · {summary_line(r)}
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

      <p :if={@all_rows == []} class="mt-4 text-base-content/70">
        No rulesets yet. Open a team and add one from the Rulesets tab.
      </p>

      <p :if={@all_rows != [] and @rows == []} class="mt-4 text-base-content/70">
        No rulesets match those filters.
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    all_rows =
      user
      |> Games.list_rulesets_for_user()
      |> Enum.map(fn r ->
        %{
          ruleset: r,
          team_label: team_label_for(r)
        }
      end)
      |> Enum.sort_by(fn %{team_label: label, ruleset: r} -> {label, r.name} end)

    user_teams =
      user
      |> Teams.list_teams_for_user()
      |> Enum.sort_by(& &1.name)

    admin_team_ids =
      user_teams
      |> Enum.filter(&Teams.user_admin_of?(user, &1))
      |> MapSet.new(& &1.id)

    {:ok,
     socket
     |> assign(:page_title, "Rulesets")
     |> assign(:all_rows, all_rows)
     |> assign(:user_teams, user_teams)
     |> assign(:admin_team_ids, admin_team_ids)
     |> assign(:division_filter, :all)
     |> assign(:team_filter, :all)
     |> assign_filtered_rows()}
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    division = parse_division(params["division"])
    team = parse_team(params["team"])

    {:noreply,
     socket
     |> assign(:division_filter, division)
     |> assign(:team_filter, team)
     |> assign_filtered_rows()}
  end

  defp parse_division("open"), do: :open
  defp parse_division("womens"), do: :womens
  defp parse_division("mixed"), do: :mixed
  defp parse_division(_), do: :all

  defp parse_team(nil), do: :all
  defp parse_team(""), do: :all
  defp parse_team("system"), do: :system
  defp parse_team(id) when is_binary(id), do: id

  defp assign_filtered_rows(socket) do
    %{
      all_rows: all_rows,
      division_filter: division,
      team_filter: team
    } = socket.assigns

    rows =
      all_rows
      |> filter_by_division(division)
      |> filter_by_team(team)

    assign(socket, :rows, rows)
  end

  defp filter_by_division(rows, :all), do: rows

  defp filter_by_division(rows, division) when division in [:open, :womens, :mixed] do
    Enum.filter(rows, fn %{ruleset: r} -> r.division == division end)
  end

  defp filter_by_team(rows, :all), do: rows

  defp filter_by_team(rows, :system) do
    Enum.filter(rows, fn %{ruleset: r} -> is_nil(r.team_id) end)
  end

  defp filter_by_team(rows, team_id) when is_binary(team_id) do
    Enum.filter(rows, fn %{ruleset: r} -> r.team_id == team_id end)
  end

  defp team_label_for(%Ruleset{team_id: nil}), do: "System"

  defp team_label_for(%Ruleset{team: %{name: name}}) when is_binary(name), do: name

  defp team_label_for(_), do: "—"

  defp summary_line(%Ruleset{} = r) do
    [
      "to #{value_or_dash(r.score_cap)}",
      "half #{value_or_dash(r.halftime_target)}",
      "soft #{minutes(r.soft_cap_minutes)}",
      "hard #{minutes(r.hard_cap_minutes)}"
    ]
    |> Enum.join(" · ")
  end

  defp score_cap_badge(nil), do: "—"
  defp score_cap_badge(n) when is_integer(n), do: Integer.to_string(n)

  defp value_or_dash(nil), do: "—"
  defp value_or_dash(n) when is_integer(n), do: Integer.to_string(n)

  defp minutes(nil), do: "—"
  defp minutes(n) when is_integer(n), do: "#{n}m"
end
