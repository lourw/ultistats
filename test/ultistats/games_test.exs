defmodule Ultistats.GamesTest do
  use Ultistats.DataCase

  alias Ultistats.Games
  alias Ultistats.Games.{Event, Game, Point}
  alias Ultistats.Repo
  alias Ultistats.Teams

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
          halftime_target: nil,
          line_size: 1
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
          hard_cap_minutes: 60,
          line_size: 1
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
      p1 = member_fixture(team_id: team.id, jersey_number: "1")
      p2 = member_fixture(team_id: team.id, jersey_number: "2")
      %{team: team, p1: p1, p2: p2}
    end

    test "starts at sequence 1 and increments", %{team: team, p1: p1, p2: p2} do
      game_two = game_fixture(team_id: team.id, line_size: 2)
      assert {:ok, pt1} = Games.start_point(game_two, [p1.id, p2.id])
      assert pt1.sequence == 1
      assert pt1.scoring_team == nil
      assert pt1.our_line_snapshot == %{"user_ids" => [p1.id, p2.id]}

      # End point 1 so it's no longer the active point.
      {:ok, _} = Games.end_point(pt1, :ours)

      game_one = game_fixture(team_id: team.id, line_size: 1)
      assert {:ok, pt2} = Games.start_point(game_one, [p1.id])
      assert pt2.sequence == 1
    end

    test "filters out player ids from another team", %{team: team, p1: p1} do
      game = game_fixture(team_id: team.id, line_size: 1)
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id, jersey_number: "9")

      assert {:ok, pt} = Games.start_point(game, [p1.id, stranger.id])
      assert pt.our_line_snapshot["user_ids"] == [p1.id]
    end

    test "all-foreign player_ids returns :wrong_line_size", %{team: team} do
      game = game_fixture(team_id: team.id, line_size: 1)
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id, jersey_number: "9")

      assert {:error, :wrong_line_size} = Games.start_point(game, [stranger.id])
    end

    test "persists snapshot as a map under string key", %{team: team, p1: p1} do
      game = game_fixture(team_id: team.id, line_size: 1)
      assert {:ok, pt} = Games.start_point(game, [p1.id])
      reloaded = Repo.get!(Point, pt.id)
      assert is_map(reloaded.our_line_snapshot)
      assert reloaded.our_line_snapshot["user_ids"] == [p1.id]
    end

    test "wrong line size returns {:error, :wrong_line_size} and inserts no point",
         %{team: team, p1: p1, p2: p2} do
      game = game_fixture(team_id: team.id, line_size: 7)
      before = Repo.aggregate(Point, :count, :id)

      assert {:error, :wrong_line_size} = Games.start_point(game, [p1.id, p2.id])
      assert Repo.aggregate(Point, :count, :id) == before
    end

    test "exactly the ruleset's line_size succeeds", %{team: team, p1: p1, p2: p2} do
      game = game_fixture(team_id: team.id, line_size: 2)

      assert {:ok, %Point{} = pt} = Games.start_point(game, [p1.id, p2.id])
      assert pt.our_line_snapshot["user_ids"] == [p1.id, p2.id]
    end
  end

  describe "end_point/2" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id, line_size: 1)
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
      game = game_fixture(team_id: team.id, line_size: 1)
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

  describe "record_throw/4" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id, line_size: 2)
      passer = member_fixture(team_id: team.id, jersey_number: "1")
      receiver = member_fixture(team_id: team.id, jersey_number: "2")
      {:ok, point} = Games.start_point(game, [passer.id, receiver.id])
      %{team: team, game: game, passer: passer, receiver: receiver, point: point}
    end

    test "records a :catch with passer + receiver", %{
      point: point,
      passer: passer,
      receiver: receiver
    } do
      assert {:ok, ev} = Games.record_throw(point, :catch, passer.id, receiver.id)
      assert ev.type == :catch
      assert ev.passer_user_id == passer.id
      assert ev.receiver_user_id == receiver.id
      assert ev.sequence == 1
      assert ev.occurred_at
    end

    test "records a :goal with assister + scorer", %{
      point: point,
      passer: assister,
      receiver: scorer
    } do
      assert {:ok, ev} = Games.record_throw(point, :goal, assister.id, scorer.id)
      assert ev.type == :goal
      assert ev.passer_user_id == assister.id
      assert ev.receiver_user_id == scorer.id
    end

    test "records a :throwaway with passer only; receiver stays nil", %{
      point: point,
      passer: passer
    } do
      assert {:ok, ev} = Games.record_throw(point, :throwaway, passer.id, nil)
      assert ev.type == :throwaway
      assert ev.passer_user_id == passer.id
      assert is_nil(ev.receiver_user_id)
    end

    test "records a :pick with both ids nil", %{point: point} do
      assert {:ok, ev} = Games.record_throw(point, :pick, nil, nil)
      assert ev.type == :pick
      assert is_nil(ev.passer_user_id)
      assert is_nil(ev.receiver_user_id)
    end

    test "records a :foul with both ids nil", %{point: point} do
      assert {:ok, ev} = Games.record_throw(point, :foul, nil, nil)
      assert ev.type == :foul
    end

    test "records an :opponent_turnover with both ids nil", %{point: point} do
      assert {:ok, ev} = Games.record_throw(point, :opponent_turnover, nil, nil)
      assert ev.type == :opponent_turnover
    end

    test "records a :block with blocker as passer; receiver nil", %{
      point: point,
      passer: blocker
    } do
      assert {:ok, ev} = Games.record_throw(point, :block, blocker.id, nil)
      assert ev.type == :block
      assert ev.passer_user_id == blocker.id
      assert is_nil(ev.receiver_user_id)
    end

    test "accepts passer_id=nil (Unknown) for a :catch", %{point: point, receiver: receiver} do
      assert {:ok, ev} = Games.record_throw(point, :catch, nil, receiver.id)
      assert is_nil(ev.passer_user_id)
      assert ev.receiver_user_id == receiver.id
    end

    test "accepts receiver_id=nil (Unknown) for a :goal", %{point: point, passer: passer} do
      assert {:ok, ev} = Games.record_throw(point, :goal, passer.id, nil)
      assert ev.passer_user_id == passer.id
      assert is_nil(ev.receiver_user_id)
    end

    test "accepts both ids nil (Unknown) for a :catch", %{point: point} do
      assert {:ok, ev} = Games.record_throw(point, :catch, nil, nil)
      assert is_nil(ev.passer_user_id)
      assert is_nil(ev.receiver_user_id)
    end

    test "rejects a passer not on the team", %{point: point} do
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id, jersey_number: "9")

      assert {:error, :user_not_on_team} =
               Games.record_throw(point, :catch, stranger.id, nil)
    end

    test "rejects a receiver not on the team", %{point: point, passer: passer} do
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id, jersey_number: "9")

      assert {:error, :user_not_on_team} =
               Games.record_throw(point, :catch, passer.id, stranger.id)
    end

    test "rejects a :throwaway with a non-nil receiver_id", %{
      point: point,
      passer: passer,
      receiver: receiver
    } do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Games.record_throw(point, :throwaway, passer.id, receiver.id)

      assert %{receiver_user_id: ["is not allowed for throwaway events"]} = errors_on(changeset)
    end

    test "rejects a :pick with a non-nil passer_id", %{point: point, passer: passer} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Games.record_throw(point, :pick, passer.id, nil)

      assert %{passer_user_id: ["is not allowed for pick events"]} = errors_on(changeset)
    end

    test "auto-increments sequence", %{point: point, passer: passer} do
      {:ok, e1} = Games.record_throw(point, :block, passer.id, nil)
      {:ok, e2} = Games.record_throw(point, :pick, nil, nil)
      assert e1.sequence == 1
      assert e2.sequence == 2
    end
  end

  describe "update_event/2" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id, line_size: 3)
      passer = member_fixture(team_id: team.id, jersey_number: "1")
      receiver = member_fixture(team_id: team.id, jersey_number: "2")
      other_player = member_fixture(team_id: team.id, jersey_number: "9")
      {:ok, point} = Games.start_point(game, [passer.id, receiver.id, other_player.id])
      {:ok, event} = Games.record_throw(point, :goal, passer.id, receiver.id)

      %{
        team: team,
        game: game,
        passer: passer,
        receiver: receiver,
        other_player: other_player,
        point: point,
        event: event
      }
    end

    test "updates :type", %{event: event} do
      assert {:ok, updated} = Games.update_event(event, %{type: :catch})
      assert updated.type == :catch
      assert Repo.get!(Event, event.id).type == :catch
    end

    test "updates :passer_id to a same-team player", %{event: event, other_player: other} do
      assert {:ok, updated} = Games.update_event(event, %{passer_user_id: other.id})
      assert updated.passer_user_id == other.id
    end

    test "updates :receiver_id to a same-team player", %{event: event, other_player: other} do
      assert {:ok, updated} = Games.update_event(event, %{receiver_user_id: other.id})
      assert updated.receiver_user_id == other.id
    end

    test "rejects a :passer_id from a different team's roster", %{event: event} do
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id, jersey_number: "99")

      assert {:error, :user_not_on_team} =
               Games.update_event(event, %{passer_user_id: stranger.id})

      # No fields touched.
      reloaded = Repo.get!(Event, event.id)
      assert reloaded.passer_user_id == event.passer_user_id
      assert reloaded.type == event.type
    end

    test "rejects a :receiver_id from a different team's roster", %{event: event} do
      other_team = team_fixture()
      stranger = member_fixture(team_id: other_team.id, jersey_number: "99")

      assert {:error, :user_not_on_team} =
               Games.update_event(event, %{receiver_user_id: stranger.id})
    end

    test "does not touch :sequence, :occurred_at, or :deleted_at", %{event: event} do
      original_seq = event.sequence
      original_at = event.occurred_at

      assert {:ok, updated} =
               Games.update_event(event, %{
                 type: :catch,
                 sequence: 99,
                 occurred_at: ~U[2030-01-01 00:00:00Z],
                 deleted_at: ~U[2030-01-01 00:00:00Z]
               })

      assert updated.sequence == original_seq
      assert DateTime.compare(updated.occurred_at, original_at) == :eq
      assert is_nil(updated.deleted_at)
    end

    test "accepts passer_id=nil to clear the attribution", %{event: event} do
      assert {:ok, updated} = Games.update_event(event, %{passer_user_id: nil})
      assert is_nil(updated.passer_user_id)
    end

    test "validates :type presence — bogus type is rejected", %{event: event} do
      assert {:error, %Ecto.Changeset{}} = Games.update_event(event, %{type: nil})
    end
  end

  describe "soft_delete_event/1 + events_for_point/1" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id, line_size: 1)
      player = member_fixture(team_id: team.id)
      {:ok, point} = Games.start_point(game, [player.id])
      %{point: point, player: player}
    end

    test "soft-delete excludes the event from reads", %{point: point, player: player} do
      {:ok, e1} = Games.record_throw(point, :block, player.id, nil)
      {:ok, e2} = Games.record_throw(point, :throwaway, player.id, nil)

      assert Games.events_for_point(point) |> Enum.map(& &1.id) == [e1.id, e2.id]

      {:ok, _} = Games.soft_delete_event(e1)

      assert Games.events_for_point(point) |> Enum.map(& &1.id) == [e2.id]
      # Row still exists in the DB.
      assert Repo.get!(Event, e1.id).deleted_at
    end

    test "soft-deleted events do not bump next_event_sequence", %{point: point, player: player} do
      {:ok, e1} = Games.record_throw(point, :block, player.id, nil)
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
        {:ok, _} = Games.record_throw(pt, :goal, player.id, player.id)
      end

      {:ok, _} = Games.end_point(pt, scoring_team)
    end)
  end

  describe "score/1, halftime?/1, hard_cap_reached?/1" do
    setup do
      team = team_fixture()
      game = game_fixture(team_id: team.id, format: :usau_standard, line_size: 1)
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
      game = game_fixture(team_id: team.id, line_size: 1)
      player = member_fixture(team_id: team.id)
      {:ok, point} = Games.start_point(game, [player.id])
      {:ok, event} = Games.record_throw(point, :goal, player.id, player.id)

      {:ok, _} = Games.delete_game(game)

      refute Repo.get(Point, point.id)
      refute Repo.get(Event, event.id)
    end

    test "deleting a user nilifies passer_user_id and receiver_user_id on existing events" do
      team = team_fixture()
      game = game_fixture(team_id: team.id, line_size: 2)
      player = member_fixture(team_id: team.id)
      other = member_fixture(team_id: team.id, jersey_number: "9")
      {:ok, point} = Games.start_point(game, [player.id, other.id])
      {:ok, event} = Games.record_throw(point, :goal, player.id, other.id)

      {:ok, _} = Repo.delete(player)

      reloaded = Repo.get!(Event, event.id)
      assert reloaded.passer_user_id == nil
      assert reloaded.receiver_user_id == other.id
    end
  end

  describe "summary_for_game/1" do
    setup do
      team = team_fixture()

      # Numeric jerseys: 3, 7, 11; plus a nil-jersey player (sorts last).
      pa = member_fixture(team_id: team.id, first_name: "Ada", last_name: "A", jersey_number: "7")

      pb =
        member_fixture(team_id: team.id, first_name: "Bea", last_name: "B", jersey_number: "11")

      pc = member_fixture(team_id: team.id, first_name: "Cal", last_name: "C", jersey_number: "3")
      pd = member_fixture(team_id: team.id, first_name: "Dee", last_name: "D", jersey_number: nil)

      %{team: team, pa: pa, pb: pb, pc: pc, pd: pd}
    end

    test "empty game returns 0/0 score and all-zero rows", %{team: team} do
      game = game_fixture(team_id: team.id)
      summary = Games.summary_for_game(game)
      assert summary.score == %{ours: 0, theirs: 0}
      assert length(summary.players) == 4

      Enum.each(summary.players, fn row ->
        assert row.goals == 0
        assert row.assists == 0
        assert row.catches == 0
        assert row.drops == 0
        assert row.throwaways == 0
        assert row.blocks == 0
        assert row.points_played == 0
      end)
    end

    test "tallies a goal as scorer goal + assister assist", %{team: team, pa: pa, pb: pb} do
      game = game_fixture(team_id: team.id, line_size: 2)
      {:ok, point} = Games.start_point(game, [pa.id, pb.id])
      {:ok, _} = Games.record_throw(point, :goal, pb.id, pa.id)
      {:ok, _} = Games.end_point(point, :ours)

      summary = Games.summary_for_game(game)
      assert summary.score == %{ours: 1, theirs: 0}

      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      b_row = Enum.find(summary.players, &(&1.user.id == pb.id))

      # pa is the scorer (receiver), pb the assister (passer).
      assert a_row.goals == 1
      assert a_row.assists == 0
      assert b_row.goals == 0
      assert b_row.assists == 1
      assert a_row.points_played == 1
      assert b_row.points_played == 1
    end

    test "tallies catches for the receiver of a :catch", %{team: team, pa: pa, pb: pb} do
      game = game_fixture(team_id: team.id, line_size: 2)
      {:ok, point} = Games.start_point(game, [pa.id, pb.id])
      {:ok, _} = Games.record_throw(point, :catch, pa.id, pb.id)
      {:ok, _} = Games.end_point(point, :theirs)

      summary = Games.summary_for_game(game)
      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      b_row = Enum.find(summary.players, &(&1.user.id == pb.id))

      assert b_row.catches == 1
      assert a_row.catches == 0
    end

    test "a :drop counts as a drop on the receiver and a throwaway on the passer", %{
      team: team,
      pa: pa,
      pb: pb
    } do
      game = game_fixture(team_id: team.id, line_size: 2)
      {:ok, point} = Games.start_point(game, [pa.id, pb.id])
      {:ok, _} = Games.record_throw(point, :drop, pa.id, pb.id)
      {:ok, _} = Games.end_point(point, :theirs)

      summary = Games.summary_for_game(game)
      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      b_row = Enum.find(summary.players, &(&1.user.id == pb.id))

      assert b_row.drops == 1
      assert a_row.throwaways == 1
    end

    test "a :throwaway counts as a throwaway on the passer", %{team: team, pa: pa} do
      game = game_fixture(team_id: team.id, line_size: 1)
      {:ok, point} = Games.start_point(game, [pa.id])
      {:ok, _} = Games.record_throw(point, :throwaway, pa.id, nil)
      {:ok, _} = Games.end_point(point, :theirs)

      summary = Games.summary_for_game(game)
      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      assert a_row.throwaways == 1
    end

    test "a :block counts as a block on the blocker", %{team: team, pa: pa} do
      game = game_fixture(team_id: team.id, line_size: 1)
      {:ok, point} = Games.start_point(game, [pa.id])
      {:ok, _} = Games.record_throw(point, :block, pa.id, nil)
      {:ok, _} = Games.end_point(point, :ours)

      summary = Games.summary_for_game(game)
      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      assert a_row.blocks == 1
    end

    test "calls and opponent events do not move per-player counters", %{team: team, pa: pa} do
      game = game_fixture(team_id: team.id, line_size: 1)
      {:ok, point} = Games.start_point(game, [pa.id])
      {:ok, _} = Games.record_throw(point, :pick, nil, nil)
      {:ok, _} = Games.record_throw(point, :foul, nil, nil)
      {:ok, _} = Games.record_throw(point, :opponent_turnover, nil, nil)
      {:ok, _} = Games.end_point(point, :theirs)

      summary = Games.summary_for_game(game)
      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      assert a_row.goals == 0
      assert a_row.assists == 0
      assert a_row.catches == 0
      assert a_row.drops == 0
      assert a_row.throwaways == 0
      assert a_row.blocks == 0
    end

    test "soft-deleted events drop out of the tally", %{team: team, pa: pa} do
      game = game_fixture(team_id: team.id, line_size: 1)
      {:ok, point} = Games.start_point(game, [pa.id])
      {:ok, event} = Games.record_throw(point, :goal, pa.id, pa.id)
      {:ok, _} = Games.end_point(point, :ours)
      {:ok, _} = Games.soft_delete_event(event)

      summary = Games.summary_for_game(game)
      a_row = Enum.find(summary.players, &(&1.user.id == pa.id))
      assert a_row.goals == 0
      # Score also drops back to 0 since `:ours` is event-driven.
      assert summary.score.ours == 0
    end

    test "points_played counts snapshot membership even with no events", %{
      team: team,
      pa: pa,
      pb: pb
    } do
      game = game_fixture(team_id: team.id, line_size: 2)
      {:ok, point1} = Games.start_point(game, [pa.id, pb.id])
      {:ok, _} = Games.end_point(point1, :theirs)

      # Point 2 needs a different line size — bypass start_point's
      # enforcement by inserting via point_fixture.
      _point2 =
        point_fixture(
          game_id: game.id,
          our_line_snapshot: %{"user_ids" => [pa.id]},
          scoring_team: :theirs
        )

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
      pa: pa
    } do
      game = game_fixture(team_id: team.id)
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
    end

    test "players sort by jersey ascending; nil jersey last", %{
      team: team,
      pa: pa,
      pb: pb,
      pc: pc,
      pd: pd
    } do
      game = game_fixture(team_id: team.id)
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
                 line_size: 7,
                 gender_ratio_rule: :endzone,
                 starting_male_count: 4,
                 starting_female_count: 3
               })

      assert r.kind == :template
    end

    test "create_ruleset/1 requires kind, timeouts_per_half, line_size, gender_ratio_rule" do
      assert {:error, changeset} = Games.create_ruleset(%{})
      errors = errors_on(changeset)

      # team_id is optional — system rulesets carry team_id: nil.
      refute errors[:team_id]
      assert errors[:timeouts_per_half]
      assert errors[:line_size]
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
                 line_size: 7,
                 gender_ratio_rule: :endzone,
                 starting_male_count: 4,
                 starting_female_count: 3
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
                 line_size: 7,
                 gender_ratio_rule: :endzone,
                 starting_male_count: 4,
                 starting_female_count: 3
               })

      assert %{name: ["can't be blank"]} = errors_on(template_cs)

      assert {:ok, %Ruleset{name: nil, kind: :game_instance}} =
               Games.create_ruleset(%{
                 team_id: team.id,
                 kind: :game_instance,
                 name: nil,
                 score_cap: 15,
                 timeouts_per_half: 2,
                 line_size: 7,
                 gender_ratio_rule: :endzone,
                 starting_male_count: 4,
                 starting_female_count: 3
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

  describe "system rulesets" do
    alias Ultistats.Games.Ruleset
    alias Ultistats.Release

    import Ultistats.AccountsFixtures

    test "Ruleset.changeset/2 accepts team_id: nil for a :template row" do
      attrs = %{
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
      }

      changeset = Ruleset.changeset(%Ruleset{}, attrs)

      assert changeset.valid?
      assert {:ok, %Ruleset{team_id: nil}} = Ultistats.Repo.insert(changeset)
    end

    test "Release.seed_system_rulesets/0 is idempotent" do
      :ok = Release.seed_system_rulesets()

      first_pass =
        from(r in Ruleset, where: is_nil(r.team_id)) |> Ultistats.Repo.all()

      assert length(first_pass) == 3
      assert Enum.all?(first_pass, &is_nil(&1.team_id))

      :ok = Release.seed_system_rulesets()

      second_pass =
        from(r in Ruleset, where: is_nil(r.team_id)) |> Ultistats.Repo.all()

      assert length(second_pass) == 3

      assert Enum.map(first_pass, & &1.id) |> Enum.sort() ==
               Enum.map(second_pass, & &1.id) |> Enum.sort()
    end

    test "list_rulesets_for_user/1 includes system rulesets for a user with no teams" do
      user = user_fixture()
      :ok = Release.seed_system_rulesets()

      results = Games.list_rulesets_for_user(user.id)

      names = results |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["USAU Mixed", "USAU Open", "USAU Women's"]
      assert Enum.all?(results, &is_nil(&1.team_id))
    end

    test "list_rulesets_for_user/1 returns the user's team rulesets plus system rulesets, no dupes" do
      user = user_fixture()
      team = team_fixture(%{name: "Owls"})
      {:ok, _m} = Teams.add_team_member(team, user, %{role: :admin, is_player: true})
      own = ruleset_fixture(%{team_id: team.id, name: "Owls Standard"})

      :ok = Release.seed_system_rulesets()

      results = Games.list_rulesets_for_user(user.id)
      names = results |> Enum.map(& &1.name) |> Enum.sort()

      assert "Owls Standard" in names
      assert "USAU Open" in names
      assert "USAU Women's" in names
      assert "USAU Mixed" in names

      ids = Enum.map(results, & &1.id)
      assert length(ids) == length(Enum.uniq(ids))
      assert own.id in ids
    end
  end
end
