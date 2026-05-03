defmodule UltistatsWeb.RulesetLive.Show do
  use UltistatsWeb, :live_view

  alias Ultistats.{Games, Teams}
  alias Ultistats.Games.Ruleset

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Ruleset {humanized_name(@ruleset)}
        <:subtitle>{kind_subtitle(@ruleset)}</:subtitle>
        <:actions>
          <.button navigate={~p"/games"} aria-label="Back to games">
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            :if={@is_admin?}
            variant="primary"
            navigate={~p"/rulesets/#{@ruleset}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit ruleset
          </.button>
          <.button
            :if={@is_admin?}
            phx-click={JS.push("delete_or_archive")}
            data-confirm={"Delete the \"#{humanized_name(@ruleset)}\" ruleset?"}
            class="btn-error"
          >
            <.icon name="hero-trash" /> Delete
          </.button>
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
        <:item title="Timeouts per half">{@ruleset.timeouts_per_half}</:item>
        <:item title="Gender ratio rule">
          {gender_ratio_label(@ruleset.gender_ratio_rule)}
        </:item>
        <:item :if={@ruleset.gender_ratio_rule != :none} title="Default starting ratio">
          {starting_ratio_label(@ruleset.default_starting_ratio)}
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

  defp humanized_name(%Ruleset{name: nil, kind: :game_instance}), do: "(per-game instance)"
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

  defp starting_ratio_label(:four_men_three_women), do: "4M / 3F"
  defp starting_ratio_label(:three_men_four_women), do: "3M / 4F"
  defp starting_ratio_label(nil), do: "—"
  defp starting_ratio_label(other), do: to_string(other)
end
