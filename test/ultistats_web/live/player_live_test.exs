defmodule UltistatsWeb.PlayerLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.TeamsFixtures

  defp create_player(_) do
    player = player_fixture()

    %{player: player, team_id: player.team_id}
  end

  defp create_attrs(team_id) do
    %{
      name: "some name",
      jersey_number: "7",
      gender_role: "female_matching",
      team_id: team_id
    }
  end

  defp update_attrs(team_id) do
    %{
      name: "some updated name",
      jersey_number: "42",
      gender_role: "male_matching",
      team_id: team_id
    }
  end

  @invalid_attrs %{name: nil, jersey_number: nil, gender_role: nil}

  describe "Index" do
    setup [:create_player]

    test "lists all players", %{conn: conn, player: player} do
      {:ok, _index_live, html} = live(conn, ~p"/players")

      assert html =~ "Listing Players"
      assert html =~ player.name
    end

    # Note: the canonical "create new player" flow is /players/new?team_id=ID
    # (entered from the team show page). The "Form prefills team_id from query
    # string" describe block below covers it. The bare /players/new flow without
    # team_id is intentionally not supported in MVP — see Teams show page.

    test "updates player in listing", %{conn: conn, player: player, team_id: team_id} do
      {:ok, index_live, _html} = live(conn, ~p"/players")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#players-#{player.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/players/#{player}/edit")

      assert render(form_live) =~ "Edit Player"

      assert form_live
             |> form("#player-form", player: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#player-form", player: update_attrs(team_id))
               |> render_submit()
               |> follow_redirect(conn, ~p"/players")

      html = render(index_live)
      assert html =~ "Player updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes player in listing", %{conn: conn, player: player} do
      {:ok, index_live, _html} = live(conn, ~p"/players")

      assert index_live |> element("#players-#{player.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#players-#{player.id}")
    end
  end

  describe "Show" do
    setup [:create_player]

    test "displays player", %{conn: conn, player: player} do
      {:ok, _show_live, html} = live(conn, ~p"/players/#{player}")

      assert html =~ "Show Player"
      assert html =~ player.name
    end

    test "updates player and returns to show", %{conn: conn, player: player, team_id: team_id} do
      {:ok, show_live, _html} = live(conn, ~p"/players/#{player}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/players/#{player}/edit?return_to=show")

      assert render(form_live) =~ "Edit Player"

      assert form_live
             |> form("#player-form", player: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#player-form", player: update_attrs(team_id))
               |> render_submit()
               |> follow_redirect(conn, ~p"/players/#{player}")

      html = render(show_live)
      assert html =~ "Player updated successfully"
      assert html =~ "some updated name"
    end
  end

  describe "Form prefills team_id from query string" do
    test "creating from /players/new?team_id=ID submits with that team", %{conn: conn} do
      team = team_fixture()

      {:ok, form_live, _html} = live(conn, ~p"/players/new?team_id=#{team.id}")

      attrs = %{
        name: "Roster Person",
        jersey_number: "00",
        gender_role: "female_matching"
      }

      assert {:ok, _index_live, html} =
               form_live
               |> form("#player-form", player: attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/players")

      assert html =~ "Roster Person"
    end
  end
end
