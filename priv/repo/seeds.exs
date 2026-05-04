# Idempotent dev seed: one admin user, one team ("The Misfits"), 14
# stub-user players (8 MMP + 6 FMP), two line presets, and two rulesets.
# Re-running is a no-op as long as a team named "The Misfits" already
# exists.
#
# Run manually with: `mix run priv/repo/seeds.exs`
# Auto-runs on `mix phx.server` in dev (see lib/ultistats/application.ex).

alias Ultistats.{Games, Repo, Teams}
alias Ultistats.Teams.Team

# System rulesets (team_id = nil) — visible to every user. Idempotent.
Ultistats.Release.seed_system_rulesets()

if Repo.get_by(Ultistats.Accounts.User, email: "admin@admin.com") do
  IO.puts("Seeds: admin@admin.com already present, skipping")
else
  # 1) Admin user — real email/password so dev login works out of the box.
  # We bypass the registration changeset's 12-char password minimum here so
  # the dev login can be `admin` / `admin`. Production registration still
  # enforces the validation; the seed runs only in dev.
  admin_email = "admin@admin.com"
  admin_password = "admin"

  admin =
    %Ultistats.Accounts.User{}
    |> Ecto.Changeset.change(%{
      email: admin_email,
      hashed_password: Bcrypt.hash_pwd_salt(admin_password),
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()

  # Profile fields on the admin so the team-stats query treats them as a
  # full FMP/MMP/etc. player.
  {:ok, admin} =
    admin
    |> Ultistats.Accounts.User.profile_changeset(%{
      first_name: "Admin",
      last_name: "Misfit",
      gender_role: :male_matching,
      position: :handler
    })
    |> Repo.update()

  # 2) The team itself, with the admin's membership inserted in the
  # same Multi via create_team_with_admin/2.
  {:ok, %{team: team, membership: admin_membership}} =
    Teams.create_team_with_admin(%{name: "The Misfits", division: :mixed}, admin)

  # Backfill the jersey number on the admin membership — the helper
  # always inserts with role: :admin, is_player: true and no jersey.
  {:ok, _} =
    Teams.update_team_membership(admin_membership, %{jersey_number: "00"})

  # 3) Existing 14-player roster — created as stub users + memberships.
  player_specs = [
    # FMP (6) — jerseys intentionally shuffled vs first-name alpha order
    {"Brooke", "Lee", "3", :female_matching, :cutter},
    {"Avery", "Stone", "11", :female_matching, :handler},
    {"Casey", "Park", "01", :female_matching, :cutter},
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

  results =
    Enum.map(player_specs, fn {first, last, jersey, gender, position} ->
      {:ok, %{user: user, membership: _}} =
        Teams.create_member_with_stub_user(team, %{
          first_name: first,
          last_name: last,
          gender_role: gender,
          position: position,
          role: :member,
          is_player: true,
          jersey_number: jersey
        })

      {first, user}
    end)

  by_first =
    fn name ->
      {_, user} = Enum.find(results, fn {f, _} -> f == name end)
      user
    end

  # 4) Line presets — keyed off the new user_ids attribute on
  #    create_line_preset/1.
  o_line_user_ids =
    ["Hayden", "Ira", "Jordan", "Kit", "Avery", "Brooke", "Casey"]
    |> Enum.map(&by_first.(&1).id)

  d_line_user_ids =
    ["Logan", "Marlowe", "Niko", "Gabe", "Devon", "Emery", "Frankie"]
    |> Enum.map(&by_first.(&1).id)

  {:ok, _} =
    Teams.create_line_preset(%{
      team_id: team.id,
      name: "O-line",
      user_ids: o_line_user_ids
    })

  {:ok, _} =
    Teams.create_line_preset(%{
      team_id: team.id,
      name: "D-line",
      user_ids: d_line_user_ids
    })

  # 5) Rulesets — unchanged from the prior seed, scoped to the team.
  {:ok, _} =
    Games.create_ruleset(%{
      team_id: team.id,
      kind: :template,
      division: :mixed,
      name: "USAU Standard",
      score_cap: 15,
      halftime_target: 8,
      halftime_cap_minutes: nil,
      soft_cap_minutes: nil,
      hard_cap_minutes: nil,
      timeouts_per_half: 2,
      line_size: 7,
      gender_ratio_rule: :endzone,
      starting_male_count: 4,
      starting_female_count: 3
    })

  {:ok, _} =
    Games.create_ruleset(%{
      team_id: team.id,
      kind: :template,
      division: :mixed,
      name: "Hat League",
      score_cap: 13,
      halftime_target: 7,
      halftime_cap_minutes: nil,
      soft_cap_minutes: 50,
      hard_cap_minutes: 60,
      timeouts_per_half: 1,
      line_size: 7,
      gender_ratio_rule: :alternating,
      starting_male_count: 4,
      starting_female_count: 3
    })

  IO.puts(
    "Seeded: #{team.name} · admin=#{admin.email} · 14 stub-user players · 2 line presets · 2 rulesets"
  )
end

# A second, single-gender (open) team for the most common 7v7 use case —
# 14 male-matching members, no ratio enforcement.
if Repo.get_by(Team, name: "The Open Squad") do
  IO.puts("Seeds: 'The Open Squad' already present, skipping")
else
  admin =
    Repo.get_by(Ultistats.Accounts.User, email: "admin@admin.com") ||
      raise "Expected admin user to be seeded by the Misfits block above"

  {:ok, %{team: team, membership: admin_membership}} =
    Teams.create_team_with_admin(%{name: "The Open Squad", division: :open}, admin)

  {:ok, _} =
    Teams.update_team_membership(admin_membership, %{jersey_number: "00"})

  open_specs = [
    {"Sam", "Reyes", "1", :male_matching, :handler},
    {"Alex", "Park", "3", :male_matching, :handler},
    {"Charlie", "Mendez", "5", :male_matching, :hybrid},
    {"Drew", "Okonkwo", "7", :male_matching, :cutter},
    {"Eli", "Vargas", "9", :male_matching, :cutter},
    {"Finn", "Mori", "11", :male_matching, :handler},
    {"Greyson", "Tate", "13", :male_matching, :hybrid},
    {"Harper", "Ito", "15", :male_matching, :cutter},
    {"Indy", "Bauer", "17", :male_matching, :cutter},
    {"Jules", "Khan", "19", :male_matching, :handler},
    {"Kade", "Soto", "21", :male_matching, :hybrid},
    {"Lior", "Webb", "23", :male_matching, :cutter},
    {"Milo", "Frost", "25", :male_matching, :cutter},
    {"Nate", "Brooks", "27", :male_matching, :handler}
  ]

  open_results =
    Enum.map(open_specs, fn {first, last, jersey, gender, position} ->
      {:ok, %{user: user}} =
        Teams.create_member_with_stub_user(team, %{
          first_name: first,
          last_name: last,
          gender_role: gender,
          position: position,
          role: :member,
          is_player: true,
          jersey_number: jersey
        })

      {first, user}
    end)

  by_first_open = fn name ->
    {_, user} = Enum.find(open_results, fn {f, _} -> f == name end)
    user
  end

  o_ids =
    ["Sam", "Alex", "Charlie", "Drew", "Eli", "Finn", "Greyson"]
    |> Enum.map(&by_first_open.(&1).id)

  d_ids =
    ["Harper", "Indy", "Jules", "Kade", "Lior", "Milo", "Nate"]
    |> Enum.map(&by_first_open.(&1).id)

  {:ok, _} = Teams.create_line_preset(%{team_id: team.id, name: "O-line", user_ids: o_ids})
  {:ok, _} = Teams.create_line_preset(%{team_id: team.id, name: "D-line", user_ids: d_ids})

  {:ok, _} =
    Games.create_ruleset(%{
      team_id: team.id,
      kind: :template,
      division: :open,
      name: "Open Standard",
      score_cap: 15,
      halftime_target: 8,
      halftime_cap_minutes: nil,
      soft_cap_minutes: nil,
      hard_cap_minutes: nil,
      timeouts_per_half: 2,
      line_size: 7,
      gender_ratio_rule: :none
    })

  IO.puts("Seeded: #{team.name} · 14 male-matching members · 2 line presets · 1 :none ruleset")
end
