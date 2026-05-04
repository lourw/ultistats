defmodule Ultistats.Release.SystemRulesets do
  @moduledoc """
  Canonical attribute lists for the global (system) rulesets seeded by
  `Ultistats.Release.seed_system_rulesets/0` and `priv/repo/seeds.exs`.

  System rulesets carry `team_id: nil` and are visible to every user
  alongside their team-owned rulesets.
  """

  @doc "Attrs for every system ruleset, in seed order."
  def all do
    [
      %{
        name: "USAU Open",
        kind: :template,
        division: :open,
        score_cap: 15,
        halftime_target: 8,
        soft_cap_minutes: 75,
        hard_cap_minutes: 90,
        timeouts_per_half: 2,
        line_size: 7,
        gender_ratio_rule: :none
      },
      %{
        name: "USAU Women's",
        kind: :template,
        division: :womens,
        score_cap: 15,
        halftime_target: 8,
        soft_cap_minutes: 75,
        hard_cap_minutes: 90,
        timeouts_per_half: 2,
        line_size: 7,
        gender_ratio_rule: :none
      },
      %{
        name: "USAU Mixed",
        kind: :template,
        division: :mixed,
        score_cap: 15,
        halftime_target: 8,
        soft_cap_minutes: 75,
        hard_cap_minutes: 90,
        timeouts_per_half: 2,
        line_size: 7,
        gender_ratio_rule: :endzone,
        starting_male_count: 4,
        starting_female_count: 3
      }
    ]
  end
end
