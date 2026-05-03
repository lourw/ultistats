defmodule UltistatsWeb.PlayerLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.TeamsFixtures

  alias Ultistats.Teams
  alias Ultistats.Teams.Player

  defp create_player(_) do
    player = player_fixture()

    %{player: player, team_id: player.team_id}
  end

  defp update_attrs(team_id) do
    %{
      first_name: "Some",
      last_name: "Updated",
      jersey_number: "42",
      gender_role: "male_matching",
      team_id: team_id
    }
  end

  # gender_role intentionally omitted — radio inputs reject empty values, and
  # blank first/last is enough to trigger the "can't be blank" error path.
  @invalid_attrs %{first_name: nil, last_name: nil, jersey_number: nil}

  describe "Index" do
    setup [:create_player]

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
      assert html =~ "Some Updated"
    end

    test "deletes player in listing", %{conn: conn, player: player} do
      {:ok, index_live, _html} = live(conn, ~p"/players")

      assert index_live |> element("#players-#{player.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#players-#{player.id}")
    end
  end

  describe "Show" do
    setup [:create_player]

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
      assert html =~ "Some Updated"
    end

    test "delete affordance on the edit form removes the player", %{conn: conn, player: player} do
      {:ok, edit_live, _html} = live(conn, ~p"/players/#{player}/edit")

      assert has_element?(edit_live, "#delete-player")

      edit_live
      |> element("#delete-player")
      |> render_click()

      assert_redirect(edit_live)

      assert_raise Ecto.NoResultsError, fn ->
        Ultistats.Teams.get_player!(player.id)
      end
    end
  end

  describe "Bulk add (/players/new?team_id=ID)" do
    test "add_row appends a fourth row", %{conn: conn} do
      team = team_fixture()
      {:ok, view, _html} = live(conn, ~p"/players/new?team_id=#{team.id}")

      view |> element("button", "Add row") |> render_click()

      assert has_element?(view, "#player-row-3")
    end

    test "remove_row drops a row but won't go below one", %{conn: conn} do
      team = team_fixture()
      {:ok, view, _html} = live(conn, ~p"/players/new?team_id=#{team.id}")

      # Drop rows 0 and 1 — leaves row 2 alone.
      view |> element("#player-row-0 button[aria-label='Remove row']") |> render_click()
      refute has_element?(view, "#player-row-0")

      view |> element("#player-row-1 button[aria-label='Remove row']") |> render_click()
      refute has_element?(view, "#player-row-1")

      assert has_element?(view, "#player-row-2")

      # Last remaining row's remove button is disabled — clicking is a no-op.
      assert view
             |> element("#player-row-2 button[aria-label='Remove row']")
             |> render() =~ "disabled"
    end

    test "set_gender flips the selected radio", %{conn: conn} do
      team = team_fixture()
      {:ok, view, _html} = live(conn, ~p"/players/new?team_id=#{team.id}")

      # Initially no radio is checked on row 0.
      row0_html = view |> element("#player-row-0") |> render()
      refute row0_html =~ ~s(checked)

      # Click the female-matching radio on row 0.
      view
      |> element("#player-row-0 input[value='female_matching']")
      |> render_click()

      row0_html = view |> element("#player-row-0") |> render()

      assert row0_html =~ ~r/<input[^>]*value="female_matching"[^>]*\schecked\b/
    end

    test "save_all with two valid rows persists two players", %{conn: conn} do
      team = team_fixture()
      {:ok, view, _html} = live(conn, ~p"/players/new?team_id=#{team.id}")

      # Set gender on rows 0 and 1.
      view
      |> element("#player-row-0 input[value='female_matching']")
      |> render_click()

      view
      |> element("#player-row-1 input[value='male_matching']")
      |> render_click()

      # Submit names + jersey via the form. Row 2 stays blank — it should be dropped.
      params = %{
        "row" => %{
          "0" => %{"first_name" => "Alice", "last_name" => "Aaron", "jersey_number" => "1"},
          "1" => %{"first_name" => "Bob", "last_name" => "Brown", "jersey_number" => ""},
          "2" => %{"first_name" => "", "last_name" => "", "jersey_number" => ""}
        }
      }

      {:ok, _view, _html} =
        view
        |> form("#bulk-player-form", params)
        |> render_submit()
        |> follow_redirect(conn, ~p"/teams/#{team}")

      players = Teams.list_players_for_team(team)
      assert length(players) == 2

      names = Enum.map(players, &Player.display_name/1) |> Enum.sort()
      assert names == ["Alice Aaron", "Bob Brown"]
    end

    test "save_all with all blank rows flashes error and doesn't navigate", %{conn: conn} do
      team = team_fixture()
      {:ok, view, _html} = live(conn, ~p"/players/new?team_id=#{team.id}")

      params = %{
        "row" => %{
          "0" => %{"first_name" => "", "last_name" => "", "jersey_number" => ""},
          "1" => %{"first_name" => "", "last_name" => "", "jersey_number" => ""},
          "2" => %{"first_name" => "", "last_name" => "", "jersey_number" => ""}
        }
      }

      html = view |> form("#bulk-player-form", params) |> render_submit()

      assert html =~ "Add at least one player"
      assert Teams.list_players_for_team(team) == []
    end

    test "save_all with row missing gender_role surfaces inline error and rolls back", %{
      conn: conn
    } do
      team = team_fixture()
      {:ok, view, _html} = live(conn, ~p"/players/new?team_id=#{team.id}")

      # Row 0 gets names + gender. Row 1 gets names but no gender.
      view
      |> element("#player-row-0 input[value='female_matching']")
      |> render_click()

      params = %{
        "row" => %{
          "0" => %{"first_name" => "Alice", "last_name" => "Aaron", "jersey_number" => "1"},
          "1" => %{"first_name" => "Bob", "last_name" => "Brown", "jersey_number" => ""},
          "2" => %{"first_name" => "", "last_name" => "", "jersey_number" => ""}
        }
      }

      html = view |> form("#bulk-player-form", params) |> render_submit()

      assert html =~ "can&#39;t be blank"
      # Multi rolled back — neither player persisted.
      assert Teams.list_players_for_team(team) == []
    end

    test "save_all persists with nil jersey_number when omitted", %{conn: conn} do
      team = team_fixture()
      {:ok, view, _html} = live(conn, ~p"/players/new?team_id=#{team.id}")

      view
      |> element("#player-row-0 input[value='female_matching']")
      |> render_click()

      params = %{
        "row" => %{
          "0" => %{"first_name" => "Jersey", "last_name" => "Less", "jersey_number" => ""},
          "1" => %{"first_name" => "", "last_name" => "", "jersey_number" => ""},
          "2" => %{"first_name" => "", "last_name" => "", "jersey_number" => ""}
        }
      }

      {:ok, _view, _html} =
        view
        |> form("#bulk-player-form", params)
        |> render_submit()
        |> follow_redirect(conn, ~p"/teams/#{team}")

      [player] = Teams.list_players_for_team(team)
      assert player.first_name == "Jersey"
      assert player.last_name == "Less"
      assert player.jersey_number == nil
    end
  end

  describe "Edit form gender radios" do
    test "tapping the other gender radio updates form state", %{conn: conn} do
      player = player_fixture(%{gender_role: :female_matching})
      {:ok, view, _html} = live(conn, ~p"/players/#{player}/edit")

      # Tap male-matching.
      view |> element("input[value='male_matching']") |> render_click()

      html = render(view)

      assert html =~ ~r/<input[^>]*value="male_matching"[^>]*\schecked\b/
    end

    test "saving with the new gender_role persists", %{conn: conn} do
      player = player_fixture(%{gender_role: :female_matching})
      {:ok, view, _html} = live(conn, ~p"/players/#{player}/edit?return_to=show")

      view |> element("input[value='male_matching']") |> render_click()

      assert {:ok, _show_live, _html} =
               view
               |> form("#player-form",
                 player: %{
                   first_name: player.first_name,
                   last_name: player.last_name,
                   jersey_number: player.jersey_number,
                   gender_role: "male_matching",
                   team_id: player.team_id
                 }
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/players/#{player}")

      assert Teams.get_player!(player.id).gender_role == :male_matching
    end
  end
end
