defmodule Ultistats.GamesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ultistats.Games` context.
  """

  import Ultistats.TeamsFixtures

  alias Ultistats.Games
  alias Ultistats.Games.{Event, Point}
  alias Ultistats.Repo

  @doc """
  Generate a game. Creates a team automatically if `team_id` is not
  given.
  """
  def game_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    attrs =
      Map.put_new_lazy(attrs, :team_id, fn -> team_fixture().id end)

    {:ok, game} =
      attrs
      |> Enum.into(%{
        opponent_name: "Some Opponent",
        format: :usau_standard,
        status: :in_progress,
        started_at: ~U[2026-05-02 02:10:00Z],
        first_pull: :ours
      })
      |> Games.create_game()

    game
  end

  @doc """
  Generate a point. Creates a game (and team) automatically if
  `game_id` is not given. Accepts a `:user_ids` list (defaults to
  `[]`); since `start_point/2` filters cross-team ids defensively, we
  use direct insert here for fixture-level control.
  """
  def point_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    attrs = Map.put_new_lazy(attrs, :game_id, fn -> game_fixture().id end)
    user_ids = Map.get(attrs, :user_ids, [])

    sequence =
      Map.get_lazy(attrs, :sequence, fn ->
        Games.next_point_sequence(%Games.Game{id: attrs.game_id})
      end)

    snapshot =
      Map.get(attrs, :our_line_snapshot, %{"user_ids" => user_ids})

    point_attrs = %{
      game_id: attrs.game_id,
      sequence: sequence,
      our_line_snapshot: snapshot,
      scoring_team: Map.get(attrs, :scoring_team)
    }

    {:ok, point} =
      %Point{}
      |> Point.changeset(point_attrs)
      |> Repo.insert()

    point
  end

  @doc """
  Generate an event. Creates a point (and game and team) if
  `point_id` is not given.
  """
  def event_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    attrs = Map.put_new_lazy(attrs, :point_id, fn -> point_fixture().id end)

    sequence =
      Map.get_lazy(attrs, :sequence, fn ->
        Games.next_event_sequence(%Point{id: attrs.point_id})
      end)

    event_attrs = %{
      point_id: attrs.point_id,
      sequence: sequence,
      type: Map.get(attrs, :type, :goal),
      passer_user_id: Map.get(attrs, :passer_user_id),
      receiver_user_id: Map.get(attrs, :receiver_user_id),
      occurred_at: Map.get(attrs, :occurred_at, ~U[2026-05-02 02:11:00Z]),
      deleted_at: Map.get(attrs, :deleted_at)
    }

    {:ok, event} =
      %Event{}
      |> Event.changeset(event_attrs)
      |> Repo.insert()

    event
  end
end
