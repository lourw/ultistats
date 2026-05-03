defmodule Ultistats.Repo.Migrations.AddLineSizeToRulesets do
  use Ecto.Migration

  def change do
    alter table(:rulesets) do
      add :line_size, :integer, null: false, default: 7
    end
  end
end
