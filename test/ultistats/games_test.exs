defmodule Ultistats.GamesTest do
  use Ultistats.DataCase

  alias Ultistats.Games
  alias Ultistats.Games.{Event, Game, Point}
  alias Ultistats.Repo

  import Ultistats.GamesFixtures
  import Ultistats.TeamsFixtures

  describe "games CRUD" do
    @invalid_attrs %{
      status: nil,
      format: nil,
      started_at: nil,
      opponent_name: nil,
      first_pull: nil,
      team_id: nil
    }

    test "list_games_for_team/1 filters and orders by started_at desc" do
      team = team_fixture()
      other = team_fixture()
      _other_game = game_fixture(team_id: other.id)

      g1 = game_fixture(team_id: team.id, started_at: ~U[2026-04-01 12:00:00Z])
      g2 = game_fixture(team_id: team.id, started_at: ~U[2026-05-01 12:00:00Z])

      assert Games.list_games_for_team(team) |> Enum.map(& &1.id) == [g2.id, g1.id]
      assert Games.list_games_for_team(team.id) |> Enum.map(& &1.id) == [g2.id, g1.id]
    end

    test "create_game/1 with valid data creates a game" do
      team = team_fixture()

      valid_attrs = %{
        team_id: team.id,
        opponent_name: "Rivals",
        format: :usau_standard,
        status: :in_progress,
        started_at: ~U[2026-05-02 02:10:00Z],
        first_pull: :ours
      }

      assert {:ok, %Game{} = game} = Games.create_game(valid_attrs)
      assert game.opponent_name == "Rivals"
      assert game.format == :usau_standard
      assert game.status == :in_progress
      assert game.first_pull == :ours
    end

    test "create_game/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Games.create_game(@invalid_attrs)
    end

    test "create_game/1 rejects opponent_name longer than 80 chars" do
      team = team_fixture()
      long = String.duplicate("a", 81)

      assert {:error, changeset} =
               Games.create_game(%{
                 team_id: team.id,
                 opponent_name: long,
                 format: :usau_standard,
                 status: :in_progress,
                 started_at: ~U[2026-05-02 02:10:00Z],
                 first_pull: :ours
               })

      assert %{opponent_name: ["should be at most 80 character(s)"]} = errors_on(changeset)
    end

    test "update_game/2 with valid data updates the game" do
      game = game_fixture()
      assert {:ok, %Game{} = game} = Games.update_game(game, %{opponent_name: "New Name"})
      assert game.opponent_name == "New Name"
    end

    test "update_game/2 with invalid data returns error changeset" do
      game = game_fixture()
      assert {:error, %Ecto.Changeset{}} = Games.update_game(game, @invalid_attrs)
    end

    test "delete_game/1 deletes the game" do
      game = game_fixture()
      assert {:ok, %Game{}} = Games.delete_game(game)
      assert_raise Ecto.NoResultsError, fn -> Games.get_game!(game.id) end
    end
  end

  describe "start_game/1" do
    test "defaults status to :in_progress and stamps started_at" do
      team = team_fixture()
      before = DateTime.utc_now() |> DateTime.add(-1, :second)

      assert {:ok, game} =
               Games.start_game(%{
                 team_id: team.id,
                 opponent_name: "Rivals",
                 format: :usau_standard,
                 first_pull: :ours
               })

      assert game.status == :in_progress
      assert game.started_at
      assert DateTime.compare(game.started_at, before) in [:gt, :eq]
    end

    test "respects explicit started_at and status" do
      team = team_fixture()
      ts = ~U[2026-04-01 12:00:00Z]

      assert {:ok, game} =
               Games.start_game(%{
                 team_id: team.id,
                 opponent_name: "Rivals",
                 format: :usau_standard,
                 first_pull: :theirs,
                 status: :in_progress,
                 started_at: ts
               })

      assert game.started_at == ts
      assert game.first_pull == :theirs
    end

    test "missing required fields returns changeset error" do
      assert {:error, %Ecto.Changeset{}} = Games.start_game(%{})
    end
  end

  describe "rulesets integration" do
    alias Ultistats.Games.Ruleset

    test "start_game/1 with :ruleset_id (no overrides) attaches the template" do
      team = team_fixture()

      template =
        ruleset_fixture(%{
          team_id: team.id,
          name: "Hat League",
          score_cap: 13,
          halftime_target: 7
        })

      assert {:ok, game} =
               Games.start_game(%{
                 team_id: team.id,
                 opponent_name: "Rivals",
                 format: :usau_standard,
                 first_pull: :ours,
                 ruleset_id: template.id
               })

      assert game.ruleset_id == template.id
      assert Games.halftime_threshold(game) == 7
      assert Games.hard_cap_threshold(game) == 13
    end

    test "start_game/1 with :ruleset_id + overrides creates a :game_instance" do
      team = team_fixture()
      template = ruleset_fixture(%{team_id: team.id, score_cap: 15, halftime_target: 8})

      assert {:ok, game} =
               Games.start_game(%{
                 team_id: team.id,
                 opponent_name: "Rivals",
                 format: :usau_standard,
                 first_pull: :ours,
                 ruleset_id: template.id,
                 rule_overrides: %{score_cap: 11}
               })

      refute game.ruleset_id == template.id
      attached = Games.get_ruleset!(game.ruleset_id)
      assert attached.kind == :game_instance
      assert attached.team_id == team.id
      assert attached.score_cap == 11

      # Original template untouched.
      assert Games.get_ruleset!(template.id).score_cap == 15
    end

    test "start_game/1 without :ruleset_id and no overrides leaves ruleset_id nil; reads default to USAU" do
      team = team_fixture()

      assert {:ok, game} =
               Games.start_game(%{
                 team_id: team.id,
                 opponent_name: "Rivals",
                 format: :usau_standard,
                 first_pull: :ours
               })

      assert is_nil(game.ruleset_id)
      assert Games.halftime_threshold(game) == 8
      assert Games.hard_cap_threshold(game) == 15
    end

    test "start_game/1 without :ruleset_id but with overrides synthesizes a :game_instance" do
      team = team_fixture()

      assert {:ok, game} =
               Games.start_game(%{
                 team_id: team.id,
                 opponent_name: "Rivals",
                 format: :usau_standard,
                 first_pull: :ours,
                 rule_overrides: %{score_cap: 11}
               })

      assert game.ruleset_id

      attached = Games.get_ruleset!(game.ruleset_id)
      assert %Ruleset{kind: :game_instance, team_id: t} = attached
      assert t == team.id
      assert attached.score_cap == 11
      # Falls back to USAU defaults for unspecified knobs.
      assert attached.halftime_target == 8
      assert attached.timeouts_per_half == 2
    end

    test "editing the source template after game-start does not change the in-flight game's resolved values" do
      team = team_fixture()
      template = ruleset_fixture(%{team_id: team.id, score_cap: 15, halftime_target: 8})

      {:ok, game} =
        Games.start_game(%{
          team_id: team.id,
          opponent_name: "Rivals",
          format: :usau_standard,
          first_pull: :ours,
          ruleset_id: template.id
        })

      # Edit the template — clone-on-write archives the old template and
      # creates a new template row. The game should keep reading the old.
      {:ok, _new_template} = Games.update_ruleset(template, %{score_cap: 11, halftime_target: 6})

      reloaded = Games.get_game!(game.id)
      assert Games.halftime_threshold(reloaded) == 8
      assert Games.hard_cap_threshold(reloaded) == 15
    end

    test "halftime?/1 returns false when resolved halftime_target is nil" do
      team = team_fixture()

      template =
        ruleset_fixture(%{
          team_id: team.id,
          name: "No halftime",
          score_cap: 15,
          halftime_target: nil
        })

      {:ok, game} =
        Games.start_game(%{
          team_id: team.id,
          opponent_name: "Rivals",
          format: :usau_standard,
          first_pull: :ours,
          ruleset_id: template.id
        })

      player = member_fixture(team_id: team.id)
      score_n_points(game, player, :ours, 8)

      refute Games.halftime?(Games.get_game!(game.id))
    end

    test "hard_cap_reached?/1 returns false when resolved score_cap is nil" do
      team = team_fixture()

      template =
        ruleset_fixture(%{
          team_id: team.id,
          name: "Timed only",
          score_cap: nil,
          hard_cap_minutes: 60
        })

      {:ok, game} =
        Games.start_game(%{
          team_id: team.id,
          opponent_name: "Rivals",
          format: :usau_standard,
          first_pull: :ours,
          ruleset_id: template.id
        })

      player = member_fixture(team_id: team.id)
      score_n_points(game, player, :ours, 20)

      refute Games.hard_cap_reached?(Games.get_game!(game.id))
    end
  end

  describe "end_game/2" do
    test "defaults to :finished and stamps ended_at" do
      game = game_fixture()
      assert {:ok, ended} = Games.end_game(game)
      assert ended.status == :finished
      assert ended.ended_at
    end

    test "accepts :abandoned via opts" do
      game = game_fixture()
      assert {:ok, ended} = Games.end_game(game, status: :abandoned)
      assert ended.status == :abandoned
    end
  end

  describe "start_point/2" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id)
      p1 = member_fixture(team_id: team.id, jersey_number: "1")
      p2 = member_fixture(team_id: team.id, jersey_number: "2")
      %{team: team, game: game, p1: p1, p2: p2}
    end

    test "starts at sequence 1 and increments", %{game: game, p1: p1, p2: p2} do
      assert {:ok, pt1} = Games.start_point(game, [p1.id, p2.id])
      assert pt1.sequence == 1
      assert pt1.scoring_team == nil
      assert pt1.our_line_snapshot == %{"user_ids" => [p1.id, p2.id]}

      # End point 1 so it's no longer the active point.
      {:ok, _} = Games.end_point(pt1, :ours)

      assert {:ok, pt2} = Games.start_point(game, [p1.id])
      assert pt2.sequence == 2
    end

    test "filters out player ids from another team", %{game: game, p1: p1} do
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id, jersey_number: "9")

      assert {:ok, pt} = Games.start_point(game, [p1.id, stranger.id])
      assert pt.our_line_snapshot["user_ids"] == [p1.id]
    end

    test "all-foreign user_ids yields a changeset error", %{game: game} do
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id, jersey_number: "9")

      assert {:error, changeset} = Games.start_point(game, [stranger.id])
      assert %{our_line_snapshot: [_msg]} = errors_on(changeset)
    end

    test "persists snapshot as a map under string key", %{game: game, p1: p1} do
      assert {:ok, pt} = Games.start_point(game, [p1.id])
      reloaded = Repo.get!(Point, pt.id)
      assert is_map(reloaded.our_line_snapshot)
      assert reloaded.our_line_snapshot["user_ids"] == [p1.id]
    end
  end

  describe "end_point/2" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id)
      player = member_fixture(team_id: team.id)
      {:ok, point} = Games.start_point(game, [player.id])
      %{game: game, point: point}
    end

    test "sets scoring_team", %{point: point} do
      assert {:ok, ended} = Games.end_point(point, :ours)
      assert ended.scoring_team == :ours
    end

    test "is idempotent when called with the same scoring_team", %{point: point} do
      {:ok, ended} = Games.end_point(point, :theirs)
      assert {:ok, again} = Games.end_point(ended, :theirs)
      assert again.scoring_team == :theirs
    end

    test "errors when called with a conflicting scoring_team", %{point: point} do
      {:ok, ended} = Games.end_point(point, :ours)
      assert {:error, :scoring_team_conflict} = Games.end_point(ended, :theirs)
    end
  end

  describe "current_point/1" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id)
      player = member_fixture(team_id: team.id)
      %{team: team, game: game, player: player}
    end

    test "returns nil when no points yet", %{game: game} do
      assert Games.current_point(game) == nil
    end

    test "returns the in-progress point", %{game: game, player: player} do
      {:ok, pt1} = Games.start_point(game, [player.id])
      {:ok, _} = Games.end_point(pt1, :ours)
      {:ok, pt2} = Games.start_point(game, [player.id])

      assert %Point{id: id} = Games.current_point(game)
      assert id == pt2.id
    end

    test "returns nil when all points have ended", %{game: game, player: player} do
      {:ok, pt} = Games.start_point(game, [player.id])
      {:ok, _} = Games.end_point(pt, :ours)
      assert Games.current_point(game) == nil
    end
  end

  describe "next_point_sequence/1" do
    test "is 1 for an empty game" do
      game = game_fixture()
      assert Games.next_point_sequence(game) == 1
    end

    test "increments past the highest sequence" do
      team = team_fixture()
      game = game_fixture(team_id: team.id)
      _ = point_fixture(game_id: game.id, sequence: 1)
      _ = point_fixture(game_id: game.id, sequence: 2)
      assert Games.next_point_sequence(game) == 3
    end
  end

  describe "record_event/3" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id)
      player = member_fixture(team_id: team.id)
      {:ok, point} = Games.start_point(game, [player.id])
      %{team: team, game: game, player: player, point: point}
    end

    test "records a goal pinned to a player", %{point: point, player: player} do
      assert {:ok, ev} = Games.record_event(point, :goal, player.id)
      assert ev.type == :goal
      assert ev.user_id == player.id
      assert ev.sequence == 1
      assert ev.occurred_at
    end

    test "records an event with no player (user_id=nil)", %{point: point} do
      assert {:ok, ev} = Games.record_event(point, :turn, nil)
      assert ev.user_id == nil
    end

    test "rejects a player not on the team's roster", %{point: point} do
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id)

      assert {:error, :user_not_on_team} =
               Games.record_event(point, :goal, stranger.id)
    end

    test "auto-increments sequence", %{point: point, player: player} do
      {:ok, e1} = Games.record_event(point, :block, player.id)
      {:ok, e2} = Games.record_event(point, :turn, player.id)
      assert e1.sequence == 1
      assert e2.sequence == 2
    end
  end

  describe "update_event/2" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id)
      player = member_fixture(team_id: team.id)
      other_player = member_fixture(team_id: team.id, jersey_number: "9")
      {:ok, point} = Games.start_point(game, [player.id, other_player.id])
      {:ok, event} = Games.record_event(point, :goal, player.id)

      %{
        team: team,
        game: game,
        player: player,
        other_player: other_player,
        point: point,
        event: event
      }
    end

    test "updates :type", %{event: event} do
      assert {:ok, updated} = Games.update_event(event, %{type: :turn})
      assert updated.type == :turn
      assert Repo.get!(Event, event.id).type == :turn
    end

    test "updates :user_id to a same-team player", %{event: event, other_player: other_player} do
      assert {:ok, updated} = Games.update_event(event, %{user_id: other_player.id})
      assert updated.user_id == other_player.id
    end

    test "rejects a :user_id from a different team's roster", %{event: event} do
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id, jersey_number: "99")

      assert {:error, :user_not_on_team} =
               Games.update_event(event, %{user_id: stranger.id})

      # No fields touched.
      reloaded = Repo.get!(Event, event.id)
      assert reloaded.user_id == event.user_id
      assert reloaded.type == event.type
    end

    test "does not touch :sequence, :occurred_at, or :deleted_at", %{event: event} do
      original_seq = event.sequence
      original_at = event.occurred_at

      assert {:ok, updated} =
               Games.update_event(event, %{
                 type: :assist,
                 sequence: 99,
                 occurred_at: ~U[2030-01-01 00:00:00Z],
                 deleted_at: ~U[2030-01-01 00:00:00Z]
               })

      assert updated.sequence == original_seq
      assert DateTime.compare(updated.occurred_at, original_at) == :eq
      assert is_nil(updated.deleted_at)
    end

    test "accepts user_id=nil to clear the attribution", %{event: event} do
      assert {:ok, updated} = Games.update_event(event, %{user_id: nil})
      assert is_nil(updated.user_id)
    end

    test "validates :type presence — bogus type is rejected", %{event: event} do
      assert {:error, %Ecto.Changeset{}} = Games.update_event(event, %{type: nil})
    end
  end

  describe "soft_delete_event/1 + events_for_point/1" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id)
      player = member_fixture(team_id: team.id)
      {:ok, point} = Games.start_point(game, [player.id])
      %{point: point, player: player}
    end

    test "soft-delete excludes the event from reads", %{point: point, player: player} do
      {:ok, e1} = Games.record_event(point, :block, player.id)
      {:ok, e2} = Games.record_event(point, :turn, player.id)

      assert Games.events_for_point(point) |> Enum.map(& &1.id) == [e1.id, e2.id]

      {:ok, _} = Games.soft_delete_event(e1)

      assert Games.events_for_point(point) |> Enum.map(& &1.id) == [e2.id]
      # Row still exists in the DB.
      assert Repo.get!(Event, e1.id).deleted_at
    end

    test "soft-deleted events do not bump next_event_sequence", %{point: point, player: player} do
      {:ok, e1} = Games.record_event(point, :block, player.id)
      {:ok, _} = Games.soft_delete_event(e1)
      # next_event_sequence sees no live events, so it returns 1 again.
      assert Games.next_event_sequence(point) == 1
    end
  end

  defp score_n_points(game, player, scoring_team, n) do
    Enum.each(1..n, fn _ ->
      {:ok, pt} = Games.start_point(game, [player.id])
      # `:ours` points always have a goal event in production; mirror that
      # in the helper so Games.score/1 (which counts non-deleted goal
      # events on the `:ours` side) reports correctly.
      if scoring_team == :ours do
        {:ok, _} = Games.record_event(pt, :goal, player.id)
      end

      {:ok, _} = Games.end_point(pt, scoring_team)
    end)
  end

  describe "score/1, halftime?/1, hard_cap_reached?/1" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id, format: :usau_standard)
      player = member_fixture(team_id: team.id)
      %{team: team, game: game, player: player}
    end

    test "score/1 returns 0/0 with no ended points", %{game: game} do
      assert Games.score(game) == %{ours: 0, theirs: 0}
    end

    test "score/1 ignores in-progress points", %{game: game, player: player} do
      {:ok, _pt} = Games.start_point(game, [player.id])
      assert Games.score(game) == %{ours: 0, theirs: 0}
    end

    test "score/1 counts ended points by side", %{game: game, player: player} do
      score_n_points(game, player, :ours, 3)
      score_n_points(game, player, :theirs, 2)
      assert Games.score(game) == %{ours: 3, theirs: 2}
    end

    test "halftime?/1 flips at 8 for :usau_standard", %{game: game, player: player} do
      score_n_points(game, player, :ours, 7)
      refute Games.halftime?(game)
      score_n_points(game, player, :ours, 1)
      assert Games.halftime?(game)
    end

    test "halftime?/1 also flips when the opponent reaches 8", %{game: game, player: player} do
      score_n_points(game, player, :theirs, 8)
      assert Games.halftime?(game)
    end

    test "hard_cap_reached?/1 flips at 15 for :usau_standard", %{game: game, player: player} do
      score_n_points(game, player, :ours, 14)
      refute Games.hard_cap_reached?(game)
      score_n_points(game, player, :ours, 1)
      assert Games.hard_cap_reached?(game)
    end
  end

  describe "get_game_with_points!/1" do
    test "preloads points in sequence order" do
      team = team_fixture()
      game = game_fixture(team_id: team.id)
      _p2 = point_fixture(game_id: game.id, sequence: 2)
      _p1 = point_fixture(game_id: game.id, sequence: 1)
      _p3 = point_fixture(game_id: game.id, sequence: 3)

      reloaded = Games.get_game_with_points!(game.id)
      assert Enum.map(reloaded.points, & &1.sequence) == [1, 2, 3]
    end
  end

  describe "cascade behavior" do
    test "deleting a game deletes its points and events" do
      team = team_fixture()
      game = game_fixture(team_id: team.id)
      player = member_fixture(team_id: team.id)
      {:ok, point} = Games.start_point(game, [player.id])
      {:ok, event} = Games.record_event(point, :goal, player.id)

      {:ok, _} = Games.delete_game(game)

      refute Repo.get(Point, point.id)
      refute Repo.get(Event, event.id)
    end

    test "deleting a user nilifies user_id on existing events" do
      team = team_fixture()
      game = game_fixture(team_id: team.id)
      player = member_fixture(team_id: team.id)
      {:ok, point} = Games.start_point(game, [player.id])
      {:ok, event} = Games.record_event(point, :goal, player.id)

      {:ok, _} = Repo.delete(player)

      reloaded = Repo.get!(Event, event.id)
      assert reloaded.user_id == nil
    end
  end

  describe "summary_for_game/1" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id)

      # Numeric jerseys: 3, 7, 11; plus a nil-jersey player (sorts last).
      pa = member_fixture(team_id: team.id, first_name: "Ada", last_name: "A", jersey_number: "7")

      pb =
        member_fixture(team_id: team.id, first_name: "Bea", last_name: "B", jersey_number: "11")

      pc = member_fixture(team_id: team.id, first_name: "Cal", last_name: "C", jersey_number: "3")
      pd = member_fixture(team_id: team.id, first_name: "Dee", last_name: "D", jersey_number: nil)

      %{team: team, game: game, pa: pa, pb: pb, pc: pc, pd: pd}
    end

    test "empty game returns 0/0 score and all-zero rows", %{game: game} do
      summary = Games.summary_for_game(game)
      assert summary.score == %{ours: 0, theirs: 0}
      assert length(summary.players) == 4

      Enum.each(summary.players, fn row ->
        assert row.goals == 0
        assert row.assists == 0
        assert row.blocks == 0
        assert row.turns == 0
        assert row.points_played == 0
      end)
    end

    test "tallies a goal for the scorer and our score", %{game: game, pa: pa, pb: pb} do
      {:ok, point} = Games.start_point(game, [pa.id, pb.id])
      {:ok, _} = Games.record_event(point, :goal, pa.id)
      {:ok, _} = Games.end_point(point, :ours)

      summary = Games.summary_for_game(game)
      assert summary.score == %{ours: 1, theirs: 0}

      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      b_row = Enum.find(summary.players, &(&1.user.id == pb.id))

      assert a_row.goals == 1
      assert b_row.goals == 0
      # Both played the point.
      assert a_row.points_played == 1
      assert b_row.points_played == 1
    end

    test "soft-deleted events drop out of the tally", %{game: game, pa: pa} do
      {:ok, point} = Games.start_point(game, [pa.id])
      {:ok, event} = Games.record_event(point, :goal, pa.id)
      {:ok, _} = Games.end_point(point, :ours)
      {:ok, _} = Games.soft_delete_event(event)

      summary = Games.summary_for_game(game)
      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      assert a_row.goals == 0
      # Score also drops back to 0 since `:ours` is event-driven.
      assert summary.score.ours == 0
    end

    test "points_played counts snapshot membership even with no events", %{
      game: game,
      pa: pa,
      pb: pb
    } do
      {:ok, point1} = Games.start_point(game, [pa.id, pb.id])
      {:ok, _} = Games.end_point(point1, :theirs)

      {:ok, point2} = Games.start_point(game, [pa.id])
      {:ok, _} = Games.end_point(point2, :theirs)

      summary = Games.summary_for_game(game)
      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      b_row = Enum.find(summary.players, &(&1.user.id == pb.id))

      assert a_row.points_played == 2
      assert b_row.points_played == 1
      assert a_row.goals == 0
      assert summary.score == %{ours: 0, theirs: 2}
    end

    test "cross-team ids in a snapshot are ignored defensively", %{
      team: team,
      game: game,
      pa: pa
    } do
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id, jersey_number: "99")

      # Bypass start_point/2's filter to simulate a corrupt snapshot.
      _point =
        point_fixture(
          game_id: game.id,
          our_line_snapshot: %{"user_ids" => [pa.id, stranger.id]}
        )

      summary = Games.summary_for_game(game)
      # stranger doesn't appear in players (roster-scoped).
      refute Enum.any?(summary.players, &(&1.user.id == stranger.id))
      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      assert a_row.points_played == 1

      # silence unused
      _ = team
    end

    test "players sort by jersey ascending; nil jersey last", %{
      game: game,
      pa: pa,
      pb: pb,
      pc: pc,
      pd: pd
    } do
      summary = Games.summary_for_game(game)
      ids_in_order = Enum.map(summary.players, & &1.user.id)
      # Numeric: 3 (pc), 7 (pa), 11 (pb), then nil-jersey pd.
      assert ids_in_order == [pc.id, pa.id, pb.id, pd.id]
    end
  end

  describe "rulesets" do
    alias Ultistats.Games.Ruleset

    test "list_rulesets_for_team/1 returns only :template rows for the team, name asc" do
      team = team_fixture(%{name: "Home"})
      other = team_fixture(%{name: "Away"})

      _stranger = ruleset_fixture(%{team_id: other.id, name: "Foreign"})

      b = ruleset_fixture(%{team_id: team.id, name: "Bravo"})
      a = ruleset_fixture(%{team_id: team.id, name: "Alpha"})

      # game_instance rows are excluded from the library.
      _instance =
        ruleset_fixture(%{team_id: team.id, kind: :game_instance, name: nil})

      # archived templates are excluded too.
      archived = ruleset_fixture(%{team_id: team.id, name: "Archived"})
      {:ok, _} = Games.archive_ruleset(archived)

      results = Games.list_rulesets_for_team(team)
      assert Enum.map(results, & &1.id) == [a.id, b.id]
    end

    test "get_ruleset!/1 fetches both :template and :game_instance rows" do
      team = team_fixture()
      template = ruleset_fixture(%{team_id: team.id})
      instance = ruleset_fixture(%{team_id: team.id, kind: :game_instance, name: nil})

      assert Games.get_ruleset!(template.id).id == template.id
      assert Games.get_ruleset!(instance.id).kind == :game_instance
    end

    test "create_ruleset/1 defaults kind to :template when not supplied" do
      team = team_fixture()

      assert {:ok, %Ruleset{} = r} =
               Games.create_ruleset(%{
                 team_id: team.id,
                 name: "Standard",
                 score_cap: 15,
                 halftime_target: 8,
                 timeouts_per_half: 2,
                 gender_ratio_rule: :endzone
               })

      assert r.kind == :template
    end

    test "create_ruleset/1 requires team, kind, timeouts_per_half, gender_ratio_rule" do
      assert {:error, changeset} = Games.create_ruleset(%{})
      errors = errors_on(changeset)

      assert errors[:team_id]
      assert errors[:timeouts_per_half]
      assert errors[:gender_ratio_rule]
    end

    test "create_ruleset/1 requires at least one of score_cap or hard_cap_minutes" do
      team = team_fixture()

      assert {:error, changeset} =
               Games.create_ruleset(%{
                 team_id: team.id,
                 name: "Open-ended",
                 score_cap: nil,
                 hard_cap_minutes: nil,
                 timeouts_per_half: 2,
                 gender_ratio_rule: :endzone
               })

      assert %{score_cap: [msg | _]} = errors_on(changeset)
      assert msg =~ "at least one of score_cap or hard_cap_minutes"
    end

    test "create_ruleset/1 requires :name only when kind is :template" do
      team = team_fixture()

      assert {:error, template_cs} =
               Games.create_ruleset(%{
                 team_id: team.id,
                 kind: :template,
                 name: nil,
                 score_cap: 15,
                 timeouts_per_half: 2,
                 gender_ratio_rule: :endzone
               })

      assert %{name: ["can't be blank"]} = errors_on(template_cs)

      assert {:ok, %Ruleset{name: nil, kind: :game_instance}} =
               Games.create_ruleset(%{
                 team_id: team.id,
                 kind: :game_instance,
                 name: nil,
                 score_cap: 15,
                 timeouts_per_half: 2,
                 gender_ratio_rule: :endzone
               })
    end

    test "update_ruleset/2 updates in place when no games reference it" do
      team = team_fixture()
      ruleset = ruleset_fixture(%{team_id: team.id, name: "Hat League", score_cap: 13})

      assert {:ok, updated} = Games.update_ruleset(ruleset, %{score_cap: 11})
      assert updated.id == ruleset.id
      assert updated.score_cap == 11

      # Same row in the DB; no new rows inserted.
      assert length(Games.list_rulesets_for_team(team)) == 1
    end

    test "update_ruleset/2 clones-on-write when a game references the ruleset" do
      team = team_fixture()
      old = ruleset_fixture(%{team_id: team.id, name: "Hat League", score_cap: 13})
      _game = game_fixture(%{team_id: team.id, ruleset_id: old.id})

      assert {:ok, new_ruleset} = Games.update_ruleset(old, %{score_cap: 11})
      refute new_ruleset.id == old.id
      assert new_ruleset.score_cap == 11
      assert new_ruleset.kind == :template
      assert new_ruleset.name == "Hat League"
      assert is_nil(new_ruleset.archived_at)

      # Old row is still readable but archived.
      reloaded_old = Games.get_ruleset!(old.id)
      assert reloaded_old.score_cap == 13
      assert reloaded_old.archived_at

      # The team's library only shows the new row.
      ids = Enum.map(Games.list_rulesets_for_team(team), & &1.id)
      assert ids == [new_ruleset.id]
    end

    test "update_ruleset/2 clones-on-write with string-keyed string-valued params (LV form path)" do
      team = team_fixture()
      old = ruleset_fixture(%{team_id: team.id, name: "Hat League", score_cap: 13})
      _game = game_fixture(%{team_id: team.id, ruleset_id: old.id})

      # Mirrors what a LiveView form submits: string keys, string values.
      assert {:ok, new_ruleset} =
               Games.update_ruleset(old, %{
                 "score_cap" => "11",
                 "timeouts_per_half" => "1"
               })

      assert new_ruleset.score_cap == 11
      assert new_ruleset.timeouts_per_half == 1
      assert new_ruleset.name == "Hat League"
    end

    test "delete_ruleset/1 deletes when no games reference it" do
      team = team_fixture()
      ruleset = ruleset_fixture(%{team_id: team.id})

      assert {:ok, %Ruleset{}} = Games.delete_ruleset(ruleset)
      assert_raise Ecto.NoResultsError, fn -> Games.get_ruleset!(ruleset.id) end
    end

    test "delete_ruleset/1 returns {:error, :referenced_by_games} when in use" do
      team = team_fixture()
      ruleset = ruleset_fixture(%{team_id: team.id})
      _game = game_fixture(%{team_id: team.id, ruleset_id: ruleset.id})

      assert {:error, :referenced_by_games} = Games.delete_ruleset(ruleset)
      # Row still there.
      assert Games.get_ruleset!(ruleset.id).id == ruleset.id
    end

    test "archive_ruleset/1 sets archived_at and removes the row from the library" do
      team = team_fixture()
      ruleset = ruleset_fixture(%{team_id: team.id})

      assert {:ok, archived} = Games.archive_ruleset(ruleset)
      assert archived.archived_at

      assert Games.list_rulesets_for_team(team) == []
      # Still readable.
      assert Games.get_ruleset!(ruleset.id).archived_at
    end

    test "clone_ruleset_for_game/2 returns the template id when overrides match" do
      team = team_fixture()
      template = ruleset_fixture(%{team_id: team.id, score_cap: 15, halftime_target: 8})

      assert {:ok, id} =
               Games.clone_ruleset_for_game(template, %{score_cap: 15, halftime_target: 8})

      assert id == template.id
      # And the empty-overrides case.
      assert {:ok, ^id} = Games.clone_ruleset_for_game(template, %{})
    end

    test "clone_ruleset_for_game/2 inserts a :game_instance row when overrides differ" do
      team = team_fixture()
      template = ruleset_fixture(%{team_id: team.id, score_cap: 15})

      assert {:ok, id} = Games.clone_ruleset_for_game(template, %{score_cap: 11})
      refute id == template.id

      instance = Games.get_ruleset!(id)
      assert instance.kind == :game_instance
      assert is_nil(instance.name)
      assert instance.team_id == team.id
      assert instance.score_cap == 11
    end
  end
end
