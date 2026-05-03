defmodule UltistatsWeb.TeamLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.TeamsFixtures

  @create_attrs %{name: "some name"}
  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: nil}

  defp create_team(_) do
    team = team_fixture()
    %{team: team}
  end

  describe "Index" do
    test "renders empty state with link to /teams/new when there are no teams", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/teams")

      assert html =~ "Teams"
      assert html =~ "No teams yet"
      assert html =~ ~p"/teams/new"
    end

    test "renders list rows with player count, male/female counts, and game record", %{conn: conn} do
      team = team_fixture(%{name: "Aardvarks"})
      _f = player_fixture(%{team_id: team.id, gender_role: :female_matching, jersey_number: "1"})
      _m = player_fixture(%{team_id: team.id, gender_role: :male_matching, jersey_number: "2"})

      {:ok, index_live, html} = live(conn, ~p"/teams")

      assert html =~ team.name
      # Player counts.
      assert html =~ "2 players"
      # Male first, then female.
      assert html =~ "♂ 1"
      assert html =~ "♀ 1"
      male_idx = :binary.match(html, "♂ 1") |> elem(0)
      female_idx = :binary.match(html, "♀ 1") |> elem(0)
      assert male_idx < female_idx
      # No games yet — record shows the empty-record copy.
      assert html =~ "No games yet"

      # The whole row is a link to the show page.
      assert has_element?(index_live, "#team-#{team.id} a", team.name)
    end

    test "navigates to the new-team form", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/teams")

      assert {:ok, form_live, _html} =
               index_live
               |> element("a", "New team")
               |> render_click()
               |> follow_redirect(conn, ~p"/teams/new")

      assert render(form_live) =~ "New team"
    end

    test "creating a team from the form returns to the index and shows the new row", %{conn: conn} do
      {:ok, form_live, _html} = live(conn, ~p"/teams/new")

      assert form_live
             |> form("#team-form", team: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#team-form", team: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/teams")

      html = render(index_live)
      assert html =~ "Team created successfully"
      assert html =~ "some name"
    end
  end

  describe "Show" do
    setup [:create_team]

    test "renders the team name as the heading (without 'Team ' prefix)", %{
      conn: conn,
      team: team
    } do
      {:ok, _show_live, html} = live(conn, ~p"/teams/#{team}")

      assert html =~ team.name
      # Generator-default heading and subtitle are gone.
      refute html =~ "Show Team"
      refute html =~ "This is a team record from your database"
    end

    test "no longer renders the generator <.list> Name row", %{conn: conn, team: team} do
      {:ok, _show_live, html} = live(conn, ~p"/teams/#{team}")

      # The default scaffold rendered a <.list> with an item titled "Name".
      # Confirm that's been removed.
      refute html =~ ~r/<dt[^>]*>\s*Name\s*<\/dt>/
    end

    test "exposes a delete affordance and clicking it deletes the team", %{conn: conn, team: team} do
      {:ok, show_live, _html} = live(conn, ~p"/teams/#{team}")

      assert has_element?(show_live, "#delete-team")

      assert show_live
             |> element("#delete-team")
             |> render_click()

      assert_redirect(show_live, ~p"/teams")

      assert_raise Ecto.NoResultsError, fn -> Ultistats.Teams.get_team!(team.id) end
    end

    test "updates team and returns to show", %{conn: conn, team: team} do
      {:ok, show_live, _html} = live(conn, ~p"/teams/#{team}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit team")
               |> render_click()
               |> follow_redirect(conn, ~p"/teams/#{team}/edit?return_to=show")

      assert render(form_live) =~ "Edit #{team.name}"

      assert form_live
             |> form("#team-form", team: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#team-form", team: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/teams/#{team}")

      html = render(show_live)
      assert html =~ "Team updated successfully"
      assert html =~ "some updated name"
    end
  end

  describe "Form" do
    setup [:create_team]

    test "subtitle filler is gone on the new page", %{conn: conn} do
      {:ok, _form_live, html} = live(conn, ~p"/teams/new")

      refute html =~ "Use this form"
      assert html =~ "New team"
    end

    test "subtitle filler is gone on the edit page", %{conn: conn, team: team} do
      {:ok, _form_live, html} = live(conn, ~p"/teams/#{team}/edit")

      refute html =~ "Use this form"
      assert html =~ "Edit #{team.name}"
    end

    test "save button reads 'Save' (not 'Save Team')", %{conn: conn} do
      {:ok, _form_live, html} = live(conn, ~p"/teams/new")

      assert html =~ ~r/<button[^>]*>\s*Save\s*</
      refute html =~ "Save Team"
    end
  end
end
