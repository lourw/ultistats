defmodule Ultistats.Repo.Migrations.AddGameIdToEventsAndNullablePointId do
  use Ecto.Migration

  # SQLite3 doesn't support `ALTER COLUMN`, so on that adapter we
  # rebuild the table from scratch. Postgres uses `modify` with `:from`.
  def up do
    case repo().__adapter__() do
      Ecto.Adapters.SQLite3 -> sqlite_up()
      _ -> postgres_up()
    end
  end

  def down do
    case repo().__adapter__() do
      Ecto.Adapters.SQLite3 -> sqlite_down()
      _ -> postgres_down()
    end
  end

  defp sqlite_up do
    execute("""
    CREATE TABLE events_new (
      id TEXT PRIMARY KEY,
      point_id TEXT NULL CONSTRAINT events_point_id_fkey REFERENCES points(id) ON DELETE CASCADE,
      game_id TEXT NOT NULL CONSTRAINT events_game_id_fkey REFERENCES games(id) ON DELETE CASCADE,
      sequence INTEGER NOT NULL,
      type TEXT NOT NULL,
      passer_user_id TEXT NULL CONSTRAINT events_passer_user_id_fkey REFERENCES users(id) ON DELETE SET NULL,
      receiver_user_id TEXT NULL CONSTRAINT events_receiver_user_id_fkey REFERENCES users(id) ON DELETE SET NULL,
      occurred_at TEXT NOT NULL,
      deleted_at TEXT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO events_new (
      id, point_id, game_id, sequence, type, passer_user_id, receiver_user_id,
      occurred_at, deleted_at, inserted_at, updated_at
    )
    SELECT
      e.id, e.point_id, p.game_id, e.sequence, e.type, e.passer_user_id, e.receiver_user_id,
      e.occurred_at, e.deleted_at, e.inserted_at, e.updated_at
    FROM events e
    INNER JOIN points p ON p.id = e.point_id
    """)

    execute("DROP TABLE events")
    execute("ALTER TABLE events_new RENAME TO events")

    create index(:events, [:point_id, :sequence])
    create index(:events, [:passer_user_id])
    create index(:events, [:receiver_user_id])
    create index(:events, [:game_id])
  end

  defp sqlite_down do
    execute("""
    CREATE TABLE events_old (
      id TEXT PRIMARY KEY,
      point_id TEXT NOT NULL CONSTRAINT events_point_id_fkey REFERENCES points(id) ON DELETE CASCADE,
      sequence INTEGER NOT NULL,
      type TEXT NOT NULL,
      passer_user_id TEXT NULL CONSTRAINT events_passer_user_id_fkey REFERENCES users(id) ON DELETE SET NULL,
      receiver_user_id TEXT NULL CONSTRAINT events_receiver_user_id_fkey REFERENCES users(id) ON DELETE SET NULL,
      occurred_at TEXT NOT NULL,
      deleted_at TEXT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO events_old (
      id, point_id, sequence, type, passer_user_id, receiver_user_id,
      occurred_at, deleted_at, inserted_at, updated_at
    )
    SELECT
      id, point_id, sequence, type, passer_user_id, receiver_user_id,
      occurred_at, deleted_at, inserted_at, updated_at
    FROM events
    WHERE point_id IS NOT NULL
    """)

    execute("DROP TABLE events")
    execute("ALTER TABLE events_old RENAME TO events")

    create index(:events, [:point_id, :sequence])
    create index(:events, [:passer_user_id])
    create index(:events, [:receiver_user_id])
  end

  defp postgres_up do
    alter table(:events) do
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: true
    end

    flush()

    execute(
      "UPDATE events SET game_id = (SELECT game_id FROM points WHERE points.id = events.point_id) WHERE game_id IS NULL"
    )

    alter table(:events) do
      modify :game_id, references(:games, type: :binary_id, on_delete: :delete_all),
        null: false,
        from: references(:games, type: :binary_id, on_delete: :delete_all)

      modify :point_id, references(:points, type: :binary_id, on_delete: :delete_all),
        null: true,
        from: references(:points, type: :binary_id, on_delete: :delete_all)
    end

    create index(:events, [:game_id])
  end

  defp postgres_down do
    drop index(:events, [:game_id])

    execute("DELETE FROM events WHERE point_id IS NULL")

    alter table(:events) do
      modify :point_id, references(:points, type: :binary_id, on_delete: :delete_all),
        null: false,
        from: references(:points, type: :binary_id, on_delete: :delete_all)

      remove :game_id
    end
  end
end
