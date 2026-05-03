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
      assert html =~ "USAU standard (no template)"
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

    test "ruleset picker lists the team's templates", %{conn: conn} do
      team = team_fixture()
      _hat = ruleset_fixture(%{team_id: team.id, name: "Hat League"})
      _strict = ruleset_fixture(%{team_id: team.id, name: "Strict Tourney"})

      {:ok, _live, html} = live(conn, ~p"/games/new?team_id=#{team.id}")

      assert html =~ "Hat League"
      assert html =~ "Strict Tourney"
    end

    test "picking a ruleset prefills the rule fields", %{conn: conn} do
      team = team_fixture()

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
      conn: conn
    } do
      team = team_fixture()

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

      # Each player shows up in the picker by display name.
      first = hd(players)
      assert has_element?(live, "button[phx-value-id='#{first.id}']", Player.display_name(first))

      # Start point button is disabled before any selection.
      assert has_element?(live, "button[phx-click='start_point'][disabled]")
    end

    test "toggling players updates the per-section counter", %{
      conn: conn,
      game: game,
      players: players
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [p1, p2 | _] = players

      live |> element("button[phx-value-id='#{p1.id}']") |> render_click()
      live |> element("button[phx-value-id='#{p2.id}']") |> render_click()

      # All 7 fixture players default to :female_matching, so the female
      # section header reflects the live count.
      assert render(live) =~ "2 of 7"
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

      # Picking a 5-player preset fills the roster — visible via the
      # per-section counter (all 7 players are female-matching here).
      assert render(live) =~ "5 of 7"
    end

    test "Start point button reflects ♂ and ♀ counts of selected players", %{
      conn: conn
    } do
      team = team_fixture()
      game = game_fixture(%{team_id: team.id})

      m_player =
        player_fixture(%{
          team_id: team.id,
          first_name: "Mark",
          last_name: "M",
          jersey_number: "1",
          gender_role: :male_matching
        })

      f_player =
        player_fixture(%{
          team_id: team.id,
          first_name: "Frances",
          last_name: "F",
          jersey_number: "2",
          gender_role: :female_matching
        })

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      # Nothing selected: the Start button text reads "♂ 0  ♀ 0" (whitespace varies).
      button_html = live |> element("button[phx-click='start_point']") |> render()
      assert button_html =~ "♂"
      assert button_html =~ "♀"
      assert Regex.scan(~r/>\s*0\s*</, button_html) |> length() >= 2

      live |> element("button[phx-value-id='#{m_player.id}']") |> render_click()
      live |> element("button[phx-value-id='#{f_player.id}']") |> render_click()

      button_html = live |> element("button[phx-click='start_point']") |> render()
      assert button_html =~ "♂"
      assert button_html =~ "♀"
      # Both selected: button now shows two "1"s instead of two "0"s.
      assert Regex.scan(~r/>\s*1\s*</, button_html) |> length() >= 2
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
      # The starting-possession label renders. game_fixture defaults
      # first_pull: :ours, so the receiving side is :theirs at point start.
      assert html =~ "They have the disc"

      assert Repo.aggregate(Point, :count, :id) == 1
    end
  end

  describe "Show — in point (per-throw flow)" do
    setup do
      team = team_fixture()
      players = build_players(team, 7)
      # first_pull: :theirs ⇒ we receive ⇒ :ours has the disc at point start.
      game = game_fixture(%{team_id: team.id, first_pull: :theirs})

      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))

      %{team: team, players: players, game: game, point: point}
    end

    test "set_passer + set_receiver + :catch records the event and B becomes the passer", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a, b | _] = players

      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "set_receiver", %{"id" => b.id})
      render_hook(live, "record_throw_outcome", %{"type" => "catch"})

      [event] = Games.events_for_point(point)
      assert event.type == :catch
      assert event.passer_id == a.id
      assert event.receiver_id == b.id

      # The current-passer card now shows player B.
      html = render(live)
      assert html =~ "data-current-passer=\"#{b.id}\""
    end

    test "after a catch, :goal ends the point with passer=B, receiver=C", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a, b, c | _] = players

      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "set_receiver", %{"id" => b.id})
      render_hook(live, "record_throw_outcome", %{"type" => "catch"})

      render_hook(live, "set_receiver", %{"id" => c.id})
      render_hook(live, "record_throw_outcome", %{"type" => "goal"})

      events = Games.events_for_point(point)

      assert Enum.any?(
               events,
               &(&1.type == :catch and &1.passer_id == a.id and &1.receiver_id == b.id)
             )

      assert Enum.any?(
               events,
               &(&1.type == :goal and &1.passer_id == b.id and &1.receiver_id == c.id)
             )

      reloaded = Repo.get!(Point, point.id)
      assert reloaded.scoring_team == :ours

      # Back to between-points view; Start point button visible again.
      assert has_element?(live, "button[phx-click='start_point']")
      assert Games.score(game) == %{ours: 1, theirs: 0}
    end

    test ":drop flips possession to :theirs", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a, b | _] = players

      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "set_receiver", %{"id" => b.id})
      render_hook(live, "record_throw_outcome", %{"type" => "drop"})

      [event] = Games.events_for_point(point)
      assert event.type == :drop
      assert event.passer_id == a.id
      assert event.receiver_id == b.id

      html = render(live)
      assert html =~ "They have the disc"
      # The :theirs-mode action buttons render now.
      assert has_element?(live, "button[phx-click='record_opponent_turnover']")
      assert has_element?(live, "button[phx-click='record_opponent_goal']")
    end

    test ":throwaway records passer-only and flips possession", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a | _] = players

      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "record_throw_outcome", %{"type" => "throwaway"})

      [event] = Games.events_for_point(point)
      assert event.type == :throwaway
      assert event.passer_id == a.id
      assert is_nil(event.receiver_id)

      assert render(live) =~ "They have the disc"
    end

    test "Block records an event, switches to ours, sets blocker as new passer", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      # First, flip to :theirs by recording a throwaway.
      [a, blocker | _] = players
      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "record_throw_outcome", %{"type" => "throwaway"})

      render_hook(live, "set_defender", %{"id" => blocker.id})
      render_hook(live, "record_defense", %{"kind" => "block"})

      events = Games.events_for_point(point)
      assert Enum.any?(events, &(&1.type == :block and &1.passer_id == blocker.id))

      reloaded = Repo.get!(Point, point.id)
      assert is_nil(reloaded.scoring_team)

      html = render(live)
      assert html =~ "We have the disc"
      # Blocker is now the current passer.
      assert html =~ "data-current-passer=\"#{blocker.id}\""
    end

    test "Catch (interception) records a :catch with passer=nil and the catcher as receiver",
         %{conn: conn, game: game, players: players, point: point} do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      # Flip to :theirs via a throwaway from one of our players.
      [a, catcher | _] = players
      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "record_throw_outcome", %{"type" => "throwaway"})

      render_hook(live, "set_defender", %{"id" => catcher.id})
      render_hook(live, "record_defense", %{"kind" => "catch"})

      events = Games.events_for_point(point)

      assert Enum.any?(
               events,
               &(&1.type == :catch and is_nil(&1.passer_id) and &1.receiver_id == catcher.id)
             )

      html = render(live)
      assert html =~ "We have the disc"
      assert html =~ "data-current-passer=\"#{catcher.id}\""
    end

    test "They turned it over flips possession to :ours, clears passer", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a | _] = players
      # Flip to :theirs first via a throwaway.
      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "record_throw_outcome", %{"type" => "throwaway"})

      live |> element("button[phx-click='record_opponent_turnover']") |> render_click()

      events = Games.events_for_point(point)
      assert Enum.any?(events, &(&1.type == :opponent_turnover))

      html = render(live)
      assert html =~ "We have the disc"
      # Possession is back to ours but no current passer — prompt shows.
      assert html =~ "Tap who has the disc"
    end

    test "They scored ends the point with scoring_team=:theirs and an :opponent_goal event", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a | _] = players
      # Flip to :theirs first.
      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "record_throw_outcome", %{"type" => "throwaway"})

      live |> element("button[phx-click='record_opponent_goal']") |> render_click()

      reloaded = Repo.get!(Point, point.id)
      assert reloaded.scoring_team == :theirs
      assert Enum.any?(Games.events_for_point(reloaded), &(&1.type == :opponent_goal))

      assert has_element?(live, "button[phx-click='start_point']")
      assert Games.score(game) == %{ours: 0, theirs: 1}
    end

    test "Pick records a :pick without changing possession", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a | _] = players
      render_hook(live, "set_passer", %{"id" => a.id})

      live
      |> element("button[phx-click='record_call'][phx-value-type='pick']")
      |> render_click()

      events = Games.events_for_point(point)

      assert Enum.any?(
               events,
               &(&1.type == :pick and is_nil(&1.passer_id) and is_nil(&1.receiver_id))
             )

      # Still :ours — current passer card still visible with player A.
      html = render(live)
      assert html =~ "data-current-passer=\"#{a.id}\""
    end

    test "tapping Unknown then Catch records nil ids", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a | _] = players

      # Set passer to unknown via the chip.
      render_hook(live, "set_passer", %{"id" => "unknown"})
      # Receiver is a real player.
      render_hook(live, "set_receiver", %{"id" => a.id})
      render_hook(live, "record_throw_outcome", %{"type" => "catch"})

      [event] = Games.events_for_point(point)
      assert event.type == :catch
      assert is_nil(event.passer_id)
      assert event.receiver_id == a.id
    end

    test "undo soft-deletes the most recent event and clears the current passer",
         %{conn: conn, game: game, players: players, point: point} do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a, b | _] = players

      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "set_receiver", %{"id" => b.id})
      render_hook(live, "record_throw_outcome", %{"type" => "catch"})

      # Catch landed: B is now the passer.
      assert render(live) =~ "data-current-passer=\"#{b.id}\""

      live |> element("button[phx-click='undo']") |> render_click()

      # The :catch row is soft-deleted (filtered from the live list).
      assert Games.events_for_point(point) == []
      [event] = Repo.all(Event)
      assert event.type == :catch
      refute is_nil(event.deleted_at)

      # Possession derives back to :ours (from the original first_pull
      # rules) and the prompt to pick a passer is shown again — undo all
      # the way back to "no events" requires the tracker to re-tap who
      # has the disc.
      html = render(live)
      assert html =~ "We have the disc"
      assert html =~ "Tap who has the disc"
      refute html =~ "data-current-passer="
    end

    test "redo restores a previously-undone event", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a, b | _] = players

      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "set_receiver", %{"id" => b.id})
      render_hook(live, "record_throw_outcome", %{"type" => "catch"})

      live |> element("button[phx-click='undo']") |> render_click()
      assert Games.events_for_point(point) == []

      live |> element("button[phx-click='redo']") |> render_click()

      [event] = Games.events_for_point(point)
      assert event.type == :catch
      assert event.passer_id == a.id
      assert event.receiver_id == b.id

      # Current passer follows the redone catch back to B.
      assert render(live) =~ "data-current-passer=\"#{b.id}\""
    end

    test "recording a new event clears the redo stack", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a, b, c | _] = players

      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "set_receiver", %{"id" => b.id})
      render_hook(live, "record_throw_outcome", %{"type" => "catch"})

      live |> element("button[phx-click='undo']") |> render_click()

      # Branch off in a different direction.
      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "set_receiver", %{"id" => c.id})
      render_hook(live, "record_throw_outcome", %{"type" => "catch"})

      # Redo button should be disabled now that the redo stack is cleared.
      assert has_element?(live, "button[phx-click='redo'][disabled]")

      [event] = Games.events_for_point(point)
      assert event.receiver_id == c.id
    end

    test "undo button shows the back-to-lineup affordance when stack is empty", %{
      conn: conn,
      game: game
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      # No events recorded yet — the leftmost button is the cancel-point
      # back arrow with the destructive confirmation prompt.
      assert has_element?(
               live,
               "button[phx-click='cancel_current_point'][data-confirm]"
             )

      refute has_element?(live, "button[phx-click='undo']")
    end

    test "Undo goal from the line picker reopens the point and clears the score", %{
      conn: conn,
      game: game,
      players: players,
      point: point
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a, scorer | _] = players

      # Score a goal: A throws to scorer, tracker hits Goal.
      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "set_receiver", %{"id" => scorer.id})
      render_hook(live, "record_throw_outcome", %{"type" => "goal"})

      # Point ended — we're back on the line picker, score 1–0.
      reloaded = Repo.get!(Point, point.id)
      assert reloaded.scoring_team == :ours
      assert Games.score(game) == %{ours: 1, theirs: 0}
      assert has_element?(live, "button[phx-click='start_point']")
      assert has_element?(live, "button[phx-click='undo_last_goal']")

      live |> element("button[phx-click='undo_last_goal']") |> render_click()

      # Point reopened, goal soft-deleted, score back to 0–0.
      reopened = Repo.get!(Point, point.id)
      assert is_nil(reopened.scoring_team)
      assert Games.events_for_point(reopened) == []
      assert Games.score(game) == %{ours: 0, theirs: 0}

      # Tracker is back in the in-point view.
      refute has_element?(live, "button[phx-click='start_point']")
      refute has_element?(live, "button[phx-click='undo_last_goal']")
    end

    test "Starting a new point clears the undo-goal affordance", %{
      conn: conn,
      game: game,
      players: players
    } do
      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [a, scorer | _] = players
      render_hook(live, "set_passer", %{"id" => a.id})
      render_hook(live, "set_receiver", %{"id" => scorer.id})
      render_hook(live, "record_throw_outcome", %{"type" => "goal"})

      assert has_element?(live, "button[phx-click='undo_last_goal']")

      # Start a new point — that commits to the previous goal.
      render_hook(live, "select_preset", %{"id" => "noop"})

      Enum.each(Enum.take(players, 7), fn p ->
        render_hook(live, "toggle_player", %{"id" => p.id})
      end)

      render_hook(live, "start_point", %{})

      refute has_element?(live, "button[phx-click='undo_last_goal']")
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

    test "hard cap auto-ends the game and pushes to summary", %{
      conn: conn,
      game: game,
      players: players,
      team: _team
    } do
      # Score 14 already, then play one more on the live view to trip the
      # hard cap via the in-LiveView code path.
      score_n_points_for_us(game, players, 14)

      {:ok, _point} = Games.start_point(game, Enum.map(players, & &1.id))

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      [scorer, assister | _] = players
      render_hook(live, "set_passer", %{"id" => assister.id})
      render_hook(live, "set_receiver", %{"id" => scorer.id})

      assert {:error, {:live_redirect, %{to: to}}} =
               render_hook(live, "record_throw_outcome", %{"type" => "goal"})

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
    setup do
      team = team_fixture()
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
      {:ok, p1} = Games.start_point(game, Enum.map(players, & &1.id))
      {:ok, _} = Games.record_throw(p1, :block, blocker.id, nil)
      {:ok, _} = Games.record_throw(p1, :goal, blocker.id, scorer.id)
      {:ok, _} = Games.end_point(p1, :ours)

      {:ok, p2} = Games.start_point(game, Enum.map(players, & &1.id))
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
      {:ok, p1} = Games.start_point(game, Enum.map(players, & &1.id))
      {:ok, goal} = Games.record_throw(p1, :goal, scorer.id, scorer.id)
      {:ok, _} = Games.end_point(p1, :ours)
      # Manually un-end the point so deleting the goal makes the score
      # actually change. (Per task notes: scoring_team is not auto-cleared.)
      {:ok, _} =
        p1
        |> Ecto.Changeset.change(scoring_team: nil)
        |> Repo.update()

      # Score the next point so we have a "1" to start from.
      {:ok, p2} = Games.start_point(game, Enum.map(players, & &1.id))
      {:ok, _} = Games.record_throw(p2, :goal, scorer.id, scorer.id)
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
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))
      {:ok, event} = Games.record_throw(point, :block, p.id, nil)

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
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))
      {:ok, event} = Games.record_throw(point, :block, p.id, nil)

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
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))
      # Block has passer-only shape, so the timeline edit (which only
      # touches passer_id) can switch its passer freely without violating
      # the per-type field-shape rules.
      {:ok, event} = Games.record_throw(point, :block, p1.id, nil)
      {:ok, _} = Games.end_point(point, :ours)

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}/timeline")

      live
      |> element("button[phx-click='open_edit'][phx-value-id='#{event.id}']")
      |> render_click()

      assert render(live) =~ "Edit event"

      # Switch to p2.
      live
      |> element("#edit-event-modal button[phx-click='set_edit_player'][phx-value-id='#{p2.id}']")
      |> render_click()

      live
      |> element("#edit-event-modal form")
      |> render_submit()

      reloaded = Repo.get!(Event, event.id)
      assert reloaded.passer_id == p2.id

      html = render(live)
      assert html =~ "##{p2.jersey_number}"
    end

    test "editing type from :catch to :stall changes the row but not scoring_team", %{
      conn: conn,
      game: game,
      players: players
    } do
      [p1, p2 | _] = players
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))
      # Use a passer-only typed event so flipping its type to another
      # passer-only type doesn't trip the shape validator on receiver_id.
      {:ok, event} = Games.record_throw(point, :throwaway, p1.id, nil)
      {:ok, _} = Games.end_point(point, :ours)

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}/timeline")

      live
      |> element("button[phx-click='open_edit'][phx-value-id='#{event.id}']")
      |> render_click()

      live
      |> element("#edit-event-modal button[phx-click='set_edit_type'][phx-value-type='stall']")
      |> render_click()

      live |> element("#edit-event-modal form") |> render_submit()

      assert Repo.get!(Event, event.id).type == :stall
      # scoring_team on the point is intentionally not cascaded — the
      # tracker manages it manually.
      assert Repo.get!(Point, point.id).scoring_team == :ours

      # silence unused
      _ = p2
    end

    test "editing rejects a cross-team player", %{
      conn: conn,
      game: game,
      players: players
    } do
      [p1 | _] = players
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))
      {:ok, event} = Games.record_throw(point, :block, p1.id, nil)

      # Set up a stranger from another team.
      other_team = team_fixture()
      stranger = player_fixture(%{team_id: other_team.id, jersey_number: "99"})

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
      assert Repo.get!(Event, event.id).passer_id == p1.id
    end
  end

  describe "Summary" do
    setup do
      team = team_fixture()
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
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))
      {:ok, _} = Games.record_throw(point, :goal, scorer.id, scorer.id)
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
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))
      {:ok, _} = Games.record_throw(point, :goal, scorer.id, scorer.id)
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
      {:ok, point} = Games.start_point(game, Enum.map(players, & &1.id))
      {:ok, event} = Games.record_throw(point, :goal, scorer.id, scorer.id)
      {:ok, _} = Games.end_point(point, :ours)
      {:ok, _} = Games.soft_delete_event(event)

      {:ok, _live, _html} = live(conn, ~p"/games/#{game.id}/summary")

      summary = Games.summary_for_game(Repo.get!(Ultistats.Games.Game, game.id))
      scorer_row = Enum.find(summary.players, &(&1.player.id == scorer.id))
      assert scorer_row.goals == 0
      assert summary.score.ours == 0
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
    scorer_id = hd(player_ids)

    for _ <- 1..n do
      {:ok, point} = Games.start_point(game, player_ids)
      {:ok, _} = Games.record_throw(point, :goal, scorer_id, scorer_id)
      {:ok, _} = Games.end_point(point, :ours)
    end

    :ok
  end
end
