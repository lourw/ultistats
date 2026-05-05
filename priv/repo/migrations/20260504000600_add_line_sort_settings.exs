defmodule Ultistats.Repo.Migrations.AddLineSortSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :default_line_picker_sort, :string, null: false, default: "jersey"
    end

    alter table(:games) do
      add :line_picker_sort, :string, null: false, default: "jersey"
    end
  end
end
