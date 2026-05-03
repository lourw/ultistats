defmodule Ultistats.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :jersey_number, :string, null: false
      # gender_role is an Ecto.Enum at the application layer with values
      # :female_matching | :male_matching. We deliberately do NOT add a DB
      # CHECK constraint so this migration stays portable across SQLite
      # (dev/test) and Postgres (prod) — see docs/DESIGN.md adapter rules.
      add :gender_role, :string, null: false
      add :team_id, references(:teams, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:players, [:team_id])
  end
end
