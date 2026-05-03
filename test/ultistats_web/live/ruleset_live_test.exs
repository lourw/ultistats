defmodule UltistatsWeb.RulesetLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.GamesFixtures
  import Ultistats.TeamsFixtures

  alias Ultistats.{Games, Teams}

  defp add_to_team(team, user, role \\ :admin) do
    {:ok, _m} =
      Teams.add_team_member(team, user, %{role: role, is_player: true})

    :ok
  end

  describe "Index" do
    setup :register_and_log_in_user

    test "lists templates only — :game_instance rows are not surfaced", %{
      conn: conn,
      user: user
    } do
      team = team_fixture(%{name: "Home"})
      add_to_team(team, user)
      template = ruleset_fixture(%{team_id: team.id, name: "Hat League"})
      _instance = ruleset_fixture(%{team_id: team.id, kind: :game_instance, name: nil})

      {:ok, _live, html} = live(conn, ~p"/rulesets")

      assert html =~ template.name
      refute html =~ "(per-game instance)"
    end

    test "shows the team name on each row", %{conn: conn, user: user} do
      team = team_fixture(%{name: "Aardvarks"})
      add_to_team(team, user)
      _r = ruleset_fixture(%{team_id: team.id, name: "Hat League"})

      {:ok, _live, html} = live(conn, ~p"/rulesets")

      assert html =~ "Aardvarks"
      assert html =~ "Hat League"
    end

    test "Edit link routes to the form for admins", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user)
      ruleset = ruleset_fixture(%{team_id: team.id, name: "Hat League"})

      {:ok, live, _html} = live(conn, ~p"/rulesets")

      assert live
             |> element("a[href='/rulesets/#{ruleset.id}/edit']")
             |> has_element?()
    end

    test "non-admin sees no Edit link", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user, :member)
      ruleset = ruleset_fixture(%{team_id: team.id, name: "Hat League"})

      {:ok, live, _html} = live(conn, ~p"/rulesets")

      refute live
             |> element("a[href='/rulesets/#{ruleset.id}/edit']")
             |> has_element?()
    end

    test "rulesets across teams the user is NOT on are excluded", %{conn: conn, user: user} do
      mine = team_fixture(%{name: "Mine"})
      other = team_fixture(%{name: "Other"})
      add_to_team(mine, user)
      _own = ruleset_fixture(%{team_id: mine.id, name: "Mine ruleset"})
      _stranger = ruleset_fixture(%{team_id: other.id, name: "Stranger ruleset"})

      {:ok, _live, html} = live(conn, ~p"/rulesets")

      assert html =~ "Mine ruleset"
      refute html =~ "Stranger ruleset"
    end

    test "Delete from the show page removes the ruleset when no games reference it", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      add_to_team(team, user)
      ruleset = ruleset_fixture(%{team_id: team.id, name: "Hat League"})

      {:ok, live, _html} = live(conn, ~p"/rulesets/#{ruleset.id}")

      assert {:ok, _games_live, _html} =
               live
               |> element("button", "Delete")
               |> render_click()
               |> follow_redirect(conn, ~p"/games")

      assert Games.list_rulesets_for_team(team) == []
    end

    test "Delete falls back to archive when games reference the ruleset", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      add_to_team(team, user)
      ruleset = ruleset_fixture(%{team_id: team.id, name: "Hat League"})
      _game = game_fixture(%{team_id: team.id, ruleset_id: ruleset.id})

      {:ok, live, _html} = live(conn, ~p"/rulesets/#{ruleset.id}")

      assert {:ok, _games_live, html} =
               live
               |> element("button", "Delete")
               |> render_click()
               |> follow_redirect(conn, ~p"/games")

      assert html =~ "Archived because games reference it."
      assert Games.get_ruleset!(ruleset.id).archived_at
    end
  end

  describe "New form — admin" do
    setup :register_and_log_in_user

    test "happy-path: creates a ruleset and redirects to the index", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user)

      {:ok, live, _html} = live(conn, ~p"/rulesets/new?team_id=#{team.id}")

      assert {:ok, _index_live, _html} =
               live
               |> form("#ruleset-form",
                 ruleset: %{
                   name: "Hat League",
                   score_cap: "13",
                   halftime_target: "7",
                   timeouts_per_half: "1",
                   line_size: "7",
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
      assert ruleset.line_size == 7
      assert ruleset.gender_ratio_rule == :alternating
    end

    test "without team_id redirects to /teams with a flash", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/rulesets/new")

      assert to == ~p"/teams"
      assert flash["error"] =~ "Pick a team first"
    end
  end

  describe "New form — non-admin" do
    setup :register_and_log_in_user

    test "non-admin members are redirected from /rulesets/new?team_id=...", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      add_to_team(team, user, :member)

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/rulesets/new?team_id=#{team.id}")

      assert to == ~p"/teams/#{team.id}"
      assert flash["error"] =~ "permission"
    end
  end

  describe "Edit form — admin" do
    setup :register_and_log_in_user

    test "happy-path: updates an existing ruleset", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user)

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
                   line_size: "7",
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

  describe "Edit form — non-admin" do
    setup :register_and_log_in_user

    test "non-admin members are redirected from /rulesets/:id/edit", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      add_to_team(team, user, :member)
      ruleset = ruleset_fixture(%{team_id: team.id})

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/rulesets/#{ruleset.id}/edit")

      assert to == ~p"/teams/#{team.id}"
      assert flash["error"] =~ "permission"
    end
  end
end
