defmodule Ultistats.Repo.Migrations.AddStartedEndedAtToPoints do
  use Ecto.Migration

  def up do
    alter table(:points) do
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime
    end

    flush()

    execute("UPDATE points SET started_at = inserted_at WHERE started_at IS NULL")

    execute(
      "UPDATE points SET ended_at = updated_at WHERE ended_at IS NULL AND scoring_team IS NOT NULL"
    )
  end

  def down do
    alter table(:points) do
      remove :started_at
      remove :ended_at
    end
  end
end
