defmodule Ultistats.TeamsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ultistats.Teams` context.
  """

  alias Ultistats.{Accounts, Teams}

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
  Generates a team membership. Auto-creates a team and a stub user if
  not given. Defaults: `role: :member`, `is_player: true`,
  `jersey_number: "7"`.

  Accepts profile fields (`:first_name`, `:last_name`, `:gender_role`,
  `:position`) which are forwarded to the stub user; if `:user_id` is
  given those are ignored.

  The returned membership comes back with `:user` preloaded.
  """
  def team_membership_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    attrs = expand_name_compat(attrs)

    {team_id, attrs} = Map.pop_lazy(attrs, :team_id, fn -> team_fixture().id end)

    {user_id, attrs} =
      Map.pop_lazy(attrs, :user_id, fn ->
        {:ok, user} =
          Accounts.create_stub_user(%{
            first_name: Map.get(attrs, :first_name, "Some"),
            last_name: Map.get(attrs, :last_name, "Player"),
            gender_role: Map.get(attrs, :gender_role, :female_matching),
            position: Map.get(attrs, :position, :cutter)
          })

        user.id
      end)

    membership_attrs =
      attrs
      |> Map.drop([:first_name, :last_name, :gender_role, :position])
      |> Enum.into(%{
        role: :member,
        is_player: true,
        jersey_number: "7"
      })
      |> Map.put(:team_id, team_id)
      |> Map.put(:user_id, user_id)

    {:ok, membership} =
      %Ultistats.Teams.TeamMembership{}
      |> Ultistats.Teams.TeamMembership.changeset(membership_attrs)
      |> Ultistats.Repo.insert()

    Ultistats.Repo.preload(membership, :user)
  end

  @doc """
  Convenience wrapper around `team_membership_fixture/1` that returns
  the underlying user — handy for tests that previously called
  `player_fixture/1` and worked with the player struct directly. The
  user has the same `id` that callers used to use as `player_id`, and
  carries the profile fields (first_name, last_name, gender_role,
  position).
  """
  def member_fixture(attrs \\ %{}) do
    membership = team_membership_fixture(attrs)
    membership.user
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
  not given. Accepts an optional `:user_ids` list — users must
  hold a membership on the same team or they'll be silently dropped
  (defensive cross-team filter in the context).
  """
  def line_preset_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    attrs =
      Map.put_new_lazy(attrs, :team_id, fn -> team_fixture().id end)

    attrs = Map.put_new(attrs, :name, "some name")

    {:ok, line_preset} = Teams.create_line_preset(attrs)

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
        line_size: 7,
        gender_ratio_rule: :endzone,
        default_starting_ratio: :four_men_three_women
      })
      |> Ultistats.Games.create_ruleset()

    ruleset
  end
end
