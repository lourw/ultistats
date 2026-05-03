defmodule Ultistats.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :team_id,
          references(:teams, type: :binary_id, on_delete: :nothing),
          null: false

      add :opponent_name, :string, null: false
      # format / status / first_pull are Ecto.Enum at the app layer.
      # See docs/DESIGN.md for the values.
      add :format, :string, null: false
      add :status, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime, null: true
      add :first_pull, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:games, [:team_id])

    create table(:points, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :game_id,
          references(:games, type: :binary_id, on_delete: :delete_all),
          null: false

      add :sequence, :integer, null: false
      # scoring_team is set when the point ends (Ecto.Enum :ours | :theirs).
      add :scoring_team, :string, null: true
      # our_line_snapshot is %{"player_ids" => [<binary_id>, ...]}.
      # `:map` translates to jsonb on Postgres and TEXT on SQLite.
      add :our_line_snapshot, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:points, [:game_id, :sequence])

    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :point_id,
          references(:points, type: :binary_id, on_delete: :delete_all),
          null: false

      add :sequence, :integer, null: false
      # type is Ecto.Enum :goal | :assist | :block | :turn at the app layer.
      add :type, :string, null: false

      add :player_id,
          references(:players, type: :binary_id, on_delete: :nilify_all),
          null: true

      add :occurred_at, :utc_datetime, null: false
      # Soft-delete timestamp; reads filter `deleted_at IS NULL`.
      add :deleted_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:point_id, :sequence])
    create index(:events, [:player_id])
  end
end
