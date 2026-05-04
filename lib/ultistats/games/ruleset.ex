defmodule Ultistats.Games.Ruleset do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:template, :game_instance]
  @gender_ratio_rules [:endzone, :alternating, :fixed, :none]
  @divisions [:open, :womens, :mixed]

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
    field :line_size, :integer
    field :gender_ratio_rule, Ecto.Enum, values: @gender_ratio_rules
    field :starting_male_count, :integer
    field :starting_female_count, :integer
    field :division, Ecto.Enum, values: @divisions, default: :open

    belongs_to :team, Ultistats.Teams.Team

    timestamps(type: :utc_datetime)
  end

  @doc "Valid `:kind` enum values."
  def kinds, do: @kinds

  @doc "Valid `:gender_ratio_rule` enum values."
  def gender_ratio_rules, do: @gender_ratio_rules

  @doc "Valid `:division` enum values."
  def divisions, do: @divisions

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
      :line_size,
      :gender_ratio_rule,
      :starting_male_count,
      :starting_female_count,
      :division
    ])
    |> validate_required([
      :kind,
      :timeouts_per_half,
      :line_size,
      :gender_ratio_rule,
      :division
    ])
    |> validate_name_for_kind()
    |> validate_number(:score_cap, greater_than_or_equal_to: 1, less_than_or_equal_to: 30)
    |> validate_number(:timeouts_per_half, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> validate_number(:line_size, greater_than_or_equal_to: 1, less_than_or_equal_to: 15)
    |> validate_number(:halftime_cap_minutes,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 240
    )
    |> validate_number(:halftime_target, greater_than_or_equal_to: 1)
    |> validate_number(:soft_cap_minutes, greater_than_or_equal_to: 1)
    |> validate_number(:hard_cap_minutes, greater_than_or_equal_to: 1)
    |> validate_number(:starting_male_count,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 15
    )
    |> validate_number(:starting_female_count,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 15
    )
    |> validate_starting_counts_for_rule()
    |> validate_halftime_target_within_cap()
    |> validate_has_end_condition()
    |> maybe_assoc_constraint_team()
  end

  defp maybe_assoc_constraint_team(changeset) do
    if get_field(changeset, :team_id) do
      assoc_constraint(changeset, :team)
    else
      changeset
    end
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

  # When the gender-ratio rule is `:none`, both starting counts stay
  # unrestricted. Otherwise both are required and must sum to `:line_size`.
  # If `:line_size` is missing/invalid, skip the sum check so the
  # `validate_required` / `validate_number` errors on it surface alone.
  defp validate_starting_counts_for_rule(changeset) do
    case get_field(changeset, :gender_ratio_rule) do
      :none ->
        changeset

      rule when rule in [:endzone, :alternating, :fixed] ->
        changeset
        |> require_starting_counts()
        |> validate_starting_counts_sum()

      _ ->
        changeset
    end
  end

  defp require_starting_counts(changeset) do
    changeset
    |> require_count(:starting_male_count)
    |> require_count(:starting_female_count)
  end

  defp require_count(changeset, field) do
    if is_nil(get_field(changeset, field)) do
      add_error(changeset, field, "can't be blank")
    else
      changeset
    end
  end

  defp validate_starting_counts_sum(changeset) do
    m = get_field(changeset, :starting_male_count)
    f = get_field(changeset, :starting_female_count)
    line_size = get_field(changeset, :line_size)

    cond do
      not is_integer(m) or not is_integer(f) ->
        changeset

      not is_integer(line_size) ->
        changeset

      m + f == line_size ->
        changeset

      true ->
        add_error(
          changeset,
          :starting_male_count,
          "male + female must equal line_size (#{line_size})"
        )
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
