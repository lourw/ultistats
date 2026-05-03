defmodule Ultistats.TeamsTest do
  use Ultistats.DataCase

  alias Ultistats.Teams

  describe "teams" do
    alias Ultistats.Teams.Team

    import Ultistats.TeamsFixtures

    @invalid_attrs %{name: nil}

    test "create_team/1 with valid data creates a team" do
      valid_attrs = %{name: "some name"}

      assert {:ok, %Team{} = team} = Teams.create_team(valid_attrs)
      assert team.name == "some name"
    end

    test "create_team/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Teams.create_team(@invalid_attrs)
    end

    test "create_team/1 rejects names longer than 80 characters" do
      long_name = String.duplicate("a", 81)
      assert {:error, changeset} = Teams.create_team(%{name: long_name})
      assert %{name: ["should be at most 80 character(s)"]} = errors_on(changeset)
    end

    test "create_team/1 rejects empty string names" do
      assert {:error, changeset} = Teams.create_team(%{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "update_team/2 with valid data updates the team" do
      team = team_fixture()
      update_attrs = %{name: "some updated name"}

      assert {:ok, %Team{} = team} = Teams.update_team(team, update_attrs)
      assert team.name == "some updated name"
    end

    test "update_team/2 with invalid data returns error changeset" do
      team = team_fixture()
      assert {:error, %Ecto.Changeset{}} = Teams.update_team(team, @invalid_attrs)
      assert team == Teams.get_team!(team.id)
    end

    test "delete_team/1 deletes the team" do
      team = team_fixture()
      assert {:ok, %Team{}} = Teams.delete_team(team)
      assert_raise Ecto.NoResultsError, fn -> Teams.get_team!(team.id) end
    end
  end

  describe "team_memberships" do
    alias Ultistats.Accounts
    alias Ultistats.Teams.TeamMembership

    import Ultistats.TeamsFixtures

    test "add_team_member/3 inserts a membership" do
      team = team_fixture()
      {:ok, user} = stub_user()

      assert {:ok, %TeamMembership{} = m} =
               Teams.add_team_member(team, user, %{
                 role: :member,
                 is_player: true,
                 jersey_number: "7"
               })

      assert m.team_id == team.id
      assert m.user_id == user.id
      assert m.role == :member
      assert m.is_player == true
      assert m.jersey_number == "7"
    end

    test "add_team_member/3 enforces unique team+user" do
      team = team_fixture()
      {:ok, user} = stub_user()

      {:ok, _} = Teams.add_team_member(team, user, %{role: :member})

      assert {:error, changeset} = Teams.add_team_member(team, user, %{role: :admin})
      assert %{team_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "update_team_membership/2 toggles is_player and role" do
      m = team_membership_fixture(%{role: :member, is_player: true})

      assert {:ok, updated} =
               Teams.update_team_membership(m, %{role: :admin, is_player: false})

      assert updated.role == :admin
      assert updated.is_player == false
    end

    test "remove_team_member/1 deletes the row" do
      m = team_membership_fixture()
      assert {:ok, %TeamMembership{}} = Teams.remove_team_member(m)
      assert_raise Ecto.NoResultsError, fn -> Teams.get_team_membership!(m.id) end
    end

    test "list_team_members_for_team/1 returns memberships preloaded with :user" do
      team = team_fixture()
      _m1 = team_membership_fixture(%{team_id: team.id, jersey_number: "7"})
      _m2 = team_membership_fixture(%{team_id: team.id, jersey_number: "11"})

      results = Teams.list_team_members_for_team(team)
      assert length(results) == 2
      assert Enum.all?(results, &match?(%TeamMembership{user: %Accounts.User{}}, &1))
    end

    test "list_players_for_team/1 filters to is_player=true" do
      team = team_fixture()

      _player =
        team_membership_fixture(%{team_id: team.id, is_player: true, jersey_number: "1"})

      _coach =
        team_membership_fixture(%{team_id: team.id, is_player: false, jersey_number: nil})

      results = Teams.list_players_for_team(team)
      assert length(results) == 1
      assert Enum.all?(results, & &1.is_player)
    end

    test "create_member_with_stub_user/2 atomically creates user + membership" do
      team = team_fixture()

      assert {:ok, %{user: user, membership: membership}} =
               Teams.create_member_with_stub_user(team, %{
                 first_name: "Sam",
                 last_name: "Rivera",
                 gender_role: :female_matching,
                 position: :cutter,
                 role: :member,
                 is_player: true,
                 jersey_number: "12"
               })

      assert user.first_name == "Sam"
      assert user.last_name == "Rivera"
      assert user.hashed_password == nil
      assert String.starts_with?(user.email, "stub-")
      assert membership.team_id == team.id
      assert membership.user_id == user.id
      assert membership.jersey_number == "12"
    end

    test "create_member_with_stub_user/2 rolls back when user creation fails" do
      team = team_fixture()

      # Missing required first_name on the stub user → user step fails.
      assert {:error, :user, %Ecto.Changeset{}, _changes} =
               Teams.create_member_with_stub_user(team, %{
                 last_name: "Only",
                 gender_role: :male_matching,
                 position: :handler,
                 role: :member,
                 is_player: true
               })

      # No memberships, no users (other than what fixtures created).
      assert Teams.list_team_members_for_team(team) == []
    end

    test "add_team_member/3 prefills :position and :jersey_number from the user's defaults" do
      team = team_fixture()

      {:ok, user} =
        Ultistats.Accounts.create_stub_user(%{
          first_name: "Sam",
          last_name: "Default",
          gender_role: :male_matching,
          position: :handler
        })

      # Stash a jersey on the user as their personal default.
      {:ok, user} =
        user
        |> Ecto.Changeset.change(jersey_number: "23")
        |> Ultistats.Repo.update()

      assert {:ok, m} = Teams.add_team_member(team, user, %{role: :member, is_player: true})
      assert m.position == :handler
      assert m.jersey_number == "23"
    end

    test "add_team_member/3 prefers explicit :position / :jersey_number over user defaults" do
      team = team_fixture()

      {:ok, user} =
        Ultistats.Accounts.create_stub_user(%{
          first_name: "Sam",
          last_name: "Override",
          gender_role: :male_matching,
          position: :handler
        })

      assert {:ok, m} =
               Teams.add_team_member(team, user, %{
                 role: :member,
                 is_player: true,
                 position: :cutter,
                 jersey_number: "9"
               })

      assert m.position == :cutter
      assert m.jersey_number == "9"
    end

    test "resolved_position/1 prefers the membership override over the user default" do
      team = team_fixture()

      {:ok, user} =
        Ultistats.Accounts.create_stub_user(%{
          first_name: "P",
          last_name: "Override",
          gender_role: :female_matching,
          position: :hybrid
        })

      {:ok, m} =
        Teams.add_team_member(team, user, %{role: :member, is_player: true, position: :handler})

      m = Teams.get_team_membership!(m.id)
      assert Teams.resolved_position(m) == :handler
    end

    test "resolved_position/1 falls back to the user's default when membership override is nil" do
      team = team_fixture()

      {:ok, user} =
        Ultistats.Accounts.create_stub_user(%{
          first_name: "P",
          last_name: "Fallback",
          gender_role: :female_matching,
          position: :cutter
        })

      # Insert membership directly with no position override.
      {:ok, m} =
        %TeamMembership{}
        |> TeamMembership.changeset(%{
          team_id: team.id,
          user_id: user.id,
          role: :member,
          is_player: true
        })
        |> Ultistats.Repo.insert()

      m = Teams.get_team_membership!(m.id)
      assert is_nil(m.position)
      assert Teams.resolved_position(m) == :cutter
    end

    test "resolved_jersey_number/1 prefers the membership override, falls back to the user" do
      team = team_fixture()

      {:ok, user} =
        Ultistats.Accounts.create_stub_user(%{
          first_name: "J",
          last_name: "Number",
          gender_role: :male_matching,
          position: :cutter
        })

      {:ok, user} =
        user
        |> Ecto.Changeset.change(jersey_number: "5")
        |> Ultistats.Repo.update()

      # Override on the membership.
      {:ok, m_override} =
        Teams.add_team_member(team, user, %{
          role: :member,
          is_player: true,
          jersey_number: "42"
        })

      assert Teams.resolved_jersey_number(Teams.get_team_membership!(m_override.id)) == "42"

      # Same user joining a second team with no override — falls back.
      team2 = team_fixture(%{name: "Other"})

      {:ok, m_fallback} =
        %TeamMembership{}
        |> TeamMembership.changeset(%{
          team_id: team2.id,
          user_id: user.id,
          role: :member,
          is_player: true
        })
        |> Ultistats.Repo.insert()

      assert Teams.resolved_jersey_number(Teams.get_team_membership!(m_fallback.id)) == "5"
    end

    defp stub_user do
      Ultistats.Accounts.create_stub_user(%{
        first_name: "Test",
        last_name: "User",
        gender_role: :male_matching,
        position: :cutter
      })
    end
  end

  describe "line_presets" do
    alias Ultistats.Teams.LinePreset

    import Ultistats.TeamsFixtures

    @invalid_attrs %{name: nil, team_id: nil}

    test "create_line_preset/1 with valid data creates a line_preset" do
      team = team_fixture()
      valid_attrs = %{name: "O-line A", team_id: team.id}

      assert {:ok, %LinePreset{} = line_preset} = Teams.create_line_preset(valid_attrs)
      assert line_preset.name == "O-line A"
      assert line_preset.team_id == team.id
    end

    test "create_line_preset/1 with user_ids attaches the users" do
      team = team_fixture()
      m1 = team_membership_fixture(%{team_id: team.id, jersey_number: "1"})
      m2 = team_membership_fixture(%{team_id: team.id, jersey_number: "2"})

      assert {:ok, line_preset} =
               Teams.create_line_preset(%{
                 name: "Mixed",
                 team_id: team.id,
                 user_ids: [m1.user_id, m2.user_id]
               })

      preset = Teams.get_line_preset!(line_preset.id)

      assert Enum.map(preset.users, & &1.id) |> Enum.sort() ==
               Enum.sort([m1.user_id, m2.user_id])
    end

    test "create_line_preset/1 ignores user_ids that don't belong to the team" do
      team = team_fixture(%{name: "Home"})
      other_team = team_fixture(%{name: "Away"})

      ours = team_membership_fixture(%{team_id: team.id, jersey_number: "1"})
      theirs = team_membership_fixture(%{team_id: other_team.id, jersey_number: "1"})

      assert {:ok, line_preset} =
               Teams.create_line_preset(%{
                 name: "Sneaky",
                 team_id: team.id,
                 user_ids: [ours.user_id, theirs.user_id]
               })

      preset = Teams.get_line_preset!(line_preset.id)
      assert Enum.map(preset.users, & &1.id) == [ours.user_id]
    end

    test "create_line_preset/1 with no user_ids creates an empty preset" do
      team = team_fixture()

      assert {:ok, line_preset} =
               Teams.create_line_preset(%{name: "Empty", team_id: team.id})

      preset = Teams.get_line_preset!(line_preset.id)
      assert preset.users == []
    end

    test "create_line_preset/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Teams.create_line_preset(@invalid_attrs)
    end

    test "update_line_preset/2 with user_ids replaces (not appends) the users" do
      team = team_fixture()
      m1 = team_membership_fixture(%{team_id: team.id, jersey_number: "1"})
      m2 = team_membership_fixture(%{team_id: team.id, jersey_number: "2"})
      m3 = team_membership_fixture(%{team_id: team.id, jersey_number: "3"})

      {:ok, line_preset} =
        Teams.create_line_preset(%{
          name: "Original",
          team_id: team.id,
          user_ids: [m1.user_id, m2.user_id]
        })

      assert {:ok, updated} =
               Teams.update_line_preset(line_preset, %{
                 name: "Original",
                 team_id: team.id,
                 user_ids: [m3.user_id]
               })

      reloaded = Teams.get_line_preset!(updated.id)
      assert Enum.map(reloaded.users, & &1.id) == [m3.user_id]
    end

    test "update_line_preset/2 with invalid data returns error changeset" do
      line_preset = line_preset_fixture()
      assert {:error, %Ecto.Changeset{}} = Teams.update_line_preset(line_preset, @invalid_attrs)
    end

    test "delete_line_preset/1 deletes the line_preset and cascades the join table" do
      team = team_fixture()
      m1 = team_membership_fixture(%{team_id: team.id, jersey_number: "1"})

      {:ok, line_preset} =
        Teams.create_line_preset(%{
          name: "Soon-deleted",
          team_id: team.id,
          user_ids: [m1.user_id]
        })

      assert {:ok, %LinePreset{}} = Teams.delete_line_preset(line_preset)
      assert_raise Ecto.NoResultsError, fn -> Teams.get_line_preset!(line_preset.id) end

      # Membership is still around (cascade is on the join row only).
      assert Teams.get_team_membership!(m1.id)

      # No orphan join rows.
      orphan_count =
        Ultistats.Repo.aggregate(
          from(j in "line_preset_users", where: j.line_preset_id == ^line_preset.id),
          :count
        )

      assert orphan_count == 0
    end

    test "list_line_presets_for_team/1 returns presets ordered by name, scoped by team" do
      team = team_fixture(%{name: "Home"})
      other = team_fixture(%{name: "Away"})

      _stranger =
        line_preset_fixture(%{team_id: other.id, name: "Stranger"})

      b = line_preset_fixture(%{team_id: team.id, name: "Bravo"})
      a = line_preset_fixture(%{team_id: team.id, name: "Alpha"})

      presets = Teams.list_line_presets_for_team(team)
      assert Enum.map(presets, & &1.id) == [a.id, b.id]
    end
  end

  describe "team_stats/1" do
    import Ultistats.TeamsFixtures
    import Ultistats.GamesFixtures

    alias Ultistats.Games

    test "returns zeros for an empty team" do
      team = team_fixture()

      assert %{
               total_players: 0,
               male_matching: 0,
               female_matching: 0,
               games_in_progress: 0,
               wins: 0,
               losses: 0,
               ties: 0
             } = Teams.team_stats(team)
    end

    test "counts players by gender_role via team_memberships" do
      team = team_fixture()

      _f1 =
        team_membership_fixture(%{
          team_id: team.id,
          gender_role: :female_matching,
          jersey_number: "1"
        })

      _f2 =
        team_membership_fixture(%{
          team_id: team.id,
          gender_role: :female_matching,
          jersey_number: "2"
        })

      _m1 =
        team_membership_fixture(%{
          team_id: team.id,
          gender_role: :male_matching,
          jersey_number: "3"
        })

      # A non-player member shouldn't be counted.
      _coach =
        team_membership_fixture(%{
          team_id: team.id,
          gender_role: :male_matching,
          is_player: false
        })

      # A player on a different team should not be counted.
      other_team = team_fixture(%{name: "Other"})

      _stranger =
        team_membership_fixture(%{team_id: other_team.id, gender_role: :male_matching})

      stats = Teams.team_stats(team)
      assert stats.total_players == 3
      assert stats.female_matching == 2
      assert stats.male_matching == 1
    end

    test "counts in-progress games" do
      team = team_fixture()
      _g1 = game_fixture(%{team_id: team.id, status: :in_progress})
      _g2 = game_fixture(%{team_id: team.id, status: :in_progress})
      # Different team's in-progress game should not count.
      other = team_fixture(%{name: "Other"})
      _other_g = game_fixture(%{team_id: other.id, status: :in_progress})

      stats = Teams.team_stats(team)
      assert stats.games_in_progress == 2
    end

    test "counts wins and losses for finished games using Games.score/1" do
      team = team_fixture()

      # Build a finished game where we win 2–1.
      win_game = game_fixture(%{team_id: team.id, status: :finished})
      p_win_a = point_fixture(%{game_id: win_game.id, sequence: 1, scoring_team: :ours})
      _ = event_fixture(%{point_id: p_win_a.id, type: :goal})
      p_win_b = point_fixture(%{game_id: win_game.id, sequence: 2, scoring_team: :ours})
      _ = event_fixture(%{point_id: p_win_b.id, type: :goal})
      _p_win_c = point_fixture(%{game_id: win_game.id, sequence: 3, scoring_team: :theirs})

      # Build a finished game where we lose 0–1.
      loss_game = game_fixture(%{team_id: team.id, status: :finished})
      _p_loss = point_fixture(%{game_id: loss_game.id, sequence: 1, scoring_team: :theirs})

      # Confirm score helper agrees with our setup before assertions.
      assert Games.score(win_game) == %{ours: 2, theirs: 1}
      assert Games.score(loss_game) == %{ours: 0, theirs: 1}

      stats = Teams.team_stats(team)
      assert stats.wins == 1
      assert stats.losses == 1
      assert stats.ties == 0
    end

    test "distinguishes ties from wins or losses" do
      team = team_fixture()

      tie_game = game_fixture(%{team_id: team.id, status: :finished})
      p_t_a = point_fixture(%{game_id: tie_game.id, sequence: 1, scoring_team: :ours})
      _ = event_fixture(%{point_id: p_t_a.id, type: :goal})
      _p_t_b = point_fixture(%{game_id: tie_game.id, sequence: 2, scoring_team: :theirs})

      assert Games.score(tie_game) == %{ours: 1, theirs: 1}

      stats = Teams.team_stats(team)
      assert stats.ties == 1
      assert stats.wins == 0
      assert stats.losses == 0
    end

    test "in-progress games do not contribute to wins/losses/ties" do
      team = team_fixture()
      g = game_fixture(%{team_id: team.id, status: :in_progress})
      _p = point_fixture(%{game_id: g.id, sequence: 1, scoring_team: :ours})

      stats = Teams.team_stats(team)
      assert stats.games_in_progress == 1
      assert stats.wins == 0
      assert stats.losses == 0
      assert stats.ties == 0
    end
  end

  describe "list_teams_with_stats/0" do
    import Ultistats.TeamsFixtures

    test "returns a list ordered by team name with stats embedded" do
      _b = team_fixture(%{name: "Bravo"})
      a = team_fixture(%{name: "Alpha"})
      _c = team_fixture(%{name: "Charlie"})

      _player = team_membership_fixture(%{team_id: a.id, gender_role: :male_matching})

      results = Teams.list_teams_with_stats()
      assert Enum.map(results, & &1.team.name) == ["Alpha", "Bravo", "Charlie"]

      [%{team: alpha, stats: alpha_stats} | _] = results
      assert alpha.id == a.id
      assert alpha_stats.total_players == 1
      assert alpha_stats.male_matching == 1
      assert alpha_stats.female_matching == 0
    end
  end
end
