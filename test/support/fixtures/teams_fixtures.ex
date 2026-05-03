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
  Generate a player. Creates a team automatically if `team_id` is not given.
  """
  def player_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    attrs =
      Map.put_new_lazy(attrs, :team_id, fn -> team_fixture().id end)

    {:ok, player} =
      attrs
      |> Enum.into(%{
        gender_role: :female_matching,
        jersey_number: "7",
        name: "some name"
      })
      |> Ultistats.Teams.create_player()

    player
  end
end
