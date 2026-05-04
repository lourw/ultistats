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

      <div :if={length(@rows) > 1} class="flex flex-col gap-1 mt-4 mb-3">
        <span
          id="rulesets-division-filter-label"
          class="text-[11px] uppercase tracking-wide text-base-content/60"
        >
          Division
        </span>
        <div
          role="radiogroup"
          aria-labelledby="rulesets-division-filter-label"
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
        :if={@rows != []}
        id="rulesets-list"
        class="mt-4 pb-24 rounded-md border border-base-200 divide-y divide-base-200 overflow-hidden"
      >
        <li
          :for={%{ruleset: r} <- visible_rows(@rows, @division_filter)}
          id={"ruleset-#{r.id}"}
          class="min-h-10 flex items-center gap-2 px-3 py-0.5"
        >
          <span class="tabular-nums font-semibold inline-flex items-center justify-center size-6 rounded-full bg-base-200 text-base-content text-[11px] shrink-0">
            {score_cap_badge(r.score_cap)}
          </span>
          <div class="flex-1 min-w-0">
            <div class="font-medium text-sm truncate leading-tight">{r.name}</div>
            <div class="text-[11px] text-base-content/60 truncate leading-tight">
              {summary_line(r)}
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
      |> Enum.sort_by(fn %{ruleset: r} -> {r.name} end)

    admin_team_ids =
      user
      |> Teams.list_teams_for_user()
      |> Enum.filter(&Teams.user_admin_of?(user, &1))
      |> MapSet.new(& &1.id)

    {:ok,
     socket
     |> assign(:page_title, "Rulesets")
     |> assign(:rows, rows)
     |> assign(:division_filter, "all")
     |> assign(:admin_team_ids, admin_team_ids)}
  end

  @impl true
  def handle_event("set_division_filter", %{"division" => division}, socket)
      when division in ["all", "open", "mixed", "womens"] do
    {:noreply, assign(socket, :division_filter, division)}
  end

  defp division_filter_options do
    [{"All divisions", "all"}, {"Open", "open"}, {"Women's", "womens"}, {"Mixed", "mixed"}]
  end

  defp visible_rows(rows, "all"), do: rows

  defp visible_rows(rows, division) when division in ["open", "womens", "mixed"] do
    atom = String.to_existing_atom(division)
    Enum.filter(rows, fn %{ruleset: r} -> r.division == atom end)
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
