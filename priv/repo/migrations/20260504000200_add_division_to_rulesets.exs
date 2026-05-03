defmodule Ultistats.Repo.Migrations.AddDivisionToRulesets do
  use Ecto.Migration

  def change do
    alter table(:rulesets) do
      add :division, :string, null: false, default: "open"
    end

    create index(:rulesets, [:team_id, :division])
  end
end
