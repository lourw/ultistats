defmodule UltistatsWeb.TeamJoinControllerTest do
  use UltistatsWeb.ConnCase

  import Ultistats.AccountsFixtures
  import Ultistats.TeamsFixtures

  alias Ultistats.Accounts
  alias Ultistats.Accounts.User
  alias Ultistats.Repo
  alias Ultistats.Teams

  defp stub_with_team(team, attrs \\ %{}) do
    {:ok, stub} =
      Accounts.create_stub_user(
        Map.merge(
          %{
            first_name: "Stub",
            last_name: "Friend",
            gender_role: :male_matching,
            position: :handler
          },
          attrs
        )
      )

    {:ok, m} = Teams.add_team_member(team, stub, %{role: :member, is_player: true})
    %{stub: stub, membership: m}
  end

  describe "GET /join/:token" do
    test "redirects to / with a flash on an invalid token", %{conn: conn} do
      conn = get(conn, ~p"/join/not-a-real-token")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end

    test "renders the log-in/register prompt and sets :user_return_to when unauthenticated",
         %{conn: conn} do
      team = team_fixture(%{name: "Wildcats"})
      token = Teams.generate_team_join_token(team)

      conn = get(conn, ~p"/join/#{token}")
      assert html_response(conn, 200)
      assert get_session(conn, :user_return_to) == ~p"/join/#{token}"
    end

    test "renders the picker with unclaimed stubs when authenticated", %{conn: conn} do
      team = team_fixture()
      %{membership: m1} = stub_with_team(team, %{first_name: "First", last_name: "Stub"})
      %{membership: m2} = stub_with_team(team, %{first_name: "Second", last_name: "Stub"})
      claimer = user_fixture()

      token = Teams.generate_team_join_token(team)

      conn =
        conn
        |> log_in_user(claimer)
        |> get(~p"/join/#{token}")

      assert html_response(conn, 200)
      # Both stubs are surfaced to the picker — assert via the context
      # that the underlying data flow is correct (per project memory:
      # don't assert on UI structure).
      stubs = Teams.list_unclaimed_stub_memberships_for_team(team)
      assert Enum.map(stubs, & &1.id) |> Enum.sort() == Enum.sort([m1.id, m2.id])
    end

    test "redirects to the team page when the user is already a member", %{conn: conn} do
      team = team_fixture()
      claimer = user_fixture()
      {:ok, _} = Teams.add_team_member(team, claimer, %{role: :member, is_player: true})

      token = Teams.generate_team_join_token(team)

      conn =
        conn
        |> log_in_user(claimer)
        |> get(~p"/join/#{token}")

      assert redirected_to(conn) == ~p"/teams/#{team.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "already on this team"
    end
  end

  describe "GET /join/:token/claim/:membership_id" do
    test "redirects unauthenticated users to log in with :user_return_to set", %{conn: conn} do
      team = team_fixture()
      %{membership: m} = stub_with_team(team)
      token = Teams.generate_team_join_token(team)

      conn = get(conn, ~p"/join/#{token}/claim/#{m.id}")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) == ~p"/join/#{token}"
    end

    test "renders the verify form when authenticated", %{conn: conn} do
      team = team_fixture()
      %{membership: m} = stub_with_team(team)
      claimer = user_fixture()

      token = Teams.generate_team_join_token(team)

      conn =
        conn
        |> log_in_user(claimer)
        |> get(~p"/join/#{token}/claim/#{m.id}")

      assert html_response(conn, 200)
    end

    test "redirects back to picker when membership is on a different team", %{conn: conn} do
      team = team_fixture(%{name: "Real"})
      other = team_fixture(%{name: "Other"})
      %{membership: foreign_m} = stub_with_team(other)
      claimer = user_fixture()

      token = Teams.generate_team_join_token(team)

      conn =
        conn
        |> log_in_user(claimer)
        |> get(~p"/join/#{token}/claim/#{foreign_m.id}")

      assert redirected_to(conn) == ~p"/join/#{token}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "isn't on this team"
    end

    test "redirects when the stub is already claimed", %{conn: conn} do
      team = team_fixture()
      %{stub: stub, membership: m} = stub_with_team(team)

      stub
      |> Ecto.Changeset.change(claimed_at: DateTime.utc_now(:second))
      |> Repo.update!()

      claimer = user_fixture()
      token = Teams.generate_team_join_token(team)

      conn =
        conn
        |> log_in_user(claimer)
        |> get(~p"/join/#{token}/claim/#{m.id}")

      assert redirected_to(conn) == ~p"/join/#{token}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already been claimed"
    end
  end

  describe "POST /join/:token/claim/:membership_id" do
    test "redirects unauthenticated users to log in with :user_return_to set", %{conn: conn} do
      team = team_fixture()
      %{membership: m} = stub_with_team(team)
      token = Teams.generate_team_join_token(team)

      conn =
        post(conn, ~p"/join/#{token}/claim/#{m.id}", %{
          "member" => %{
            "first_name" => "X",
            "last_name" => "Y",
            "gender_role" => "male_matching",
            "position" => "handler",
            "jersey_number" => "1"
          }
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) == ~p"/join/#{token}"
    end

    test "claims the stub, copies the verified profile to the claimer, and deletes the stub",
         %{conn: conn} do
      team = team_fixture()

      # Stub starts out with one set of profile fields; the verify form
      # carries different values that the user just edited. Assert the
      # claimer ends up with the EDITED values, not the stub's
      # originals.
      %{stub: stub, membership: m} =
        stub_with_team(team, %{
          first_name: "Stale",
          last_name: "Data",
          gender_role: :female_matching,
          position: :hybrid
        })

      claimer = user_fixture()
      token = Teams.generate_team_join_token(team)

      conn =
        conn
        |> log_in_user(claimer)
        |> post(~p"/join/#{token}/claim/#{m.id}", %{
          "member" => %{
            "first_name" => "Edited",
            "last_name" => "Name",
            "gender_role" => "male_matching",
            "position" => "handler",
            "jersey_number" => "77"
          }
        })

      assert redirected_to(conn) == ~p"/teams/#{team.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "You're on"

      assert Teams.user_member_of?(claimer, team)
      refute Repo.get(User, stub.id)

      reloaded = Accounts.get_user!(claimer.id)
      assert reloaded.first_name == "Edited"
      assert reloaded.last_name == "Name"
      assert reloaded.gender_role == :male_matching
      assert reloaded.position == :handler

      # The membership picked up the per-team override from the form.
      reloaded_m =
        Teams.get_team_membership_by_team_and_user(team, claimer)

      assert reloaded_m.jersey_number == "77"
      assert reloaded_m.position == :handler
    end

    test "re-renders the verify form on invalid params (no claim happens)",
         %{conn: conn} do
      team = team_fixture()
      %{stub: stub, membership: m} = stub_with_team(team)
      claimer = user_fixture()
      token = Teams.generate_team_join_token(team)

      conn =
        conn
        |> log_in_user(claimer)
        |> post(~p"/join/#{token}/claim/#{m.id}", %{
          "member" => %{
            "first_name" => "",
            "last_name" => "",
            "gender_role" => "",
            "position" => "",
            "jersey_number" => ""
          }
        })

      # Page re-renders (200), no claim happened.
      assert html_response(conn, 200)
      assert Repo.get(User, stub.id)
      refute Teams.user_member_of?(claimer, team)
    end

    test "redirects back to picker when membership is on a different team", %{conn: conn} do
      team = team_fixture(%{name: "Real"})
      other = team_fixture(%{name: "Other"})
      %{membership: foreign_m, stub: foreign_stub} = stub_with_team(other)
      claimer = user_fixture()

      token = Teams.generate_team_join_token(team)

      conn =
        conn
        |> log_in_user(claimer)
        |> post(~p"/join/#{token}/claim/#{foreign_m.id}", %{
          "member" => %{
            "first_name" => "X",
            "last_name" => "Y",
            "gender_role" => "male_matching",
            "position" => "handler",
            "jersey_number" => "1"
          }
        })

      assert redirected_to(conn) == ~p"/join/#{token}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "isn't on this team"

      # No mutation: the stub is still around and the claimer is on no
      # teams.
      assert Repo.get(User, foreign_stub.id)
      refute Teams.user_member_of?(claimer, team)
      refute Teams.user_member_of?(claimer, other)
    end

    test "redirects when the stub is already claimed", %{conn: conn} do
      team = team_fixture()
      %{stub: stub, membership: m} = stub_with_team(team)

      stub
      |> Ecto.Changeset.change(claimed_at: DateTime.utc_now(:second))
      |> Repo.update!()

      claimer = user_fixture()
      token = Teams.generate_team_join_token(team)

      conn =
        conn
        |> log_in_user(claimer)
        |> post(~p"/join/#{token}/claim/#{m.id}", %{
          "member" => %{
            "first_name" => "X",
            "last_name" => "Y",
            "gender_role" => "male_matching",
            "position" => "handler",
            "jersey_number" => "1"
          }
        })

      assert redirected_to(conn) == ~p"/join/#{token}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already been claimed"
    end

    test "redirects with error on an invalid token", %{conn: conn} do
      claimer = user_fixture()

      conn =
        conn
        |> log_in_user(claimer)
        |> post(~p"/join/not-a-token/claim/00000000-0000-0000-0000-000000000000", %{
          "member" => %{
            "first_name" => "X",
            "last_name" => "Y",
            "gender_role" => "male_matching",
            "position" => "handler",
            "jersey_number" => "1"
          }
        })

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end
  end

  describe "POST /join/:token/create" do
    test "creates a TeamMembership and updates the user's profile", %{conn: conn} do
      team = team_fixture(%{name: "Wildcats"})
      claimer = user_fixture()
      token = Teams.generate_team_join_token(team)

      before_count = length(Teams.list_team_members_for_team(team))

      conn =
        conn
        |> log_in_user(claimer)
        |> post(~p"/join/#{token}/create", %{
          "member" => %{
            "first_name" => "Real",
            "last_name" => "Player",
            "gender_role" => "female_matching",
            "position" => "cutter",
            "jersey_number" => "33"
          }
        })

      assert redirected_to(conn) == ~p"/teams/#{team.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome to"

      assert Teams.user_member_of?(claimer, team)
      assert length(Teams.list_team_members_for_team(team)) == before_count + 1

      reloaded = Accounts.get_user!(claimer.id)
      assert reloaded.first_name == "Real"
      assert reloaded.last_name == "Player"
      assert reloaded.gender_role == :female_matching
      assert reloaded.position == :cutter
    end

    test "re-renders the pick page with errors when params are invalid", %{conn: conn} do
      team = team_fixture()
      claimer = user_fixture()
      token = Teams.generate_team_join_token(team)

      before_count = length(Teams.list_team_members_for_team(team))

      conn =
        conn
        |> log_in_user(claimer)
        |> post(~p"/join/#{token}/create", %{
          "member" => %{
            "first_name" => "",
            "last_name" => "",
            "gender_role" => "",
            "position" => "",
            "jersey_number" => ""
          }
        })

      # Page re-renders (200), nothing was created, user is not a
      # member.
      assert html_response(conn, 200)
      assert length(Teams.list_team_members_for_team(team)) == before_count
      refute Teams.user_member_of?(claimer, team)
    end

    test "redirects unauthenticated users to log in with :user_return_to set", %{conn: conn} do
      team = team_fixture()
      token = Teams.generate_team_join_token(team)

      conn =
        post(conn, ~p"/join/#{token}/create", %{
          "member" => %{
            "first_name" => "X",
            "last_name" => "Y",
            "gender_role" => "male_matching",
            "position" => "handler",
            "jersey_number" => "1"
          }
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) == ~p"/join/#{token}"
    end
  end

  describe "register-then-join end-to-end" do
    test "a fresh user registers, lands on the join page, and joins as a new player",
         %{conn: conn} do
      team = team_fixture(%{name: "Wildcats"})
      token = Teams.generate_team_join_token(team)

      before_member_count = length(Teams.list_team_members_for_team(team))

      # 1. Visit the join page unauthenticated. The controller stashes
      #    `:user_return_to` so post-auth we'd come back here.
      anon_conn = get(conn, ~p"/join/#{token}")
      assert html_response(anon_conn, 200)
      assert get_session(anon_conn, :user_return_to) == ~p"/join/#{token}"

      email = unique_user_email()

      # 2. Register a fresh account from a fresh conn. Pre-stash
      #    :user_return_to in the session (the join controller's
      #    `show/2` does this in the real flow — we mimic it here on a
      #    fresh test conn). The registration controller preserves it
      #    and post-register redirects back to the join page.
      register_conn =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(%{user_return_to: ~p"/join/#{token}"})
        |> post(~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert get_session(register_conn, :user_token)
      assert redirected_to(register_conn) == ~p"/join/#{token}"
      user = Accounts.get_user_by_email(email)
      assert user

      # 3. Drive the join-create endpoint as the now-authed user. Use
      #    the existing test-helper to log in (which builds a fresh
      #    session-backed conn with this user's token) — equivalent in
      #    effect to the post-register session that the real flow
      #    leaves the browser in.
      conn =
        build_conn()
        |> log_in_user(user)
        |> post(~p"/join/#{token}/create", %{
          "member" => %{
            "first_name" => "Brand",
            "last_name" => "New",
            "gender_role" => "male_matching",
            "position" => "handler",
            "jersey_number" => "42"
          }
        })

      assert redirected_to(conn) == ~p"/teams/#{team.id}"

      # 4. Assert via the DB — entity state, not HTML.
      reloaded = Repo.get_by(User, email: email)
      assert reloaded
      assert reloaded.first_name == "Brand"
      assert reloaded.last_name == "New"
      assert reloaded.gender_role == :male_matching
      assert reloaded.position == :handler

      assert Teams.user_member_of?(reloaded, team)

      assert team.id in (Teams.list_teams_for_user(reloaded) |> Enum.map(& &1.id))

      assert length(Teams.list_team_members_for_team(team)) == before_member_count + 1
    end
  end
end
