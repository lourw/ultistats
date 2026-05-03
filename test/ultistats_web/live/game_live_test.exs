defmodule UltistatsWeb.GameLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.GamesFixtures
  import Ultistats.TeamsFixtures

  alias Ultistats.Games

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
      # Default first_pull is :ours — the option is selected.
      assert html =~ ~r/<option[^>]*selected[^>]*value="ours">We pull</
      assert html =~ "USAU standard format"
    end

    test "pre-selects the team when ?team_id=... is provided", %{conn: conn} do
      _other = team_fixture(%{name: "Other"})
      target = team_fixture(%{name: "Target"})

      {:ok, _live, html} = live(conn, ~p"/games/new?team_id=#{target.id}")

      # With more than one team we render a select; the chosen team_id is selected.
      assert html =~ ~r/<option[^>]*selected[^>]*value="#{target.id}">Target</
    end

    test "ignores a bogus team_id query param without 404", %{conn: conn} do
      _team = team_fixture()

      {:ok, _live, html} =
        live(conn, ~p"/games/new?team_id=00000000-0000-0000-0000-000000000000")

      # No crash, form still renders.
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

  describe "Show" do
    test "renders opponent name and 'Game in progress' copy", %{conn: conn} do
      game = game_fixture(%{opponent_name: "Stormcrows"})

      {:ok, _live, html} = live(conn, ~p"/games/#{game.id}")

      assert html =~ "Game vs Stormcrows"
      assert html =~ "Game in progress"
      assert html =~ "Live tracking UI lands in the next ticket"
    end

    test "renders Back to team link with the game's team_id", %{conn: conn} do
      game = game_fixture()

      {:ok, live, _html} = live(conn, ~p"/games/#{game.id}")

      assert has_element?(live, "a[href='#{~p"/teams/#{game.team_id}"}']", "Back to team")
    end
  end
end
