defmodule Ultistats.TeamsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ultistats.Teams` context.
  """

  @doc """
  Generate a team.
  """
  def team_fixture(attrs \\ %{}) do
    {:ok, team} =
      attrs
      |> Enum.into(%{
        name: "some name"
      })
      |> Ultistats.Teams.create_team()

    team
  end

  @doc """
  Generate a player. Creates a team automatically if `team_id` is not
  given.

  Accepts `:name` for backwards compatibility with old call sites — it
  is split on the first space into `:first_name` / `:last_name`. The
  preferred form is to pass `:first_name` / `:last_name` directly.
  """
  def player_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    attrs = Map.put_new_lazy(attrs, :team_id, fn -> team_fixture().id end)
    attrs = expand_name_compat(attrs)

    {:ok, player} =
      attrs
      |> Enum.into(%{
        gender_role: :female_matching,
        position: :cutter,
        jersey_number: "7",
        first_name: "Some",
        last_name: "Player"
      })
      |> Ultistats.Teams.create_player()

    player
  end

  defp expand_name_compat(%{name: name} = attrs) when is_binary(name) do
    {first, last} =
      case String.split(name, " ", parts: 2) do
        [f, l] -> {f, l}
        [f] -> {f, "—"}
      end

    attrs
    |> Map.delete(:name)
    |> Map.put_new(:first_name, first)
    |> Map.put_new(:last_name, last)
  end

  defp expand_name_compat(attrs), do: attrs

  @doc """
  Generate a line_preset. Creates a team automatically if `team_id` is
  not given. Accepts an optional `:player_ids` list — players must
  belong to the same team or they'll be silently dropped (defensive
  cross-team filter in the context).
  """
  def line_preset_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    attrs =
      Map.put_new_lazy(attrs, :team_id, fn -> team_fixture().id end)

    attrs = Map.put_new(attrs, :name, "some name")

    {:ok, line_preset} = Ultistats.Teams.create_line_preset(attrs)

    line_preset
  end

  @doc """
  Generate a ruleset. Creates a team automatically if `team_id` is not
  given. Defaults to a `:template` row with USAU-standard values.
  """
  def ruleset_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    attrs = Map.put_new_lazy(attrs, :team_id, fn -> team_fixture().id end)

    {:ok, ruleset} =
      attrs
      |> Enum.into(%{
        kind: :template,
        name: "Standard",
        score_cap: 15,
        halftime_target: 8,
        halftime_cap_minutes: nil,
        soft_cap_minutes: nil,
        hard_cap_minutes: nil,
        timeouts_per_half: 2,
        gender_ratio_rule: :endzone,
        default_starting_ratio: :four_men_three_women
      })
      |> Ultistats.Games.create_ruleset()

    ruleset
  end
end
