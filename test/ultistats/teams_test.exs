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

    @invalid_attrs %{
      first_name: nil,
      last_name: nil,
      jersey_number: nil,
      gender_role: nil,
      team_id: nil
    }

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
        first_name: "Some",
        last_name: "Player",
        jersey_number: "00",
        gender_role: :female_matching,
        team_id: team.id
      }

      assert {:ok, %Player{} = player} = Teams.create_player(valid_attrs)
      assert player.first_name == "Some"
      assert player.last_name == "Player"
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
                 first_name: "Pat",
                 last_name: "Smith",
                 jersey_number: "9",
                 gender_role: "not_a_real_value",
                 team_id: team.id
               })

      assert %{gender_role: ["is invalid"]} = errors_on(changeset)
    end

    test "create_player/1 rejects first names longer than 40 characters" do
      team = team_fixture()
      long_name = String.duplicate("a", 41)

      assert {:error, changeset} =
               Teams.create_player(%{
                 first_name: long_name,
                 last_name: "Smith",
                 jersey_number: "1",
                 gender_role: :male_matching,
                 team_id: team.id
               })

      assert %{first_name: ["should be at most 40 character(s)"]} = errors_on(changeset)
    end

    test "create_player/1 rejects last names longer than 40 characters" do
      team = team_fixture()
      long_name = String.duplicate("a", 41)

      assert {:error, changeset} =
               Teams.create_player(%{
                 first_name: "Pat",
                 last_name: long_name,
                 jersey_number: "1",
                 gender_role: :male_matching,
                 team_id: team.id
               })

      assert %{last_name: ["should be at most 40 character(s)"]} = errors_on(changeset)
    end

    test "create_player/1 requires both first and last name" do
      team = team_fixture()

      assert {:error, changeset} =
               Teams.create_player(%{
                 first_name: "Pat",
                 last_name: nil,
                 jersey_number: "1",
                 gender_role: :male_matching,
                 team_id: team.id
               })

      assert %{last_name: ["can't be blank"]} = errors_on(changeset)
    end

    test "create_player/1 rejects jersey numbers longer than 4 characters" do
      team = team_fixture()

      assert {:error, changeset} =
               Teams.create_player(%{
                 first_name: "Pat",
                 last_name: "Smith",
                 jersey_number: "12345",
                 gender_role: :male_matching,
                 team_id: team.id
               })

      assert %{jersey_number: ["should be at most 4 character(s)"]} = errors_on(changeset)
    end

    test "update_player/2 with valid data updates the player" do
      player = player_fixture()

      update_attrs = %{
        first_name: "Some",
        last_name: "Updated",
        jersey_number: "42",
        gender_role: :male_matching
      }

      assert {:ok, %Player{} = player} = Teams.update_player(player, update_attrs)
      assert player.first_name == "Some"
      assert player.last_name == "Updated"
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

      _stranger =
        player_fixture(%{team_id: other.id, name: "Stranger Stranger", jersey_number: "1"})

      p_high = player_fixture(%{team_id: team.id, name: "High Player", jersey_number: "99"})
      p_low = player_fixture(%{team_id: team.id, name: "Low Player", jersey_number: "10"})

      players = Teams.list_players_for_team(team)
      assert Enum.map(players, & &1.id) == [p_low.id, p_high.id]
    end

    test "Player.changeset/2 accepts nil jersey_number" do
      team = team_fixture()

      changeset =
        Ultistats.Teams.Player.changeset(%Ultistats.Teams.Player{}, %{
          first_name: "No",
          last_name: "Number",
          jersey_number: nil,
          gender_role: :female_matching,
          team_id: team.id
        })

      assert changeset.valid?
    end

    test "Player.changeset/2 still rejects 5-char jersey_number" do
      team = team_fixture()

      changeset =
        Ultistats.Teams.Player.changeset(%Ultistats.Teams.Player{}, %{
          first_name: "Pat",
          last_name: "Smith",
          jersey_number: "12345",
          gender_role: :female_matching,
          team_id: team.id
        })

      refute changeset.valid?
      assert %{jersey_number: ["should be at most 4 character(s)"]} = errors_on(changeset)
    end

    test "Player.display_name/1 joins first and last with a space" do
      player = %Ultistats.Teams.Player{first_name: "Sam", last_name: "Rivera"}
      assert Ultistats.Teams.Player.display_name(player) == "Sam Rivera"
    end

    test "Player.display_name/1 omits blank halves gracefully" do
      assert Ultistats.Teams.Player.display_name(%Ultistats.Teams.Player{
               first_name: "Sam",
               last_name: nil
             }) == "Sam"

      assert Ultistats.Teams.Player.display_name(%Ultistats.Teams.Player{
               first_name: "",
               last_name: "Rivera"
             }) == "Rivera"
    end
  end

  describe "bulk_create_players/2" do
    import Ultistats.TeamsFixtures

    test "inserts all rows, ordered by inserted_at" do
      team = team_fixture()

      rows = [
        %{
          first_name: "Alice",
          last_name: "Aaron",
          jersey_number: "1",
          gender_role: :female_matching
        },
        %{first_name: "Bob", last_name: "Brown", jersey_number: "2", gender_role: :male_matching},
        %{first_name: "Cam", last_name: "Cole", jersey_number: nil, gender_role: :female_matching}
      ]

      assert {:ok, players} = Teams.bulk_create_players(team, rows)
      assert length(players) == 3
      assert Enum.map(players, & &1.first_name) == ["Alice", "Bob", "Cam"]
      assert Enum.map(players, & &1.last_name) == ["Aaron", "Brown", "Cole"]
      # All belong to the team.
      assert Enum.all?(players, &(&1.team_id == team.id))
      # Sanity: persisted, not just returned.
      assert length(Teams.list_players_for_team(team)) == 3
    end

    test "rolls back when a row is invalid; nothing is persisted" do
      team = team_fixture()

      rows = [
        %{
          first_name: "Alice",
          last_name: "Aaron",
          jersey_number: "1",
          gender_role: :female_matching
        },
        # missing gender_role
        %{first_name: "Bob", last_name: "Brown", jersey_number: "2", gender_role: nil}
      ]

      assert {:error, {idx, %Ecto.Changeset{} = changeset}} =
               Teams.bulk_create_players(team, rows)

      assert idx == 1
      assert %{gender_role: ["can't be blank"]} = errors_on(changeset)
      assert Teams.list_players_for_team(team) == []
    end

    test "filters rows where both first and last name are blank" do
      team = team_fixture()

      rows = [
        %{first_name: "", last_name: "", jersey_number: "1", gender_role: :female_matching},
        %{
          first_name: "Alice",
          last_name: "Aaron",
          jersey_number: "1",
          gender_role: :female_matching
        },
        %{first_name: "   ", last_name: "  ", jersey_number: "2", gender_role: :male_matching},
        %{first_name: nil, last_name: nil, jersey_number: "3", gender_role: :female_matching}
      ]

      assert {:ok, [player]} = Teams.bulk_create_players(team, rows)
      assert player.first_name == "Alice"
      assert player.last_name == "Aaron"
      assert length(Teams.list_players_for_team(team)) == 1
    end

    test "ignores team_id in the row map; uses the team arg" do
      team = team_fixture(%{name: "Home"})
      sneaky = team_fixture(%{name: "Sneaky"})

      rows = [
        %{
          first_name: "Alice",
          last_name: "Aaron",
          jersey_number: "1",
          gender_role: :female_matching,
          team_id: sneaky.id
        }
      ]

      assert {:ok, [player]} = Teams.bulk_create_players(team, rows)
      assert player.team_id == team.id
      refute player.team_id == sneaky.id
    end

    test "accepts string-keyed row maps too" do
      team = team_fixture()

      rows = [
        %{
          "first_name" => "Alice",
          "last_name" => "Aaron",
          "jersey_number" => "7",
          "gender_role" => :female_matching
        }
      ]

      assert {:ok, [player]} = Teams.bulk_create_players(team, rows)
      assert player.first_name == "Alice"
      assert player.last_name == "Aaron"
      assert player.jersey_number == "7"
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

    test "create_line_preset/1 with player_ids attaches the players" do
      team = team_fixture()
      p1 = player_fixture(%{team_id: team.id, jersey_number: "1", name: "A One"})
      p2 = player_fixture(%{team_id: team.id, jersey_number: "2", name: "B Two"})

      assert {:ok, line_preset} =
               Teams.create_line_preset(%{
                 name: "Mixed",
                 team_id: team.id,
                 player_ids: [p1.id, p2.id]
               })

      preset = Teams.get_line_preset!(line_preset.id)
      assert Enum.map(preset.players, & &1.id) |> Enum.sort() == Enum.sort([p1.id, p2.id])
    end

    test "create_line_preset/1 ignores player_ids that belong to other teams" do
      team = team_fixture(%{name: "Home"})
      other_team = team_fixture(%{name: "Away"})

      ours = player_fixture(%{team_id: team.id, jersey_number: "1", name: "Ours Player"})

      theirs =
        player_fixture(%{team_id: other_team.id, jersey_number: "1", name: "Theirs Player"})

      assert {:ok, line_preset} =
               Teams.create_line_preset(%{
                 name: "Sneaky",
                 team_id: team.id,
                 player_ids: [ours.id, theirs.id]
               })

      preset = Teams.get_line_preset!(line_preset.id)
      assert Enum.map(preset.players, & &1.id) == [ours.id]
    end

    test "create_line_preset/1 with no player_ids creates an empty preset" do
      team = team_fixture()

      assert {:ok, line_preset} =
               Teams.create_line_preset(%{name: "Empty", team_id: team.id})

      preset = Teams.get_line_preset!(line_preset.id)
      assert preset.players == []
    end

    test "create_line_preset/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Teams.create_line_preset(@invalid_attrs)
    end

    test "update_line_preset/2 with player_ids replaces (not appends) the players" do
      team = team_fixture()
      p1 = player_fixture(%{team_id: team.id, jersey_number: "1", name: "A One"})
      p2 = player_fixture(%{team_id: team.id, jersey_number: "2", name: "B Two"})
      p3 = player_fixture(%{team_id: team.id, jersey_number: "3", name: "C Three"})

      {:ok, line_preset} =
        Teams.create_line_preset(%{
          name: "Original",
          team_id: team.id,
          player_ids: [p1.id, p2.id]
        })

      assert {:ok, updated} =
               Teams.update_line_preset(line_preset, %{
                 name: "Original",
                 team_id: team.id,
                 player_ids: [p3.id]
               })

      reloaded = Teams.get_line_preset!(updated.id)
      assert Enum.map(reloaded.players, & &1.id) == [p3.id]
    end

    test "update_line_preset/2 with invalid data returns error changeset" do
      line_preset = line_preset_fixture()
      assert {:error, %Ecto.Changeset{}} = Teams.update_line_preset(line_preset, @invalid_attrs)
    end

    test "delete_line_preset/1 deletes the line_preset and cascades the join table" do
      team = team_fixture()
      p1 = player_fixture(%{team_id: team.id, jersey_number: "1"})

      {:ok, line_preset} =
        Teams.create_line_preset(%{
          name: "Soon-deleted",
          team_id: team.id,
          player_ids: [p1.id]
        })

      assert {:ok, %LinePreset{}} = Teams.delete_line_preset(line_preset)
      assert_raise Ecto.NoResultsError, fn -> Teams.get_line_preset!(line_preset.id) end

      # Player is still around (cascade is on the join row only).
      assert Teams.get_player!(p1.id)

      # No orphan join rows.
      orphan_count =
        Ultistats.Repo.aggregate(
          from(j in "line_preset_players", where: j.line_preset_id == ^line_preset.id),
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

    test "change_line_preset/1 returns a line_preset changeset" do
      line_preset = line_preset_fixture()
      assert %Ecto.Changeset{} = Teams.change_line_preset(line_preset)
    end
  end
end
