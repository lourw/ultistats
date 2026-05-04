defmodule UltistatsWeb.TeamJoinHTML do
  @moduledoc """
  Templates for the public team-join flow rendered by
  `UltistatsWeb.TeamJoinController`.
  """
  use UltistatsWeb, :html

  import UltistatsWeb.UIComponents, only: [gender_radio: 1, position_radio: 1]

  alias Ultistats.Accounts.User
  alias Ultistats.Teams

  embed_templates "team_join_html/*"

  def pluralize_players(1), do: "player"
  def pluralize_players(_), do: "players"

  attr :team, :map, required: true
  attr :team_stats, :map, required: true

  def joining_card(assigns) do
    ~H"""
    <div class="rounded-lg border-2 border-base-300 bg-base-100 px-4 py-3">
      <p class="text-xs uppercase tracking-wide text-base-content/60">Joining</p>
      <p class="text-base font-semibold text-base-content">{@team.name}</p>
      <p
        :if={@team_stats.total_players > 0}
        class="mt-1 text-sm text-base-content/70 tabular-nums"
      >
        {@team_stats.total_players} {pluralize_players(@team_stats.total_players)}
        <span class="text-base-content/40">·</span>
        {@team_stats.male_matching}M / {@team_stats.female_matching}F
      </p>
    </div>
    """
  end
end
