defmodule UltistatsWeb.LinePresetLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.TeamsFixtures

  alias Ultistats.Teams

  defp setup_team_with_roster(_) do
    team = team_fixture(%{name: "Home"})
    p1 = player_fixture(%{team_id: team.id, jersey_number: "7", name: "Avery"})
    p2 = player_fixture(%{team_id: team.id, jersey_number: "11", name: "Casey"})
    p3 = player_fixture(%{team_id: team.id, jersey_number: "23", name: "Drew"})

    %{team: team, players: [p1, p2, p3]}
  end

  describe "Index" do
    test "lists all line_presets", %{conn: conn} do
      team = team_fixture()
      {:ok, preset} = Teams.create_line_preset(%{name: "O-line", team_id: team.id})

      {:ok, _index_live, html} = live(conn, ~p"/line_presets")

      assert html =~ "Listing Line presets"
      assert html =~ preset.name
    end
  end

  describe "Show" do
    test "displays line_preset", %{conn: conn} do
      team = team_fixture()
      {:ok, preset} = Teams.create_line_preset(%{name: "O-line", team_id: team.id})

      {:ok, _show_live, html} = live(conn, ~p"/line_presets/#{preset}")

      assert html =~ "Line preset"
      assert html =~ preset.name
    end
  end

  describe "New form (with team_id)" do
    setup [:setup_team_with_roster]

    # Note: the canonical "create new line preset" flow is
    # /line_presets/new?team_id=ID (entered from the team show page).
    # The bare /line_presets/new flow is intentionally not covered —
    # see the PlayerLive test for the same convention.

    test "renders a chip for every player on the team", %{
      conn: conn,
      team: team,
      players: [p1, p2, p3]
    } do
      {:ok, _form_live, html} = live(conn, ~p"/line_presets/new?team_id=#{team.id}")

      assert html =~ "Roster (0 selected of 3)"
      assert html =~ p1.name
      assert html =~ p2.name
      assert html =~ p3.name
    end

    test "toggling a chip updates the selection counter", %{
      conn: conn,
      team: team,
      players: [p1 | _]
    } do
      {:ok, form_live, _html} = live(conn, ~p"/line_presets/new?team_id=#{team.id}")

      html =
        form_live
        |> element("button[phx-value-id='#{p1.id}']")
        |> render_click()

      assert html =~ "Roster (1 selected of 3)"

      html =
        form_live
        |> element("button[phx-value-id='#{p1.id}']")
        |> render_click()

      assert html =~ "Roster (0 selected of 3)"
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

      assert html =~ "Roster (2 selected of 3)"
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
  end
end
