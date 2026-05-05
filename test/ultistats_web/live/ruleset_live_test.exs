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

  describe "Show — delete" do
    setup :register_and_log_in_user

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
               |> element("button[aria-label='Delete ruleset']")
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
               |> element("button[aria-label='Delete ruleset']")
               |> render_click()
               |> follow_redirect(conn, ~p"/games")

      assert html =~ "Archived because games reference it."
      assert Games.get_ruleset!(ruleset.id).archived_at
    end
  end

  describe "New form — admin" do
    setup :register_and_log_in_user

    test "happy-path: creates a ruleset and redirects to the team page", %{
      conn: conn,
      user: user
    } do
      team = team_fixture(%{division: :mixed})
      add_to_team(team, user)

      {:ok, live, _html} = live(conn, ~p"/rulesets/new?team_id=#{team.id}")

      # Default division is :open; switch to :mixed so the gender_ratio fields render.
      live
      |> form("#ruleset-form", ruleset: %{division: "mixed"})
      |> render_change()

      assert {:ok, _team_live, _html} =
               live
               |> form("#ruleset-form",
                 ruleset: %{
                   name: "Hat League",
                   score_cap: "13",
                   halftime_target: "7",
                   timeouts_per_half: "1",
                   line_size: "7",
                   division: "mixed",
                   gender_ratio_rule: "alternating",
                   starting_male_count: "4",
                   starting_female_count: "3"
                 }
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/teams/#{team.id}")

      [ruleset] = Games.list_rulesets_for_team(team)
      assert ruleset.name == "Hat League"
      assert ruleset.score_cap == 13
      assert ruleset.halftime_target == 7
      assert ruleset.timeouts_per_half == 1
      assert ruleset.line_size == 7
      assert ruleset.gender_ratio_rule == :alternating
      assert ruleset.starting_male_count == 4
      assert ruleset.starting_female_count == 3
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
          division: :mixed,
          gender_ratio_rule: :alternating
        })

      {:ok, live, _html} = live(conn, ~p"/rulesets/#{ruleset.id}/edit")

      assert {:ok, _team_live, _html} =
               live
               |> form("#ruleset-form",
                 ruleset: %{
                   name: "Hat League",
                   score_cap: "11",
                   halftime_target: "6",
                   timeouts_per_half: "1",
                   line_size: "7",
                   gender_ratio_rule: "alternating",
                   starting_male_count: "4",
                   starting_female_count: "3"
                 }
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/teams/#{team.id}")

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
