defmodule UltistatsWeb.MemberLiveTest do
  use UltistatsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ultistats.TeamsFixtures

  alias Ultistats.Accounts.User
  alias Ultistats.Repo
  alias Ultistats.Teams
  alias Ultistats.Teams.TeamMembership

  defp add_to_team(team, user, role) do
    {:ok, _m} =
      Teams.add_team_member(team, user, %{role: role, is_player: true})

    :ok
  end

  describe "Index" do
    setup :register_and_log_in_user

    test "renders empty-state when the user is on no teams", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/members")

      assert html =~ "Listing Members"
      assert html =~ "No members yet"
    end

    test "lists memberships only for teams the user belongs to", %{conn: conn, user: user} do
      home = team_fixture(%{name: "Home"})
      away = team_fixture(%{name: "Away"})
      add_to_team(home, user, :admin)

      _m1 =
        team_membership_fixture(%{
          team_id: home.id,
          first_name: "Alice",
          last_name: "Aaron",
          jersey_number: "1"
        })

      _m2 =
        team_membership_fixture(%{
          team_id: away.id,
          first_name: "Bob",
          last_name: "Brown",
          jersey_number: "2"
        })

      {:ok, _view, html} = live(conn, ~p"/members")

      assert html =~ "Alice Aaron"
      refute html =~ "Bob Brown"
      assert html =~ "Home"
      refute html =~ "Away"
    end
  end

  describe "Show — admin" do
    setup :register_and_log_in_user

    test "renders the membership identity and fields", %{conn: conn, user: user} do
      team = team_fixture(%{name: "Surge"})
      add_to_team(team, user, :admin)

      m =
        team_membership_fixture(%{
          team_id: team.id,
          first_name: "Casey",
          last_name: "Cole",
          jersey_number: "23",
          gender_role: :male_matching,
          position: :handler,
          role: :admin,
          is_player: true
        })

      {:ok, _view, html} = live(conn, ~p"/members/#{m.id}")

      assert html =~ "Casey Cole"
      assert html =~ "Surge"
      assert html =~ "23"
      assert html =~ "Male-matching"
      assert html =~ "Handler"
      assert html =~ "Admin"
      assert html =~ "Yes"
    end

    test "Delete removes the membership and redirects to /members", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user, :admin)
      m = team_membership_fixture(%{team_id: team.id})

      {:ok, view, _html} = live(conn, ~p"/members/#{m.id}")

      view |> element("#delete-member") |> render_click()
      assert_redirect(view, ~p"/members")

      assert_raise Ecto.NoResultsError, fn -> Teams.get_team_membership!(m.id) end
    end
  end

  describe "Show — non-admin member" do
    setup :register_and_log_in_user

    test "hides Edit and Delete affordances for non-admins", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user, :member)
      m = team_membership_fixture(%{team_id: team.id, first_name: "Casey", last_name: "Cole"})

      {:ok, _view, html} = live(conn, ~p"/members/#{m.id}")

      refute html =~ ~s|id="delete-member"|
      refute html =~ "Edit"
    end

    test "non-member cannot view a member of a team they don't belong to", %{conn: conn} do
      team = team_fixture()
      m = team_membership_fixture(%{team_id: team.id})

      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/members/#{m.id}")
      assert to == ~p"/members"
    end
  end

  describe "Bulk add (/members/new?team_id=ID)" do
    setup :register_and_log_in_user

    test "add_row appends a second row", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user, :admin)

      {:ok, view, _html} = live(conn, ~p"/members/new?team_id=#{team.id}")

      view |> element("button", "Add row") |> render_click()

      assert has_element?(view, "#member-row-1")
    end

    test "save_all with two valid rows persists two memberships and stub users", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      add_to_team(team, user, :admin)

      {:ok, view, _html} = live(conn, ~p"/members/new?team_id=#{team.id}")

      view |> element("button", "Add row") |> render_click()

      view
      |> element("#member-row-0 input[value='female_matching']")
      |> render_click()

      view
      |> element("#member-row-1 input[value='male_matching']")
      |> render_click()

      params = %{
        "row" => %{
          "0" => %{
            "first_name" => "Alice",
            "last_name" => "Aaron",
            "jersey_number" => "1",
            "is_player" => "true"
          },
          "1" => %{
            "first_name" => "Bob",
            "last_name" => "Brown",
            "jersey_number" => "",
            "is_player" => "true",
            "is_admin" => "true"
          }
        }
      }

      {:ok, _view, _html} =
        view
        |> form("#bulk-member-form", params)
        |> render_submit()
        |> follow_redirect(conn, ~p"/teams/#{team}")

      members = Teams.list_team_members_for_team(team)
      # 2 stub users + the logged-in user that we added as :admin.
      assert length(members) == 3

      stub_members = Enum.reject(members, &(&1.user_id == user.id))
      names = Enum.map(stub_members, &User.display_name(&1.user)) |> Enum.sort()
      assert names == ["Alice Aaron", "Bob Brown"]

      alice = Enum.find(stub_members, &(&1.user.first_name == "Alice"))
      bob = Enum.find(stub_members, &(&1.user.first_name == "Bob"))

      assert alice.user.gender_role == :female_matching
      assert alice.role == :member
      assert alice.is_player == true
      assert alice.jersey_number == "1"

      assert bob.user.gender_role == :male_matching
      assert bob.role == :admin
      assert bob.jersey_number == nil

      Enum.each(stub_members, fn m ->
        assert String.starts_with?(m.user.email, "stub-")
        assert is_nil(m.user.hashed_password)
      end)
    end

    test "save_all with all blank rows flashes error and doesn't navigate", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      add_to_team(team, user, :admin)

      {:ok, view, _html} = live(conn, ~p"/members/new?team_id=#{team.id}")

      params = %{
        "row" => %{
          "0" => %{
            "first_name" => "",
            "last_name" => "",
            "jersey_number" => "",
            "is_player" => "true"
          }
        }
      }

      html = view |> form("#bulk-member-form", params) |> render_submit()

      assert html =~ "Add at least one member"
      # Only the admin's own membership exists.
      members = Teams.list_team_members_for_team(team)
      assert length(members) == 1
    end

    test "save_all rolls back the entire batch on a single-row failure", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      add_to_team(team, user, :admin)

      {:ok, view, _html} = live(conn, ~p"/members/new?team_id=#{team.id}")

      view |> element("button", "Add row") |> render_click()

      view
      |> element("#member-row-0 input[value='female_matching']")
      |> render_click()

      params = %{
        "row" => %{
          "0" => %{
            "first_name" => "Alice",
            "last_name" => "Aaron",
            "jersey_number" => "1",
            "is_player" => "true"
          },
          "1" => %{
            "first_name" => "Bob",
            "last_name" => "Brown",
            "jersey_number" => "",
            "is_player" => "true"
          }
        }
      }

      _html = view |> form("#bulk-member-form", params) |> render_submit()

      # Multi rolled back — only the admin's own membership persists.
      members = Teams.list_team_members_for_team(team)
      assert length(members) == 1
    end

    test "non-admin members can't open the bulk-add form", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user, :member)

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/members/new?team_id=#{team.id}")

      assert to == ~p"/teams/#{team.id}"
      assert flash["error"] =~ "permission"
    end
  end

  describe "Edit form — admin" do
    setup :register_and_log_in_user

    test "saves changes to BOTH the user and the membership in one go", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user, :admin)

      m =
        team_membership_fixture(%{
          team_id: team.id,
          first_name: "Old",
          last_name: "Name",
          gender_role: :female_matching,
          position: :cutter,
          role: :member,
          is_player: true,
          jersey_number: "7"
        })

      {:ok, view, _html} = live(conn, ~p"/members/#{m.id}/edit")

      params = %{
        "member" => %{
          "first_name" => "New",
          "last_name" => "Name",
          "jersey_number" => "42",
          "gender_role" => "female_matching",
          "position" => "cutter",
          "is_player" => "true",
          "role" => "admin"
        }
      }

      view
      |> form("#member-form", params)
      |> render_submit()

      reloaded = Teams.get_team_membership!(m.id) |> Repo.preload(:user)

      assert reloaded.user.first_name == "New"
      assert reloaded.user.last_name == "Name"

      assert reloaded.role == :admin
      assert reloaded.is_player == true
      assert reloaded.jersey_number == "42"
    end

    test "unchecking is_player flips it false", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user, :admin)
      m = team_membership_fixture(%{team_id: team.id, is_player: true, jersey_number: "9"})

      {:ok, view, _html} = live(conn, ~p"/members/#{m.id}/edit")

      params = %{
        "member" => %{
          "first_name" => m.user.first_name,
          "last_name" => m.user.last_name,
          "jersey_number" => "9",
          "gender_role" => Atom.to_string(m.user.gender_role),
          "position" => Atom.to_string(m.user.position),
          "is_player" => "false",
          "role" => "member"
        }
      }

      view
      |> form("#member-form", params)
      |> render_submit()

      reloaded = Repo.get!(TeamMembership, m.id)
      assert reloaded.is_player == false
      assert reloaded.role == :member
    end

    test "validation errors on the user side surface on the form", %{conn: conn, user: user} do
      team = team_fixture()
      add_to_team(team, user, :admin)

      m =
        team_membership_fixture(%{
          team_id: team.id,
          first_name: "Avery",
          last_name: "Adams"
        })

      {:ok, view, _html} = live(conn, ~p"/members/#{m.id}/edit")

      params = %{
        "member" => %{
          "first_name" => "",
          "last_name" => "Adams",
          "jersey_number" => "1",
          "gender_role" => Atom.to_string(m.user.gender_role),
          "position" => Atom.to_string(m.user.position),
          "is_player" => "true"
        }
      }

      html =
        view
        |> form("#member-form", params)
        |> render_submit()

      assert html =~ "can&#39;t be blank"

      assert Repo.get!(User, m.user_id).first_name == "Avery"
    end
  end

  describe "Edit form — non-admin" do
    setup :register_and_log_in_user

    test "non-admin members are redirected away from /members/:id/edit", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      add_to_team(team, user, :member)
      m = team_membership_fixture(%{team_id: team.id})

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/members/#{m.id}/edit")

      assert to == ~p"/teams/#{team.id}"
      assert flash["error"] =~ "permission"
    end
  end
end
