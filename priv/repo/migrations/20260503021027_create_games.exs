defmodule Ultistats.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :opponent_name, :string, null: false
      # `format`, `status`, `first_pull` are Ecto.Enum at the application
      # layer (see lib/ultistats/games/game.ex). We store them as plain
      # strings with no DB CHECK so this migration stays portable across
      # SQLite (dev/test) and Postgres (prod) — see docs/DESIGN.md.
      add :format, :string, null: false
      add :status, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :first_pull, :string, null: false
      # Deleting a team that has games is blocked at the FK layer for
      # now; surfacing a friendlier error is a follow-up.
      add :team_id, references(:teams, on_delete: :nothing, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:games, [:team_id])
  end
end
