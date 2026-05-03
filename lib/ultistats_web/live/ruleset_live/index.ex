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

      <ul :if={@rows != []} id="rulesets-list" class="mt-4 pb-24 divide-y divide-base-300">
        <li
          :for={%{ruleset: r, team: team} <- @rows}
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
                {team.name} · {summary_line(r)}
              </div>
            </div>
          </div>
          <.link
            :if={MapSet.member?(@admin_team_ids, r.team_id)}
            navigate={~p"/rulesets/#{r.id}/edit"}
            aria-label={"Edit #{r.name}"}
            class="shrink-0 min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-pencil-square" class="size-5" />
          </.link>
        </li>
      </ul>

      <p :if={@rows == []} class="mt-4 text-base-content/70">
        No rulesets yet. Open a team and add one from the Rulesets tab.
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    rows =
      user
      |> Games.list_rulesets_for_user()
      |> Enum.map(fn r -> %{ruleset: r, team: r.team} end)
      |> Enum.sort_by(fn %{team: t, ruleset: r} -> {t.name, r.name} end)

    admin_team_ids =
      user
      |> Teams.list_teams_for_user()
      |> Enum.filter(&Teams.user_admin_of?(user, &1))
      |> MapSet.new(& &1.id)

    {:ok,
     socket
     |> assign(:page_title, "Rulesets")
     |> assign(:rows, rows)
     |> assign(:admin_team_ids, admin_team_ids)}
  end

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
