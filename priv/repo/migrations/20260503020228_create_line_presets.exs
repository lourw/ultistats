defmodule Ultistats.Repo.Migrations.CreateLinePresets do
  use Ecto.Migration

  def change do
    create table(:line_presets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :team_id, references(:teams, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:line_presets, [:team_id])
  end
end
