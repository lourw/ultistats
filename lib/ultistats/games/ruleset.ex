defmodule Ultistats.Games.Ruleset do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:template, :game_instance]
  @gender_ratio_rules [:endzone, :alternating, :fixed, :none]
  @starting_ratios [:four_men_three_women, :three_men_four_women]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "rulesets" do
    field :name, :string
    field :kind, Ecto.Enum, values: @kinds
    field :archived_at, :utc_datetime

    field :score_cap, :integer
    field :halftime_target, :integer
    field :halftime_cap_minutes, :integer
    field :soft_cap_minutes, :integer
    field :hard_cap_minutes, :integer
    field :timeouts_per_half, :integer
    field :gender_ratio_rule, Ecto.Enum, values: @gender_ratio_rules
    field :default_starting_ratio, Ecto.Enum, values: @starting_ratios

    belongs_to :team, Ultistats.Teams.Team

    timestamps(type: :utc_datetime)
  end

  @doc "Valid `:kind` enum values."
  def kinds, do: @kinds

  @doc "Valid `:gender_ratio_rule` enum values."
  def gender_ratio_rules, do: @gender_ratio_rules

  @doc "Valid `:default_starting_ratio` enum values."
  def starting_ratios, do: @starting_ratios

  @doc """
  Base changeset.

  Required fields differ by `:kind`:

    * `:template` rows must carry a `:name` (visible in the team's
      Ruleset library).
    * `:game_instance` rows are anonymous clones owned by exactly one
      game; `:name` is left nil.

  Numeric ranges:

    * `score_cap` 1..30 when present
    * `timeouts_per_half` 0..5
    * `halftime_cap_minutes` 1..240 when present
    * `halftime_target <= score_cap` when both present

  At least one of `score_cap` or `hard_cap_minutes` must be non-nil —
  without either the game has no end condition.
  """
  def changeset(ruleset, attrs) do
    ruleset
    |> cast(attrs, [
      :team_id,
      :name,
      :kind,
      :archived_at,
      :score_cap,
      :halftime_target,
      :halftime_cap_minutes,
      :soft_cap_minutes,
      :hard_cap_minutes,
      :timeouts_per_half,
      :gender_ratio_rule,
      :default_starting_ratio
    ])
    |> validate_required([:team_id, :kind, :timeouts_per_half, :gender_ratio_rule])
    |> validate_name_for_kind()
    |> validate_number(:score_cap, greater_than_or_equal_to: 1, less_than_or_equal_to: 30)
    |> validate_number(:timeouts_per_half, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> validate_number(:halftime_cap_minutes,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 240
    )
    |> validate_number(:halftime_target, greater_than_or_equal_to: 1)
    |> validate_number(:soft_cap_minutes, greater_than_or_equal_to: 1)
    |> validate_number(:hard_cap_minutes, greater_than_or_equal_to: 1)
    |> validate_halftime_target_within_cap()
    |> validate_has_end_condition()
    |> assoc_constraint(:team)
  end

  defp validate_name_for_kind(changeset) do
    case get_field(changeset, :kind) do
      :template -> validate_required(changeset, [:name])
      _ -> changeset
    end
  end

  defp validate_halftime_target_within_cap(changeset) do
    cap = get_field(changeset, :score_cap)
    target = get_field(changeset, :halftime_target)

    if is_integer(cap) and is_integer(target) and target > cap do
      add_error(
        changeset,
        :halftime_target,
        "must be less than or equal to score_cap"
      )
    else
      changeset
    end
  end

  defp validate_has_end_condition(changeset) do
    score_cap = get_field(changeset, :score_cap)
    hard_cap = get_field(changeset, :hard_cap_minutes)

    if is_nil(score_cap) and is_nil(hard_cap) do
      add_error(
        changeset,
        :score_cap,
        "at least one of score_cap or hard_cap_minutes must be set"
      )
    else
      changeset
    end
  end
end
