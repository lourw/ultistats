defmodule Ultistats.Repo.Migrations.MakeRulesetTeamIdNullable do
  use Ecto.Migration

  def change do
    alter table(:rulesets) do
      modify :team_id, references(:teams, type: :binary_id, on_delete: :delete_all),
        null: true,
        from: references(:teams, type: :binary_id, on_delete: :delete_all)
    end
  end
end
