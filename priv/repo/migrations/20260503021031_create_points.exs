defmodule Ultistats.Repo.Migrations.CreatePoints do
  use Ecto.Migration

  def change do
    create table(:points, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sequence, :integer, null: false
      # scoring_team is nullable: stays nil while the point is in
      # progress, set to "ours" or "theirs" when the point ends.
      add :scoring_team, :string
      # `:map` is portable: jsonb on Postgres, JSON-encoded text on
      # SQLite. Stores the line as %{"player_ids" => [...]}.
      add :our_line_snapshot, :map, null: false
      add :game_id, references(:games, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:points, [:game_id, :sequence])
  end
end
