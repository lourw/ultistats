defmodule Ultistats.Repo.Migrations.ReplaceStartingRatioWithCounts do
  use Ecto.Migration

  def change do
    alter table(:rulesets) do
      add :starting_male_count, :integer
      add :starting_female_count, :integer
    end

    # Backfill existing rows. Adapter-portable raw SQL — works on both
    # SQLite (dev/test) and Postgres (prod).
    execute(
      """
      UPDATE rulesets
         SET starting_male_count = 4, starting_female_count = 3
       WHERE default_starting_ratio = 'four_men_three_women'
      """,
      ""
    )

    execute(
      """
      UPDATE rulesets
         SET starting_male_count = 3, starting_female_count = 4
       WHERE default_starting_ratio = 'three_men_four_women'
      """,
      ""
    )

    alter table(:rulesets) do
      remove :default_starting_ratio, :string
    end
  end
end
