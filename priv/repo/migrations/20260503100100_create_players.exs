defmodule Ultistats.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :team_id,
          references(:teams, type: :binary_id, on_delete: :nothing),
          null: false

      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :jersey_number, :string, null: true
      # gender_role is enforced as Ecto.Enum at the application layer
      # (values: :female_matching | :male_matching). Stored as plain
      # :string to keep migrations portable across SQLite and Postgres
      # (no DB CHECK constraint).
      add :gender_role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:players, [:team_id])
  end
end
