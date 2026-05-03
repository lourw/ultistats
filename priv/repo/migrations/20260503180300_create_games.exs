defmodule Ultistats.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :team_id,
          references(:teams, type: :binary_id, on_delete: :nothing),
          null: false

      # Nullable from the start: pre-Ruleset / templateless games read
      # defaults via Games.usau_standard_attrs/0. on_delete: :restrict —
      # a ruleset row referenced by any game cannot be deleted; the UI
      # archives instead.
      add :ruleset_id,
          references(:rulesets, type: :binary_id, on_delete: :restrict),
          null: true

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
    create index(:games, [:ruleset_id])
  end
end
