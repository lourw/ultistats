defmodule UltistatsWeb.RulesetLive.Index do
  use UltistatsWeb, :live_view

  import Ecto.Query, only: [where: 3, preload: 2]

  alias Ultistats.Games
  alias Ultistats.Games.Ruleset
  alias Ultistats.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Rulesets across all teams
        <:subtitle>Reusable rule templates: caps, halftime, timeouts, gender ratio.</:subtitle>
      </.header>

      <p :if={@rows == []} class="mt-4 text-base-content/70">
        No rulesets yet. Open a team and add one from the Rulesets tab.
      </p>

      <ul :if={@rows != []} id="rulesets-list" class="mt-4 divide-y divide-base-300">
        <li
          :for={%{ruleset: r, team: team} <- @rows}
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
              {team.name} · {summary_line(r)}
            </div>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <.link navigate={~p"/rulesets/#{r.id}/edit"} class="link link-hover">
              Edit
            </.link>
            <.link
              phx-click={JS.push("delete_or_archive", value: %{id: r.id})}
              data-confirm={"Delete the \"#{r.name}\" ruleset?"}
              class="link link-hover text-error"
            >
              Delete
            </.link>
          </div>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Rulesets")
     |> assign(:rows, list_rows())}
  end

  @impl true
  def handle_event("delete_or_archive", %{"id" => id}, socket) do
    ruleset = Games.get_ruleset!(id)

    {flash_kind, flash_msg} =
      case Games.delete_ruleset(ruleset) do
        {:ok, _} ->
          {:info, "Ruleset deleted"}

        {:error, :referenced_by_games} ->
          {:ok, _} = Games.archive_ruleset(ruleset)
          {:info, "Ruleset has games attached, archived instead"}
      end

    {:noreply,
     socket
     |> put_flash(flash_kind, flash_msg)
     |> assign(:rows, list_rows())}
  end

  # Templates only, with team preloaded; ordered by team name then ruleset name.
  defp list_rows do
    Ruleset
    |> where([r], r.kind == :template and is_nil(r.archived_at))
    |> preload(:team)
    |> Repo.all()
    |> Enum.map(fn r -> %{ruleset: r, team: r.team} end)
    |> Enum.sort_by(fn %{team: t, ruleset: r} -> {t.name, r.name} end)
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

  defp value_or_dash(nil), do: "—"
  defp value_or_dash(n) when is_integer(n), do: Integer.to_string(n)

  defp minutes(nil), do: "—"
  defp minutes(n) when is_integer(n), do: "#{n}m"
end
