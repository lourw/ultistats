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
    {"Avery", "Stone", "1", :female_matching},
    {"Brooke", "Lee", "2", :female_matching},
    {"Casey", "Park", "3", :female_matching},
    {"Devon", "Reed", "4", :female_matching},
    {"Emery", "Vance", "5", :female_matching},
    {"Frankie", "Holt", "6", :female_matching},
    # MMP (8)
    {"Gabe", "Quinn", "7", :male_matching},
    {"Hayden", "Cole", "8", :male_matching},
    {"Ira", "Bell", "9", :male_matching},
    {"Jordan", "Diaz", "10", :male_matching},
    {"Kit", "Ng", "11", :male_matching},
    {"Logan", "West", "12", :male_matching},
    {"Marlowe", "Hart", "13", :male_matching},
    {"Niko", "Pham", "14", :male_matching}
  ]

  players =
    Enum.map(player_specs, fn {first, last, jersey, gender} ->
      {:ok, p} =
        Teams.create_player(%{
          team_id: team.id,
          first_name: first,
          last_name: last,
          jersey_number: jersey,
          gender_role: gender
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
