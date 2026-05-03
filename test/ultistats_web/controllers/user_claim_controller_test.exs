defmodule UltistatsWeb.UserClaimControllerTest do
  use UltistatsWeb.ConnCase

  import Ultistats.AccountsFixtures
  import Ultistats.TeamsFixtures

  alias Ultistats.Accounts
  alias Ultistats.Teams

  defp stub_with_team(team) do
    {:ok, stub} =
      Accounts.create_stub_user(%{
        first_name: "Stub",
        last_name: "Friend",
        gender_role: :male_matching,
        position: :handler
      })

    {:ok, _m} = Teams.add_team_member(team, stub, %{role: :member, is_player: true})
    stub
  end

  describe "GET /claim/:token" do
    test "redirects to / with a flash on an invalid token", %{conn: conn} do
      conn = get(conn, ~p"/claim/not-a-real-token")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end

    test "renders the log-in/register prompt when unauthenticated", %{conn: conn} do
      team = team_fixture()
      stub = stub_with_team(team)
      token = Accounts.generate_stub_claim_token(stub)

      conn = get(conn, ~p"/claim/#{token}")
      html = html_response(conn, 200)

      assert html =~ "Claim profile"
      assert html =~ "Stub Friend"
      assert html =~ ~p"/users/log-in"
      assert html =~ ~p"/users/register"
      assert get_session(conn, :user_return_to) == ~p"/claim/#{token}"
    end

    test "renders the confirmation page when authenticated", %{conn: conn} do
      team = team_fixture()
      stub = stub_with_team(team)
      claimer = user_fixture()
      token = Accounts.generate_stub_claim_token(stub)

      conn =
        conn
        |> log_in_user(claimer)
        |> get(~p"/claim/#{token}")

      html = html_response(conn, 200)
      assert html =~ "Claim profile"
      assert html =~ "Stub Friend"
      assert html =~ "Claim Stub Friend's profile"
    end
  end

  describe "POST /claim/:token" do
    test "redirects unauthenticated users to log in", %{conn: conn} do
      team = team_fixture()
      stub = stub_with_team(team)
      token = Accounts.generate_stub_claim_token(stub)

      conn = post(conn, ~p"/claim/#{token}", %{})

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) == ~p"/claim/#{token}"
    end

    test "claims the stub and redirects to the team page when authenticated", %{conn: conn} do
      team = team_fixture()
      stub = stub_with_team(team)
      claimer = user_fixture()
      token = Accounts.generate_stub_claim_token(stub)

      conn =
        conn
        |> log_in_user(claimer)
        |> post(~p"/claim/#{token}", %{})

      assert redirected_to(conn) == ~p"/teams/#{team.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Profile linked"
      assert Teams.user_member_of?(claimer, team)
      refute Ultistats.Repo.get(Ultistats.Accounts.User, stub.id)
    end

    test "redirects with error on an invalid token", %{conn: conn} do
      claimer = user_fixture()

      conn =
        conn
        |> log_in_user(claimer)
        |> post(~p"/claim/not-a-token", %{})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end

    test "flashes a conflict message when the claimer is already on a stub team", %{conn: conn} do
      team = team_fixture()
      stub = stub_with_team(team)
      claimer = user_fixture()
      {:ok, _m} = Teams.add_team_member(team, claimer, %{role: :member, is_player: true})

      token = Accounts.generate_stub_claim_token(stub)

      conn =
        conn
        |> log_in_user(claimer)
        |> post(~p"/claim/#{token}", %{})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "ask an admin"
    end
  end
end
