defmodule Ultistats.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sequence, :integer, null: false
      # `type` is an Ecto.Enum at the application layer (see
      # lib/ultistats/games/event.ex). Stored as a plain string so this
      # migration stays portable across SQLite/Postgres — no DB CHECK.
      add :type, :string, null: false
      add :occurred_at, :utc_datetime, null: false
      # Soft-delete column. All read paths filter deleted_at IS NULL.
      # We deliberately do NOT create a partial index on this column —
      # PG-only predicate syntax. Add a real index if perf demands.
      add :deleted_at, :utc_datetime
      add :point_id, references(:points, on_delete: :delete_all, type: :binary_id), null: false
      # nilify_all: removing a player should not destroy historical
      # events; the event survives with player_id = nil.
      add :player_id, references(:players, on_delete: :nilify_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:point_id, :sequence])
    create index(:events, [:player_id])
  end
end
