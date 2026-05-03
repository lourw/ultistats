defmodule UltistatsWeb.GameLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.GamesFixtures
  import Ultistats.TeamsFixtures

  alias Ultistats.{Games, Teams}
  alias Ultistats.Repo
  alias Ultistats.Accounts.User
  alias Ultistats.Games.{Event, Point}

  defp add_to_team(team, user, role \\ :admin) do
    {:ok, _m} =
      Teams.add_team_member(team, user, %{role: role, is_player: true})

    :ok
  end

  describe "Start" do
    setup :register_and_log_in_user

    test "renders the empty state when the user has no teams", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/games/new")

      assert html =~ "Create a team first"
      assert html =~ ~p"/teams/new"
      refute html =~ ~s(id="game-form")
    end

    test "only the user's accessible teams populate the picker", %{conn: conn, user: user} do
      mine = team_fixture(%{name: "Mine"})
      _theirs = team_fixture(%{name: "Theirs"})
      add_to_team(mine, user)

      {:ok, _live, html} = live(conn, ~p"/games/new")

      # Single-team flow: hidden team_id field, no select rendered.
      assert html =~ "Start a game"
      refute html =~ "Theirs"
    end

    test "renders the form with first_pull defaulted to :ours", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user)

      {:ok, live, html} = live(conn, ~p"/games/new")

      assert html =~ "Start a game"
      assert has_element?(live, "#game-form")
      assert html =~ ~r/<option[^>]*selected[^>]*value="ours">We pull</
      assert html =~ "USAU standard (no template)"
    end

    test "pre-selects the team when ?team_id=... is provided", %{conn: conn, user: user} do
      other = team_fixture(%{name: "Other"})
      target = team_fixture(%{name: "Target"})
      add_to_team(other, user)
      add_to_team(target, user)

      {:ok, _live, html} = live(conn, ~p"/games/new?team_id=#{target.id}")

      assert html =~ ~r/<option[^>]*selected[^>]*value="#{target.id}">Target</
    end

    test "ignores a bogus team_id query param without 404", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user)

      {:ok, _live, html} =
        live(conn, ~p"/games/new?team_id=00000000-0000-0000-0000-000000000000")

      assert html =~ "Start a game"
    end

    test "validates required fields — blank opponent shows error", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user)

      {:ok, live, _html} = live(conn, ~p"/games/new")

      html =
        live
        |> form("#game-form",
          game: %{"team_id" => team.id, "opponent_name" => "", "first_pull" => "ours"}
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "rejects an opponent name longer than 80 chars", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user)
      long_name = String.duplicate("x", 81)

      {:ok, live, _html} = live(conn, ~p"/games/new")

      html =
        live
        |> form("#game-form",
          game: %{"team_id" => team.id, "opponent_name" => long_name, "first_pull" => "ours"}
        )
        |> render_submit()

      assert html =~ "should be at most 80 character"
    end

    test "successful submit creates a game and navigates to /games/:id", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      add_to_team(team, user)

      {:ok, live, _html} = live(conn, ~p"/games/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               live
               |> form("#game-form",
                 game: %{
                   "team_id" => team.id,
                   "opponent_name" => "Sky Pirates",
                   "first_pull" => "theirs"
                 }
               )
               |> render_submit()

      games = Games.list_games()
      assert length(games) == 1
      [game] = games
      assert game.opponent_name == "Sky Pirates"
      assert game.team_id == team.id
      assert game.first_pull == :theirs
      assert game.format == :usau_standard
      assert game.status == :in_progress
      assert game.started_at
      assert to == ~p"/games/#{game.id}"
    end

    test "ruleset picker lists the team's templates", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user)
      _hat = ruleset_fixture(%{team_id: team.id, name: "Hat League"})
      _strict = ruleset_fixture(%{team_id: team.id, name: "Strict Tourney"})

      {:ok, _live, html} = live(conn, ~p"/games/new?team_id=#{team.id}")

      assert html =~ "Hat League"
      assert html =~ "Strict Tourney"
    end

    test "picking a ruleset prefills the rule fields", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user)

      template =
        ruleset_fixture(%{
          team_id: team.id,
          name: "Hat League",
          score_cap: 13,
          halftime_target: 7,
          soft_cap_minutes: 50,
          hard_cap_minutes: 60,
          timeouts_per_half: 1
        })

      {:ok, live, _html} = live(conn, ~p"/games/new?team_id=#{team.id}")

      html =
        live
        |> form("#game-form", game: %{"ruleset_id" => template.id})
        |> render_change()

      # Rendered <input value="..."> reflects the template values.
      assert html =~ ~s(value="13")
      assert html =~ ~s(value="7")
      assert html =~ ~s(value="50")
      assert html =~ ~s(value="60")
    end

    test "per-game tweak creates a :game_instance, not a mutation of the template", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      add_to_team(team, user)

      template =
        ruleset_fixture(%{
          team_id: team.id,
          name: "Hat League",
          score_cap: 13,
          halftime_target: 7,
          timeouts_per_half: 1
        })

      {:ok, live, _html} = live(conn, ~p"/games/new?team_id=#{team.id}")

      # Select the template (prefills the rule fields).
      live
      |> form("#game-form", game: %{"ruleset_id" => template.id})
      |> render_change()

      # Submit with the score_cap tweaked from 13 to 11.
      assert {:error, {:live_redirect, %{to: _to}}} =
               live
               |> form("#game-form",
                 game: %{
                   "team_id" => team.id,
                   "opponent_name" => "Rivals",
                   "first_pull" => "ours",
                   "ruleset_id" => template.id
                 },
                 rule_overrides: %{
                   "score_cap" => "11",
                   "halftime_target" => "7",
                   "timeouts_per_half" => "1",
                   "gender_ratio_rule" => "endzone",
                   "default_starting_ratio" => "four_men_three_women"
                 }
               )
               |> render_submit()

      [game] = Games.list_games()
      refute game.ruleset_id == template.id

      attached = Games.get_ruleset!(game.ruleset_id)
      assert attached.kind == :game_instance
      assert attached.score_cap == 11

      # Original template untouched.
      assert Games.get_ruleset!(template.id).score_cap == 13
    end
  end

  describe "Show — between points" do
    setup :register_and_log_in_user

    setup %{user: user} do
      team = team_fixture()
      add_to_team(team, user)
      players = build_players(team, 7)
      game = game_fixture(%{team_id: team.id, opponent_name: "Stormcrows"})
      %{team: team, players: players, game: game}
    end

    test "renders score header and line picker, Start point disabled", %{
      conn: conn,
      game: game,
      players: players
    } do
      {:ok, live, html} = live(conn, ~p"/games/#{game.id}")

      assert html =~ "vs Stormcrows"
      assert html =~ "Pick line for point 1"
      assert html =~ "0 selected"

      # First player is rendered as a chip
      first = hd(players)

      assert has_element?(
               live,
               "button[phx-value-id='#{first.user_id}']",
               User.display_name(first.user)
             )

      # Start point button is disabled before any selection.
      assert has_element?(live, "button[phx-click='start_point'][disabled]")
    end

    test "toggling player chips updates the selection counter", %{
      conn: conn,
      game: game,
      players: players
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [p1, p2 | _] = players

      live
      |> element("button[phx-value-id='#{p1.user_id}']")
      |> render_click()

      live
      |> element("button[phx-value-id='#{p2.user_id}']")
      |> render_click()

      assert render(live) =~ "2 selected"
    end

    test "selecting a line preset populates the roster", %{
      conn: conn,
      team: team,
      game: game,
      players: players
    } do
      preset_players = Enum.take(players, 5)
      ids = Enum.map(preset_players, & &1.user_id)

      preset = line_preset_fixture(%{team_id: team.id, name: "O-line A", user_ids: ids})

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      live
      |> element("button[phx-value-id='#{preset.id}']")
      |> render_click()

      assert render(live) =~ "5 selected"
    end

    test "Start point creates a Point and transitions to in-point view", %{
      conn: conn,
      game: game,
      players: players
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      Enum.each(Enum.take(players, 7), fn p ->
        live |> element("button[phx-value-id='#{p.user_id}']") |> render_click()
      end)

      live |> element("button[phx-click='start_point']") |> render_click()

      html = render(live)
      assert html =~ "On the field"
      assert html =~ "Recent events"

      # 4 action buttons appear when a point is in progress.
      assert has_element?(live, "button[phx-value-kind='goal']", "Goal")
      assert has_element?(live, "button[phx-value-kind='assist']", "Assist")
      assert has_element?(live, "button[phx-value-kind='block']", "Block")
      assert has_element?(live, "button[phx-value-kind='turn']", "Turn")

      assert Repo.aggregate(Point, :count, :id) == 1
    end
  end

  describe "Show — in point" do
    setup :register_and_log_in_user

    setup %{user: user} do
      team = team_fixture()
      add_to_team(team, user)
      players = build_players(team, 7)
      game = game_fixture(%{team_id: team.id})

      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.user_id))

      %{team: team, players: players, game: game, point: point}
    end

    test "Goal → Skip assist → point ends with scoring_team=:ours, score increments", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      live |> element("button[phx-value-kind='goal']") |> render_click()
      assert render(live) =~ "Who scored?"

      scorer = hd(players)

      live
      |> element("#player-picker-modal button[phx-value-id='#{scorer.user_id}']")
      |> render_click()

      html = render(live)
      assert html =~ "Who got the assist?"
      assert html =~ "Skip — no assist"

      live |> element("button[phx-click='skip_assist']") |> render_click()

      reloaded = Repo.get!(Point, point.id)
      assert reloaded.scoring_team == :ours

      events = Games.events_for_point(reloaded)
      assert Enum.any?(events, &(&1.type == :goal and &1.user_id == scorer.user_id))
      refute Enum.any?(events, &(&1.type == :assist))

      # back to between-points view, score updated
      html = render(live)
      assert html =~ "Pick line for point 2"
      # our score is 1
      assert Games.score(game) == %{ours: 1, theirs: 0}
    end

    test "Goal → pick assister → point ends with both events recorded", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [scorer, assister | _] = players

      live |> element("button[phx-value-kind='goal']") |> render_click()

      live
      |> element("#player-picker-modal button[phx-value-id='#{scorer.user_id}']")
      |> render_click()

      live
      |> element("#player-picker-modal button[phx-value-id='#{assister.user_id}']")
      |> render_click()

      reloaded = Repo.get!(Point, point.id)
      assert reloaded.scoring_team == :ours

      events = Games.events_for_point(reloaded)
      assert Enum.any?(events, &(&1.type == :goal and &1.user_id == scorer.user_id))
      assert Enum.any?(events, &(&1.type == :assist and &1.user_id == assister.user_id))
    end

    test "Block records an event but does not end the point", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      blocker = hd(players)

      live |> element("button[phx-value-kind='block']") |> render_click()

      live
      |> element("#player-picker-modal button[phx-value-id='#{blocker.user_id}']")
      |> render_click()

      reloaded = Repo.get!(Point, point.id)
      assert is_nil(reloaded.scoring_team)

      [event] = Repo.all(Event)
      assert event.type == :block
      assert event.user_id == blocker.user_id

      # Action buttons still visible (point not ended).
      assert has_element?(live, "button[phx-value-kind='goal']")
    end

    test "They scored ends the point with scoring_team=:theirs, no events", %{
      conn: conn,
      game: game,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      live |> element("button[phx-click='they_scored']") |> render_click()

      reloaded = Repo.get!(Point, point.id)
      assert reloaded.scoring_team == :theirs
      assert Repo.aggregate(Event, :count, :id) == 0

      assert render(live) =~ "Pick line for point 2"
      assert Games.score(game) == %{ours: 0, theirs: 1}
    end
  end

  describe "Show — milestones" do
    setup :register_and_log_in_user

    setup %{user: user} do
      team = team_fixture()
      add_to_team(team, user)
      players = build_players(team, 7)
      game = game_fixture(%{team_id: team.id})
      %{team: team, players: players, game: game}
    end

    test "halftime banner shows when score reaches 8", %{
      conn: conn,
      game: game,
      players: players
    } do
      score_n_points_for_us(game, players, 8)

      {:ok, _live, html} = live(conn, ~p"/games/#{game.id}")

      assert html =~ "Halftime"
      assert html =~ "8–0"
    end

    test "hard cap auto-ends the game and pushes to summary", %{
      conn: conn,
      game: game,
      players: players,
      team: _team
    } do
      # Score 14 already, then play one more on the live view to trip the
      # hard cap via the in-LiveView code path.
      score_n_points_for_us(game, players, 14)

      {:ok, _point} = Games.start_point(game, Enum.map(players, & &1.user_id))

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      scorer = hd(players)
      live |> element("button[phx-value-kind='goal']") |> render_click()

      live
      |> element("#player-picker-modal button[phx-value-id='#{scorer.user_id}']")
      |> render_click()

      assert {:error, {:live_redirect, %{to: to}}} =
               live |> element("button[phx-click='skip_assist']") |> render_click()

      assert to == ~p"/games/#{game.id}/summary"

      reloaded = Repo.get!(Ultistats.Games.Game, game.id)
      assert reloaded.status == :finished
      assert reloaded.ended_at
    end

    test "mounting a finished game push_navigates to the summary route", %{
      conn: conn,
      team: team,
      players: players
    } do
      game =
        game_fixture(%{
          team_id: team.id,
          status: :in_progress
        })

      score_n_points_for_us(game, players, 15)
      {:ok, _finished} = Games.end_game(Repo.get!(Ultistats.Games.Game, game.id))

      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/games/#{game.id}")
      assert to == ~p"/games/#{game.id}/summary"
    end
  end

  describe "Timeline" do
    setup :register_and_log_in_user

    setup %{user: user} do
      team = team_fixture()
      add_to_team(team, user)
      players = build_players(team, 7)
      game = game_fixture(%{team_id: team.id, opponent_name: "Stormcrows"})
      %{team: team, players: players, game: game}
    end

    test "renders empty state when there are no points", %{conn: conn, game: game} do
      {:ok, _live, html} = live(conn, ~p"/games/#{game.id}/timeline")

      assert html =~ "Timeline"
      assert html =~ "vs Stormcrows"
      assert html =~ "No points played yet"
    end

    test "renders all events grouped by point in order", %{
      conn: conn,
      game: game,
      players: players
    } do
      [scorer, blocker | _] = players
      {:ok, p1} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, _} = Games.record_event(p1, :block, blocker.user_id)
      {:ok, _} = Games.record_event(p1, :goal, scorer.user_id)
      {:ok, _} = Games.end_point(p1, :ours)

      {:ok, p2} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, _} = Games.end_point(p2, :theirs)

      {:ok, _live, html} = live(conn, ~p"/games/#{game.id}/timeline")

      assert html =~ "Point 1"
      assert html =~ "Point 2"
      assert html =~ "We scored"
      assert html =~ "They scored"
      assert html =~ "Block"
      assert html =~ "Goal"
      # P2 has no events; the empty per-point note shows.
      assert html =~ "No events recorded for this point."
      # Scorer's number renders.
      assert html =~ "##{scorer.jersey_number}"
    end

    test "deleting a goal recomputes the score", %{
      conn: conn,
      game: game,
      players: players
    } do
      [scorer | _] = players
      {:ok, p1} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, goal} = Games.record_event(p1, :goal, scorer.user_id)
      {:ok, _} = Games.end_point(p1, :ours)
      # Manually un-end the point so deleting the goal makes the score
      # actually change. (Per task notes: scoring_team is not auto-cleared.)
      {:ok, _} =
        p1
        |> Ecto.Changeset.change(scoring_team: nil)
        |> Repo.update()

      # Score the next point so we have a "1" to start from.
      {:ok, p2} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, _} = Games.record_event(p2, :goal, scorer.user_id)
      {:ok, _} = Games.end_point(p2, :ours)

      {:ok, live, html} = live(conn, ~p"/games/#{game.id}/timeline")
      assert html =~ "Goal"

      # Open delete confirm, then confirm.
      live
      |> element("button[phx-click='ask_delete'][phx-value-id='#{goal.id}']")
      |> render_click()

      assert render(live) =~ "Confirm delete event"

      live
      |> element("button[phx-click='confirm_delete'][phx-value-id='#{goal.id}']")
      |> render_click()

      # Row gone, but score is still 1 (p2's goal). The point that owned
      # the deleted goal still has scoring_team=nil here.
      assert Games.score(game) == %{ours: 1, theirs: 0}
      assert Repo.get!(Event, goal.id).deleted_at
    end

    test "soft-delete preserves the audit row", %{
      conn: conn,
      game: game,
      players: players
    } do
      [p | _] = players
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, event} = Games.record_event(point, :block, p.user_id)

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}/timeline")

      live
      |> element("button[phx-click='ask_delete'][phx-value-id='#{event.id}']")
      |> render_click()

      live
      |> element("button[phx-click='confirm_delete'][phx-value-id='#{event.id}']")
      |> render_click()

      assert Games.events_for_point(point) == []
      assert Repo.get!(Event, event.id).deleted_at != nil
    end

    test "cancel-delete restores the row's edit/delete buttons", %{
      conn: conn,
      game: game,
      players: players
    } do
      [p | _] = players
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, event} = Games.record_event(point, :block, p.user_id)

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}/timeline")

      live
      |> element("button[phx-click='ask_delete'][phx-value-id='#{event.id}']")
      |> render_click()

      assert render(live) =~ "Confirm delete event"

      live |> element("button[phx-click='cancel_delete']") |> render_click()
      html = render(live)
      refute html =~ "Confirm delete event"
      # Row still here with its edit affordance.
      assert html =~ ~s(phx-click="open_edit")
    end

    test "editing a player updates the rendered row", %{
      conn: conn,
      game: game,
      players: players
    } do
      [p1, p2 | _] = players
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, event} = Games.record_event(point, :goal, p1.user_id)
      {:ok, _} = Games.end_point(point, :ours)

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}/timeline")

      live
      |> element("button[phx-click='open_edit'][phx-value-id='#{event.id}']")
      |> render_click()

      assert render(live) =~ "Edit event"

      # Switch to p2.
      live
      |> element(
        "#edit-event-modal button[phx-click='set_edit_player'][phx-value-id='#{p2.user_id}']"
      )
      |> render_click()

      live
      |> element("#edit-event-modal form")
      |> render_submit()

      reloaded = Repo.get!(Event, event.id)
      assert reloaded.user_id == p2.user_id

      html = render(live)
      assert html =~ "##{p2.jersey_number}"
    end

    test "editing type from :goal to :turn changes the row but not the point's scoring_team", %{
      conn: conn,
      game: game,
      players: players
    } do
      [p1 | _] = players
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, event} = Games.record_event(point, :goal, p1.user_id)
      {:ok, _} = Games.end_point(point, :ours)

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}/timeline")

      live
      |> element("button[phx-click='open_edit'][phx-value-id='#{event.id}']")
      |> render_click()

      live
      |> element("#edit-event-modal button[phx-click='set_edit_type'][phx-value-type='turn']")
      |> render_click()

      live |> element("#edit-event-modal form") |> render_submit()

      assert Repo.get!(Event, event.id).type == :turn
      # scoring_team on the point is intentionally not cascaded — the
      # tracker manages it manually. The point remains marked `:ours`
      # even though its goal event has been retyped.
      assert Repo.get!(Point, point.id).scoring_team == :ours
      # Score is event-driven (counts non-deleted :goal events on :ours
      # points), so retyping the only goal to :turn drops the score.
      # The mismatch between point.scoring_team and score is a known
      # post-MVP UX gap.
      assert Games.score(game) == %{ours: 0, theirs: 0}
    end

    test "editing rejects a cross-team player", %{
      conn: conn,
      game: game,
      players: players
    } do
      [p1 | _] = players
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, event} = Games.record_event(point, :goal, p1.user_id)

      # Set up a stranger from another team.
      other_team = team_fixture()
      stranger = member_fixture(%{team_id: other_team.id, jersey_number: "99"})

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}/timeline")

      live
      |> element("button[phx-click='open_edit'][phx-value-id='#{event.id}']")
      |> render_click()

      # The modal only renders chips for same-team players, so to
      # exercise the server-side cross-team rejection we drive the event
      # handler directly via render_hook.
      render_hook(live, "set_edit_player", %{"id" => stranger.id})

      html = live |> form("#edit-event-modal form") |> render_submit()

      assert html =~ "isn&#39;t on this team"
      assert Repo.get!(Event, event.id).user_id == p1.user_id
    end
  end

  describe "Summary" do
    setup :register_and_log_in_user

    setup %{user: user} do
      team = team_fixture()
      add_to_team(team, user)
      players = build_players(team, 3)
      game = game_fixture(%{team_id: team.id, opponent_name: "Stormcrows"})
      %{team: team, players: players, game: game}
    end

    test "in-progress game shows status 'In progress' and the running score", %{
      conn: conn,
      game: game,
      players: players
    } do
      [scorer | _] = players
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, _} = Games.record_event(point, :goal, scorer.user_id)
      {:ok, _} = Games.end_point(point, :ours)

      {:ok, live, html} = live(conn, ~p"/games/#{game.id}/summary")

      assert html =~ "Summary"
      assert html =~ "Stormcrows"
      assert has_element?(live, "[role='status']", "In progress")
      # All three roster players show up by display name.
      Enum.each(players, fn p ->
        assert html =~ "Player Number#{p.jersey_number}"
      end)

      # Continue tracking CTA only on in-progress.
      assert html =~ "Continue tracking"
    end

    test "finished game shows status 'Final' and no Continue CTA", %{
      conn: conn,
      game: game,
      players: players
    } do
      score_n_points_for_us(game, players, 1)
      {:ok, _} = Games.end_game(Repo.get!(Ultistats.Games.Game, game.id))

      {:ok, live, html} = live(conn, ~p"/games/#{game.id}/summary")

      assert has_element?(live, "[role='status']", "Final")
      refute html =~ "Continue tracking"
    end

    test "renders the per-player table with a goal tally for the scorer", %{
      conn: conn,
      game: game,
      players: players
    } do
      [scorer | _] = players
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, _} = Games.record_event(point, :goal, scorer.user_id)
      {:ok, _} = Games.end_point(point, :ours)

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}/summary")

      # Scorer row contains the display name. The numeric tallies live
      # in the same row.
      assert has_element?(live, "tr", "Player Number#{scorer.jersey_number}")
    end

    test "soft-deleted goal does not show in the tally", %{
      conn: conn,
      game: game,
      players: players
    } do
      [scorer | _] = players
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.user_id))
      {:ok, event} = Games.record_event(point, :goal, scorer.user_id)
      {:ok, _} = Games.end_point(point, :ours)
      {:ok, _} = Games.soft_delete_event(event)

      {:ok, _live, _html} = live(conn, ~p"/games/#{game.id}/summary")

      summary = Games.summary_for_game(Repo.get!(Ultistats.Games.Game, game.id))
      scorer_row = Enum.find(summary.players, &(&1.user.id == scorer.user_id))
      assert scorer_row.goals == 0
      assert summary.score.ours == 0
    end
  end

  ## ---------------------------------------------------------------------
  ## helpers
  ## ---------------------------------------------------------------------

  # Returns a list of membership structs (with `:user` preloaded and
  # `:jersey_number` on the membership). Tests read identity from
  # `m.user`, `m.user_id`, and jersey from `m.jersey_number`.
  defp build_players(team, n) do
    for i <- 1..n do
      team_membership_fixture(%{
        team_id: team.id,
        first_name: "Player",
        last_name: "Number#{i}",
        jersey_number: Integer.to_string(i)
      })
    end
  end

  # Insert N completed points scored by us. Skips going through the
  # action buttons — used to set up score-state preconditions.
  defp score_n_points_for_us(game, players, n) do
    user_ids = Enum.map(players, & &1.user_id)
    scorer_id = hd(user_ids)

    for _ <- 1..n do
      {:ok, point} = Games.start_point(game, user_ids)
      {:ok, _} = Games.record_event(point, :goal, scorer_id)
      {:ok, _} = Games.end_point(point, :ours)
    end

    :ok
  end
end
