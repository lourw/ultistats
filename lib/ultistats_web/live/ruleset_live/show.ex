defmodule UltistatsWeb.RulesetLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Teams}
  alias Ultistats.Games.Ruleset

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        <span class="inline-flex items-center gap-3">
          <.link
            navigate={~p"/games"}
            aria-label="Back to games"
            class="min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <span class="truncate">{humanized_name(@ruleset)}</span>
          <.link
            :if={@is_admin?}
            navigate={~p"/rulesets/#{@ruleset}/edit?return_to=show"}
            aria-label="Edit ruleset"
            class="shrink-0 min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 hover:text-base-content active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <.icon name="hero-pencil-square" class="size-4" />
          </.link>
        </span>
        <:subtitle>{kind_subtitle(@ruleset)}</:subtitle>
        <:actions>
          <button
            :if={@is_admin?}
            type="button"
            phx-click={JS.push("delete_or_archive")}
            data-confirm={"Delete the \"#{humanized_name(@ruleset)}\" ruleset?"}
            aria-label="Delete ruleset"
            class="shrink-0 min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-error hover:bg-error/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-error"
          >
            <.icon name="hero-trash" class="size-5" />
          </button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{humanized_name(@ruleset)}</:item>
        <:item title="Score cap">{score_cap_label(@ruleset.score_cap)}</:item>
        <:item title="Halftime target">{halftime_target_label(@ruleset.halftime_target)}</:item>
        <:item title="Halftime cap">
          {minutes_label(@ruleset.halftime_cap_minutes)}
        </:item>
        <:item title="Soft cap">{minutes_label(@ruleset.soft_cap_minutes)}</:item>
        <:item title="Hard cap">{minutes_label(@ruleset.hard_cap_minutes)}</:item>
        <:item title="Line size">{@ruleset.line_size}</:item>
        <:item title="Timeouts per half">{@ruleset.timeouts_per_half}</:item>
        <:item title="Gender ratio rule">
          {gender_ratio_label(@ruleset.gender_ratio_rule)}
        </:item>
        <:item :if={@ruleset.gender_ratio_rule != :none} title="Starting ratio">
          {starting_counts_label(@ruleset)}
        </:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    ruleset = Games.get_ruleset!(id)
    user = socket.assigns.current_scope.user

    if Teams.user_member_of?(user, ruleset.team_id) do
      {:ok,
       socket
       |> assign(:page_title, "Show Ruleset")
       |> assign(:ruleset, ruleset)
       |> assign(:is_admin?, Teams.user_admin_of?(user, ruleset.team_id))}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to view that ruleset.")
       |> push_navigate(to: ~p"/games")}
    end
  end

  @impl true
  def handle_event("delete_or_archive", _params, socket) do
    ruleset = socket.assigns.ruleset
    user = socket.assigns.current_scope.user

    if not Teams.user_admin_of?(user, ruleset.team_id) do
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    else
      flash_msg =
        case Games.delete_ruleset(ruleset) do
          {:ok, _} ->
            "Ruleset deleted"

          {:error, :referenced_by_games} ->
            {:ok, _} = Games.archive_ruleset(ruleset)
            "Archived because games reference it."
        end

      {:noreply,
       socket
       |> put_flash(:info, flash_msg)
       |> push_navigate(to: ~p"/games")}
    end
  end

  defp humanized_name(%Ruleset{name: nil, kind: :game_instance}), do: "Game ruleset"
  defp humanized_name(%Ruleset{name: name}) when is_binary(name), do: name
  defp humanized_name(_), do: "Ruleset"

  defp kind_subtitle(%Ruleset{kind: :template, archived_at: nil}),
    do: "Reusable team template."

  defp kind_subtitle(%Ruleset{kind: :template, archived_at: %DateTime{}}),
    do: "Archived template — kept for historical games."

  defp kind_subtitle(%Ruleset{kind: :game_instance}),
    do: "Snapshot owned by a single game (not shown in the team library)."

  defp kind_subtitle(_), do: ""

  defp score_cap_label(nil), do: "— (no score cap)"
  defp score_cap_label(n) when is_integer(n), do: "#{n}"

  defp halftime_target_label(nil), do: "— (no halftime by score)"
  defp halftime_target_label(n) when is_integer(n), do: "#{n}"

  defp minutes_label(nil), do: "— (none)"
  defp minutes_label(n) when is_integer(n), do: "#{n} min"

  defp gender_ratio_label(:endzone), do: "Endzone (USAU genzone)"
  defp gender_ratio_label(:alternating), do: "Alternating (ABBA)"
  defp gender_ratio_label(:fixed), do: "Fixed"
  defp gender_ratio_label(:none), do: "None"
  defp gender_ratio_label(other), do: to_string(other)

  defp starting_counts_label(%Ruleset{starting_male_count: m, starting_female_count: f})
       when is_integer(m) and is_integer(f),
       do: "#{m}M / #{f}F"

  defp starting_counts_label(_), do: "—"
end
