# Idempotent dev seed: one team, 14 players (8 MMP + 6 FMP), and two
# line presets. Re-running is a no-op as long as a team already exists.
#
# Run manually with: `mix run priv/repo/seeds.exs`
# Auto-runs on `mix phx.server` in dev (see lib/ultistats/application.ex).

alias Ultistats.{Repo, Teams}
alias Ultistats.Teams.Team

if Repo.aggregate(Team, :count, :id) == 0 do
  {:ok, team} = Teams.create_team(%{name: "The Misfits"})

  # 6 female-matching, 8 male-matching = 14 total. Jersey numbers are
  # intentionally not in alphabetical order of first name so sort-by
  # toggles produce visibly different orderings during testing.
  player_specs = [
    # FMP (6) — jerseys intentionally shuffled vs first-name alpha order
    {"Brooke", "Lee", "3", :female_matching, :cutter},
    {"Avery", "Stone", "11", :female_matching, :handler},
    {"Casey", "Park", "00", :female_matching, :cutter},
    {"Frankie", "Holt", "1", :female_matching, :cutter},
    {"Emery", "Vance", "21", :female_matching, :handler},
    {"Devon", "Reed", "8", :female_matching, :hybrid},
    # MMP (8)
    {"Niko", "Pham", "2", :male_matching, :hybrid},
    {"Gabe", "Quinn", "17", :male_matching, :handler},
    {"Marlowe", "Hart", "5", :male_matching, :handler},
    {"Hayden", "Cole", "9", :male_matching, :cutter},
    {"Logan", "West", "44", :male_matching, :cutter},
    {"Ira", "Bell", "13", :male_matching, :hybrid},
    {"Kit", "Ng", "7", :male_matching, :cutter},
    {"Jordan", "Diaz", "23", :male_matching, :handler}
  ]

  players =
    Enum.map(player_specs, fn {first, last, jersey, gender, position} ->
      {:ok, p} =
        Teams.create_player(%{
          team_id: team.id,
          first_name: first,
          last_name: last,
          jersey_number: jersey,
          gender_role: gender,
          position: position
        })

      p
    end)

  by_first = fn name ->
    Enum.find(players, &(&1.first_name == name))
  end

  o_line_player_ids =
    ["Hayden", "Ira", "Jordan", "Kit", "Avery", "Brooke", "Casey"]
    |> Enum.map(&by_first.(&1).id)

  d_line_player_ids =
    ["Logan", "Marlowe", "Niko", "Gabe", "Devon", "Emery", "Frankie"]
    |> Enum.map(&by_first.(&1).id)

  {:ok, _} =
    Teams.create_line_preset(%{
      team_id: team.id,
      name: "O-line",
      player_ids: o_line_player_ids
    })

  {:ok, _} =
    Teams.create_line_preset(%{
      team_id: team.id,
      name: "D-line",
      player_ids: d_line_player_ids
    })

  IO.puts("Seeded: #{team.name} · 14 players · 2 line presets")
else
  IO.puts("Seeds: data already present, skipping")
end
