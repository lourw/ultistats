defmodule Ultistats.Repo.Migrations.AddPositionToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      # position is enforced as Ecto.Enum at the application layer
      # (values: :handler | :cutter | :hybrid). Stored as plain :string
      # to keep migrations portable across SQLite and Postgres
      # (no DB CHECK constraint). The default only exists to backfill
      # existing rows — the changeset's validate_required ensures every
      # insert/update specifies a position.
      add :position, :string, null: false, default: "cutter"
    end
  end
end
