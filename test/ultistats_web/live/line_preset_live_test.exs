defmodule UltistatsWeb.LinePresetLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.TeamsFixtures

  alias Ultistats.Teams
  alias Ultistats.Teams.Player

  defp setup_team_with_roster(_) do
    team = team_fixture(%{name: "Home"})

    p1 =
      player_fixture(%{
        team_id: team.id,
        jersey_number: "7",
        first_name: "Avery",
        last_name: "Adams"
      })

    p2 =
      player_fixture(%{
        team_id: team.id,
        jersey_number: "11",
        first_name: "Casey",
        last_name: "Cole"
      })

    p3 =
      player_fixture(%{
        team_id: team.id,
        jersey_number: "23",
        first_name: "Drew",
        last_name: "Davis"
      })

    %{team: team, players: [p1, p2, p3]}
  end

  describe "New form (with team_id)" do
    setup [:setup_team_with_roster]

    # Note: the canonical "create new line preset" flow is
    # /line_presets/new?team_id=ID (entered from the team show page).
    # The bare /line_presets/new flow is intentionally not covered —
    # see the PlayerLive test for the same convention.

    test "renders a row for every player on the team", %{
      conn: conn,
      team: team,
      players: [p1, p2, p3]
    } do
      {:ok, _form_live, html} = live(conn, ~p"/line_presets/new?team_id=#{team.id}")

      # Each player's name shows up in the picker.
      assert html =~ Player.display_name(p1)
      assert html =~ Player.display_name(p2)
      assert html =~ Player.display_name(p3)

      # Section starts with 0 selected of 3 (all 3 fixture players are female-matching by default).
      assert html =~ "0 of 3"
    end

    test "toggling a row updates the selection counter", %{
      conn: conn,
      team: team,
      players: [p1 | _]
    } do
      {:ok, form_live, _html} = live(conn, ~p"/line_presets/new?team_id=#{team.id}")

      html =
        form_live
        |> element("button[phx-value-id='#{p1.id}']")
        |> render_click()

      assert html =~ "1 of 3"

      html =
        form_live
        |> element("button[phx-value-id='#{p1.id}']")
        |> render_click()

      assert html =~ "0 of 3"
    end

    test "save persists the preset with selected players", %{
      conn: conn,
      team: team,
      players: [p1, p2, _p3]
    } do
      {:ok, form_live, _html} = live(conn, ~p"/line_presets/new?team_id=#{team.id}")

      form_live |> element("button[phx-value-id='#{p1.id}']") |> render_click()
      form_live |> element("button[phx-value-id='#{p2.id}']") |> render_click()

      assert {:ok, _index_live, _html} =
               form_live
               |> form("#line_preset-form", line_preset: %{name: "O-line A"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/line_presets")

      [preset] = Teams.list_line_presets_for_team(team)
      assert preset.name == "O-line A"
      assert preset.team_id == team.id
      assert Enum.map(preset.players, & &1.id) |> Enum.sort() == Enum.sort([p1.id, p2.id])
    end
  end

  describe "Edit form" do
    setup [:setup_team_with_roster]

    test "pre-selects the preset's existing players", %{
      conn: conn,
      team: team,
      players: [p1, p2, _p3]
    } do
      {:ok, preset} =
        Teams.create_line_preset(%{
          name: "Existing",
          team_id: team.id,
          player_ids: [p1.id, p2.id]
        })

      {:ok, _form_live, html} = live(conn, ~p"/line_presets/#{preset}/edit")

      # All 3 fixture players are female-matching by default.
      assert html =~ "2 of 3"
    end

    test "save replaces the player set", %{
      conn: conn,
      team: team,
      players: [p1, p2, p3]
    } do
      {:ok, preset} =
        Teams.create_line_preset(%{
          name: "Existing",
          team_id: team.id,
          player_ids: [p1.id, p2.id]
        })

      {:ok, form_live, _html} = live(conn, ~p"/line_presets/#{preset}/edit")

      # Deselect p1, select p3 → final set is {p2, p3}.
      form_live |> element("button[phx-value-id='#{p1.id}']") |> render_click()
      form_live |> element("button[phx-value-id='#{p3.id}']") |> render_click()

      assert {:ok, _index_live, _html} =
               form_live
               |> form("#line_preset-form", line_preset: %{name: "Existing"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/line_presets")

      reloaded = Teams.get_line_preset!(preset.id)
      assert Enum.map(reloaded.players, & &1.id) |> Enum.sort() == Enum.sort([p2.id, p3.id])
    end

    test "delete affordance on the edit form removes the preset", %{
      conn: conn,
      team: team,
      players: [p1, p2, _p3]
    } do
      {:ok, preset} =
        Teams.create_line_preset(%{
          name: "Going away",
          team_id: team.id,
          player_ids: [p1.id, p2.id]
        })

      {:ok, edit_live, _html} = live(conn, ~p"/line_presets/#{preset}/edit")

      assert has_element?(edit_live, "#delete-line-preset")

      edit_live
      |> element("#delete-line-preset")
      |> render_click()

      assert_redirect(edit_live, ~p"/line_presets")

      assert_raise Ecto.NoResultsError, fn ->
        Ultistats.Teams.get_line_preset!(preset.id)
      end
    end
  end
end
