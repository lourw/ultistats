defmodule Ultistats.TeamsTest do
  use Ultistats.DataCase

  alias Ultistats.Teams

  describe "teams" do
    alias Ultistats.Teams.Team

    import Ultistats.TeamsFixtures

    @invalid_attrs %{name: nil}

    test "list_teams/0 returns all teams" do
      team = team_fixture()
      assert Teams.list_teams() == [team]
    end

    test "get_team!/1 returns the team with given id" do
      team = team_fixture()
      assert Teams.get_team!(team.id) == team
    end

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

    test "change_team/1 returns a team changeset" do
      team = team_fixture()
      assert %Ecto.Changeset{} = Teams.change_team(team)
    end
  end

  describe "players" do
    alias Ultistats.Teams.Player

    import Ultistats.TeamsFixtures

    @invalid_attrs %{name: nil, jersey_number: nil, gender_role: nil, team_id: nil}

    test "list_players/0 returns all players" do
      player = player_fixture()
      assert [%Player{id: id}] = Teams.list_players()
      assert id == player.id
    end

    test "get_player!/1 returns the player with given id" do
      player = player_fixture()
      assert Teams.get_player!(player.id) == player
    end

    test "create_player/1 with valid data creates a player" do
      team = team_fixture()

      valid_attrs = %{
        name: "some name",
        jersey_number: "00",
        gender_role: :female_matching,
        team_id: team.id
      }

      assert {:ok, %Player{} = player} = Teams.create_player(valid_attrs)
      assert player.name == "some name"
      assert player.jersey_number == "00"
      assert player.gender_role == :female_matching
      assert player.team_id == team.id
    end

    test "create_player/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Teams.create_player(@invalid_attrs)
    end

    test "create_player/1 rejects gender_role values outside the enum" do
      team = team_fixture()

      assert {:error, changeset} =
               Teams.create_player(%{
                 name: "Pat",
                 jersey_number: "9",
                 gender_role: "not_a_real_value",
                 team_id: team.id
               })

      assert %{gender_role: ["is invalid"]} = errors_on(changeset)
    end

    test "create_player/1 rejects names longer than 80 characters" do
      team = team_fixture()
      long_name = String.duplicate("a", 81)

      assert {:error, changeset} =
               Teams.create_player(%{
                 name: long_name,
                 jersey_number: "1",
                 gender_role: :male_matching,
                 team_id: team.id
               })

      assert %{name: ["should be at most 80 character(s)"]} = errors_on(changeset)
    end

    test "create_player/1 rejects jersey numbers longer than 4 characters" do
      team = team_fixture()

      assert {:error, changeset} =
               Teams.create_player(%{
                 name: "Pat",
                 jersey_number: "12345",
                 gender_role: :male_matching,
                 team_id: team.id
               })

      assert %{jersey_number: ["should be at most 4 character(s)"]} = errors_on(changeset)
    end

    test "update_player/2 with valid data updates the player" do
      player = player_fixture()

      update_attrs = %{
        name: "some updated name",
        jersey_number: "42",
        gender_role: :male_matching
      }

      assert {:ok, %Player{} = player} = Teams.update_player(player, update_attrs)
      assert player.name == "some updated name"
      assert player.jersey_number == "42"
      assert player.gender_role == :male_matching
    end

    test "update_player/2 with invalid data returns error changeset" do
      player = player_fixture()
      assert {:error, %Ecto.Changeset{}} = Teams.update_player(player, @invalid_attrs)
      assert player == Teams.get_player!(player.id)
    end

    test "delete_player/1 deletes the player" do
      player = player_fixture()
      assert {:ok, %Player{}} = Teams.delete_player(player)
      assert_raise Ecto.NoResultsError, fn -> Teams.get_player!(player.id) end
    end

    test "change_player/1 returns a player changeset" do
      player = player_fixture()
      assert %Ecto.Changeset{} = Teams.change_player(player)
    end

    test "list_players_for_team/1 returns only that team's players, ordered by jersey" do
      team = team_fixture(%{name: "Home"})
      other = team_fixture(%{name: "Away"})

      _stranger = player_fixture(%{team_id: other.id, name: "Stranger", jersey_number: "1"})
      p_high = player_fixture(%{team_id: team.id, name: "High", jersey_number: "99"})
      p_low = player_fixture(%{team_id: team.id, name: "Low", jersey_number: "10"})

      players = Teams.list_players_for_team(team)
      assert Enum.map(players, & &1.id) == [p_low.id, p_high.id]
    end
  end
end
