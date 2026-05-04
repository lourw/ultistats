defmodule Ultistats.Repo.Migrations.RevertRulesetTeamIdNullable do
  use Ecto.Migration

  def change do
    # Drop any rows that were seeded as system (team-less) rulesets
    # before reinstating the NOT NULL constraint on team_id.
    execute(
      "DELETE FROM rulesets WHERE team_id IS NULL",
      "-- no-op on rollback"
    )

    alter table(:rulesets) do
      modify :team_id, references(:teams, type: :binary_id, on_delete: :delete_all),
        null: false,
        from: references(:teams, type: :binary_id, on_delete: :delete_all)
    end
  end
end
