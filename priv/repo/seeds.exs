# Idempotent dev seed: one team, 14 players (8 MMP + 6 FMP), and two
# line presets. Re-running is a no-op as long as a team already exists.
#
# Run manually with: `mix run priv/repo/seeds.exs`
# Auto-runs on `mix phx.server` in dev (see lib/ultistats/application.ex).

alias Ultistats.{Repo, Teams}
alias Ultistats.Teams.Team

if Repo.aggregate(Team, :count, :id) == 0 do
  {:ok, team} = Teams.create_team(%{name: "The Misfits"})

  # 6 female-matching, 8 male-matching = 14 total.
  player_specs = [
    # FMP (6)
    {"Avery", "Stone", "1", :female_matching, :handler},
    {"Brooke", "Lee", "2", :female_matching, :cutter},
    {"Casey", "Park", "3", :female_matching, :cutter},
    {"Devon", "Reed", "4", :female_matching, :hybrid},
    {"Emery", "Vance", "5", :female_matching, :handler},
    {"Frankie", "Holt", "6", :female_matching, :cutter},
    # MMP (8)
    {"Gabe", "Quinn", "7", :male_matching, :handler},
    {"Hayden", "Cole", "8", :male_matching, :cutter},
    {"Ira", "Bell", "9", :male_matching, :hybrid},
    {"Jordan", "Diaz", "10", :male_matching, :handler},
    {"Kit", "Ng", "11", :male_matching, :cutter},
    {"Logan", "West", "12", :male_matching, :cutter},
    {"Marlowe", "Hart", "13", :male_matching, :handler},
    {"Niko", "Pham", "14", :male_matching, :hybrid}
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
