defmodule Ultistats.Repo.Migrations.CreatePoints do
  use Ecto.Migration

  def change do
    create table(:points, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :game_id,
          references(:games, type: :binary_id, on_delete: :delete_all),
          null: false

      add :sequence, :integer, null: false
      # scoring_team is set when the point ends (Ecto.Enum :ours | :theirs).
      add :scoring_team, :string, null: true
      # our_line_snapshot is %{"user_ids" => [<binary_id>, ...]}.
      # `:map` translates to jsonb on Postgres and TEXT on SQLite.
      add :our_line_snapshot, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:points, [:game_id, :sequence])
  end
end
