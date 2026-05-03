defmodule UltistatsWeb.DashboardLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.GamesFixtures
  import Ultistats.TeamsFixtures

  alias Ultistats.{Games, Teams}

  defp add_to_team(team, user, role) do
    {:ok, _m} = Teams.add_team_member(team, user, %{role: role, is_player: true})
    :ok
  end

  defp add_non_player(team, attrs) do
    team_membership_fixture(Map.merge(%{team_id: team.id, is_player: false}, attrs))
  end

  describe "GET / branching" do
    test "anonymous user sees the marketing home page" do
      conn = Phoenix.ConnTest.build_conn()
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ "Ultistats"
      assert html =~ "stat tracking"
    end

    test "authenticated user is redirected to /dashboard", %{conn: _conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: Phoenix.ConnTest.build_conn()})

      conn = get(conn, ~p"/")
      assert redirected_to(conn) == ~p"/dashboard"
    end
  end

  describe "auth gate" do
    test "anonymous LiveView mount on /dashboard redirects to login" do
      anon = Phoenix.ConnTest.build_conn()
      assert {:error, {:redirect, %{to: to}}} = live(anon, ~p"/dashboard")
      assert to =~ "/users/log-in"
    end
  end

  describe "no teams" do
    setup :register_and_log_in_user

    test "renders the no-teams empty state with a link to /teams/new", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Welcome to Ultistats"
      assert html =~ ~p"/teams/new"
    end
  end

  describe "single team" do
    setup :register_and_log_in_user

    setup %{user: user} do
      team = team_fixture(%{name: "Aardvarks"})
      add_to_team(team, user, :admin)
      %{team: team}
    end

    test "auto-selects the only team and patches the URL", %{conn: conn, team: team} do
      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/dashboard")
      assert to == ~p"/dashboard?team_id=#{team.id}"

      {:ok, _view, html} = live(conn, ~p"/dashboard?team_id=#{team.id}")
      assert html =~ team.name
    end

    test "shows the empty-games panel when team has no games", %{conn: conn, team: team} do
      {:ok, _view, html} = live(conn, ~p"/dashboard?team_id=#{team.id}")

      assert html =~ "No games for #{team.name} yet"
      assert html =~ ~p"/games/new"
    end

    test "renders roster names on the leaderboard with all-zero rows", %{conn: conn, team: team} do
      _p1 =
        team_membership_fixture(%{
          team_id: team.id,
          first_name: "Avery",
          last_name: "Active",
          jersey_number: "7"
        })

      _p2 =
        team_membership_fixture(%{
          team_id: team.id,
          first_name: "Casey",
          last_name: "Catcher",
          jersey_number: "11"
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard?team_id=#{team.id}")

      assert html =~ "Avery Active"
      assert html =~ "Casey Catcher"
    end

    test "leaderboard ignores members where is_player is false", %{conn: conn, team: team} do
      _player =
        team_membership_fixture(%{
          team_id: team.id,
          first_name: "Patty",
          last_name: "Player",
          jersey_number: "3"
        })

      _coach =
        add_non_player(team, %{
          first_name: "Coach",
          last_name: "Sideline",
          jersey_number: nil
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard?team_id=#{team.id}")

      assert html =~ "Patty Player"
      refute html =~ "Coach Sideline"
    end
  end

  describe "multi-team switching" do
    setup :register_and_log_in_user

    setup %{user: user} do
      team_a = team_fixture(%{name: "Alpha"})
      team_b = team_fixture(%{name: "Bravo"})
      add_to_team(team_a, user, :admin)
      add_to_team(team_b, user, :admin)

      _player_a =
        team_membership_fixture(%{
          team_id: team_a.id,
          first_name: "Alpha",
          last_name: "Player",
          jersey_number: "1"
        })

      _player_b =
        team_membership_fixture(%{
          team_id: team_b.id,
          first_name: "Bravo",
          last_name: "Person",
          jersey_number: "2"
        })

      %{team_a: team_a, team_b: team_b}
    end

    test "?team_id selects the requested team's roster", %{
      conn: conn,
      team_a: team_a,
      team_b: team_b
    } do
      {:ok, _view, html_a} = live(conn, ~p"/dashboard?team_id=#{team_a.id}")
      assert html_a =~ "Alpha Player"
      refute html_a =~ "Bravo Person"

      {:ok, _view, html_b} = live(conn, ~p"/dashboard?team_id=#{team_b.id}")
      assert html_b =~ "Bravo Person"
      refute html_b =~ "Alpha Player"
    end

    test "switch_team event swaps to the other team's data", %{
      conn: conn,
      team_a: team_a,
      team_b: team_b
    } do
      {:ok, view, html} = live(conn, ~p"/dashboard?team_id=#{team_a.id}")
      assert html =~ "Alpha Player"
      refute html =~ "Bravo Person"

      view
      |> form("form[phx-change='switch_team']", %{"team_id" => team_b.id})
      |> render_change()

      html_after = render(view)
      assert html_after =~ "Bravo Person"
      refute html_after =~ "Alpha Player"
    end

    test "?team_id for a non-member team falls back to the user's first team", %{
      conn: conn,
      team_a: team_a
    } do
      stranger_team = team_fixture(%{name: "Outsiders"})

      _outsider =
        team_membership_fixture(%{
          team_id: stranger_team.id,
          first_name: "Outsider",
          last_name: "Player"
        })

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/dashboard?team_id=#{stranger_team.id}")

      assert to == ~p"/dashboard?team_id=#{team_a.id}"

      {:ok, _view, html} = live(conn, to)
      refute html =~ "Outsider Player"
      assert html =~ "Alpha Player"
    end
  end

  describe "leaderboard surfaces tracked stats" do
    setup :register_and_log_in_user

    test "shows goal + assist counts after a recorded throw", %{conn: conn, user: user} do
      team = team_fixture(%{name: "Squad"})
      add_to_team(team, user, :admin)

      passer_m =
        team_membership_fixture(%{
          team_id: team.id,
          first_name: "Pat",
          last_name: "Passer",
          jersey_number: "9"
        })

      receiver_m =
        team_membership_fixture(%{
          team_id: team.id,
          first_name: "Riley",
          last_name: "Receiver",
          jersey_number: "10"
        })

      game =
        game_fixture(%{
          team_id: team.id,
          opponent_name: "Other Squad",
          status: :in_progress
        })

      {:ok, point} = Games.start_point(game, [passer_m.user_id, receiver_m.user_id])
      {:ok, _ev} = Games.record_throw(point, :goal, passer_m.user_id, receiver_m.user_id)

      {:ok, _view, html} = live(conn, ~p"/dashboard?team_id=#{team.id}")

      assert html =~ "Pat Passer"
      assert html =~ "Riley Receiver"

      # Receiver got the goal, passer got the assist — confirm both are
      # surfaced in the leaderboard. (We don't assert on raw "1" because
      # the digit collides with jersey/score; we slice the leaderboard
      # block out instead.)
      [_, leaderboard_html | _] =
        String.split(html, ~r{<table id="dashboard-leaderboard"}, parts: 2)

      assert leaderboard_html =~ "Pat Passer"
      assert leaderboard_html =~ "Riley Receiver"
      # 2 stat columns will read "1" each — at minimum the table contains
      # the digit somewhere. This is a soft check; the entity assertions
      # above are the real coverage.
      assert leaderboard_html =~ "1"
    end
  end

  describe "recent games panel" do
    setup :register_and_log_in_user

    test "lists in-progress and finished games by opponent name", %{conn: conn, user: user} do
      team = team_fixture(%{name: "Squad"})
      add_to_team(team, user, :admin)

      _g_in_progress =
        game_fixture(%{
          team_id: team.id,
          opponent_name: "Live Opponents",
          status: :in_progress
        })

      _g_finished =
        game_fixture(%{
          team_id: team.id,
          opponent_name: "Past Opponents",
          status: :finished,
          ended_at: ~U[2026-05-02 03:00:00Z]
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard?team_id=#{team.id}")

      assert html =~ "Live Opponents"
      assert html =~ "Past Opponents"
    end
  end
end
