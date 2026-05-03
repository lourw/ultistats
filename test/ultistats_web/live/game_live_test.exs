defmodule UltistatsWeb.GameLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.GamesFixtures
  import Ultistats.TeamsFixtures

  alias Ultistats.Games
  alias Ultistats.Repo
  alias Ultistats.Games.{Event, Point}
  alias Ultistats.Teams.Player

  describe "Start" do
    test "renders the empty state when there are no teams", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/games/new")

      assert html =~ "Create a team first"
      assert html =~ ~p"/teams/new"
      refute html =~ ~s(id="game-form")
    end

    test "renders the form with first_pull defaulted to :ours", %{conn: conn} do
      _team = team_fixture()

      {:ok, live, html} = live(conn, ~p"/games/new")

      assert html =~ "Start a game"
      assert has_element?(live, "#game-form")
      assert html =~ ~r/<option[^>]*selected[^>]*value="ours">We pull</
      assert html =~ "USAU standard format"
    end

    test "pre-selects the team when ?team_id=... is provided", %{conn: conn} do
      _other = team_fixture(%{name: "Other"})
      target = team_fixture(%{name: "Target"})

      {:ok, _live, html} = live(conn, ~p"/games/new?team_id=#{target.id}")

      assert html =~ ~r/<option[^>]*selected[^>]*value="#{target.id}">Target</
    end

    test "ignores a bogus team_id query param without 404", %{conn: conn} do
      _team = team_fixture()

      {:ok, _live, html} =
        live(conn, ~p"/games/new?team_id=00000000-0000-0000-0000-000000000000")

      assert html =~ "Start a game"
    end

    test "validates required fields — blank opponent shows error", %{conn: conn} do
      team = team_fixture()

      {:ok, live, _html} = live(conn, ~p"/games/new")

      html =
        live
        |> form("#game-form",
          game: %{"team_id" => team.id, "opponent_name" => "", "first_pull" => "ours"}
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "rejects an opponent name longer than 80 chars", %{conn: conn} do
      team = team_fixture()
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

    test "successful submit creates a game and navigates to /games/:id", %{conn: conn} do
      team = team_fixture()

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
  end

  describe "Show — between points" do
    setup do
      team = team_fixture()
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
      assert has_element?(live, "button[phx-value-id='#{first.id}']", Player.display_name(first))

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
      |> element("button[phx-value-id='#{p1.id}']")
      |> render_click()

      live
      |> element("button[phx-value-id='#{p2.id}']")
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
      ids = Enum.map(preset_players, & &1.id)

      preset = line_preset_fixture(%{team_id: team.id, name: "O-line A", player_ids: ids})

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
        live |> element("button[phx-value-id='#{p.id}']") |> render_click()
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
    setup do
      team = team_fixture()
      players = build_players(team, 7)
      game = game_fixture(%{team_id: team.id})

      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))

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
      |> element("#player-picker-modal button[phx-value-id='#{scorer.id}']")
      |> render_click()

      html = render(live)
      assert html =~ "Who got the assist?"
      assert html =~ "Skip — no assist"

      live |> element("button[phx-click='skip_assist']") |> render_click()

      reloaded = Repo.get!(Point, point.id)
      assert reloaded.scoring_team == :ours

      events = Games.events_for_point(reloaded)
      assert Enum.any?(events, &(&1.type == :goal and &1.player_id == scorer.id))
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
      |> element("#player-picker-modal button[phx-value-id='#{scorer.id}']")
      |> render_click()

      live
      |> element("#player-picker-modal button[phx-value-id='#{assister.id}']")
      |> render_click()

      reloaded = Repo.get!(Point, point.id)
      assert reloaded.scoring_team == :ours

      events = Games.events_for_point(reloaded)
      assert Enum.any?(events, &(&1.type == :goal and &1.player_id == scorer.id))
      assert Enum.any?(events, &(&1.type == :assist and &1.player_id == assister.id))
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
      |> element("#player-picker-modal button[phx-value-id='#{blocker.id}']")
      |> render_click()

      reloaded = Repo.get!(Point, point.id)
      assert is_nil(reloaded.scoring_team)

      [event] = Repo.all(Event)
      assert event.type == :block
      assert event.player_id == blocker.id

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
    setup do
      team = team_fixture()
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

    test "hard cap auto-ends the game and renders terminal state", %{
      conn: conn,
      game: game,
      players: players,
      team: _team
    } do
      # Score 14 already, then play one more on the live view to trip the
      # hard cap via the in-LiveView code path.
      score_n_points_for_us(game, players, 14)

      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      scorer = hd(players)
      live |> element("button[phx-value-kind='goal']") |> render_click()

      live
      |> element("#player-picker-modal button[phx-value-id='#{scorer.id}']")
      |> render_click()

      live |> element("button[phx-click='skip_assist']") |> render_click()

      reloaded = Repo.get!(Ultistats.Games.Game, game.id)
      assert reloaded.status == :finished
      assert reloaded.ended_at

      html = render(live)
      assert html =~ "Game finished"
      assert html =~ "Final score:"
      # Make sure we don't keep rendering the action bar.
      refute html =~ ~s(phx-click="start_point")

      # silence unused
      _ = point
    end

    test "mounting a finished game renders the terminal state directly", %{
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

      {:ok, _live, html} = live(conn, ~p"/games/#{game.id}")

      assert html =~ "Game finished"
      assert html =~ "15"
    end
  end

  ## ---------------------------------------------------------------------
  ## helpers
  ## ---------------------------------------------------------------------

  defp build_players(team, n) do
    for i <- 1..n do
      player_fixture(%{
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
    player_ids = Enum.map(players, & &1.id)

    for _ <- 1..n do
      {:ok, point} = Games.start_point(game, player_ids)
      {:ok, _} = Games.end_point(point, :ours)
    end

    :ok
  end
end
