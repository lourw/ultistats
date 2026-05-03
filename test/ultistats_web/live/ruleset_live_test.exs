defmodule UltistatsWeb.RulesetLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.GamesFixtures
  import Ultistats.TeamsFixtures

  alias Ultistats.Games

  describe "Index" do
    test "lists templates only — :game_instance rows are not surfaced", %{conn: conn} do
      team = team_fixture(%{name: "Home"})
      template = ruleset_fixture(%{team_id: team.id, name: "Hat League"})
      _instance = ruleset_fixture(%{team_id: team.id, kind: :game_instance, name: nil})

      {:ok, _live, html} = live(conn, ~p"/rulesets")

      assert html =~ template.name
      # No anonymous "(per-game instance)" entries make it into the list.
      refute html =~ "(per-game instance)"
    end

    test "shows the team name on each row", %{conn: conn} do
      team = team_fixture(%{name: "Aardvarks"})
      _r = ruleset_fixture(%{team_id: team.id, name: "Hat League"})

      {:ok, _live, html} = live(conn, ~p"/rulesets")

      assert html =~ "Aardvarks"
      assert html =~ "Hat League"
    end

    test "Edit link routes to the form", %{conn: conn} do
      team = team_fixture()
      ruleset = ruleset_fixture(%{team_id: team.id, name: "Hat League"})

      {:ok, live, _html} = live(conn, ~p"/rulesets")

      assert live
             |> element("a[href='/rulesets/#{ruleset.id}/edit']", "Edit")
             |> has_element?()
    end

    test "Delete removes the ruleset when no games reference it", %{conn: conn} do
      team = team_fixture()
      ruleset = ruleset_fixture(%{team_id: team.id, name: "Hat League"})

      {:ok, live, _html} = live(conn, ~p"/rulesets")

      live
      |> element("#ruleset-#{ruleset.id} a", "Delete")
      |> render_click()

      assert Games.list_rulesets_for_team(team) == []
      refute render(live) =~ "Hat League"
    end

    test "Delete falls back to archive when games reference the ruleset", %{conn: conn} do
      team = team_fixture()
      ruleset = ruleset_fixture(%{team_id: team.id, name: "Hat League"})
      _game = game_fixture(%{team_id: team.id, ruleset_id: ruleset.id})

      {:ok, live, _html} = live(conn, ~p"/rulesets")

      html =
        live
        |> element("#ruleset-#{ruleset.id} a", "Delete")
        |> render_click()

      assert html =~ "archived"
      # Row gone from the index (filter excludes archived templates).
      refute html =~ "Hat League"
      # But the row still exists in the DB.
      assert Games.get_ruleset!(ruleset.id).archived_at
    end
  end

  describe "New form" do
    test "happy-path: creates a ruleset and redirects to the index", %{conn: conn} do
      team = team_fixture()

      {:ok, live, _html} = live(conn, ~p"/rulesets/new?team_id=#{team.id}")

      assert {:ok, _index_live, _html} =
               live
               |> form("#ruleset-form",
                 ruleset: %{
                   name: "Hat League",
                   score_cap: "13",
                   halftime_target: "7",
                   timeouts_per_half: "1",
                   gender_ratio_rule: "alternating",
                   default_starting_ratio: "four_men_three_women"
                 }
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/rulesets")

      [ruleset] = Games.list_rulesets_for_team(team)
      assert ruleset.name == "Hat League"
      assert ruleset.score_cap == 13
      assert ruleset.halftime_target == 7
      assert ruleset.timeouts_per_half == 1
      assert ruleset.gender_ratio_rule == :alternating
    end

    test "without team_id redirects to /teams with a flash", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/rulesets/new")

      assert to == ~p"/teams"
      assert flash["error"] =~ "Pick a team first"
    end
  end

  describe "Edit form" do
    test "happy-path: updates an existing ruleset", %{conn: conn} do
      team = team_fixture()

      ruleset =
        ruleset_fixture(%{
          team_id: team.id,
          name: "Hat League",
          score_cap: 13,
          halftime_target: 7,
          timeouts_per_half: 1,
          gender_ratio_rule: :alternating
        })

      {:ok, live, _html} = live(conn, ~p"/rulesets/#{ruleset.id}/edit")

      assert {:ok, _index_live, _html} =
               live
               |> form("#ruleset-form",
                 ruleset: %{
                   name: "Hat League",
                   score_cap: "11",
                   halftime_target: "6",
                   timeouts_per_half: "1",
                   gender_ratio_rule: "alternating",
                   default_starting_ratio: "four_men_three_women"
                 }
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/rulesets")

      reloaded = Games.get_ruleset!(ruleset.id)
      assert reloaded.score_cap == 11
      assert reloaded.halftime_target == 6
    end
  end
end
