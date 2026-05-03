defmodule Ultistats.Repo.Migrations.CreateLinePresets do
  use Ecto.Migration

  def change do
    create table(:line_presets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :team_id,
          references(:teams, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:line_presets, [:team_id])

    # Join table for the many_to_many between line_presets and players.
    # No timestamps — Ecto's many_to_many with a string `join_through`
    # uses insert_all and does not populate timestamp columns.
    create table(:line_preset_players, primary_key: false) do
      add :line_preset_id,
          references(:line_presets, type: :binary_id, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :player_id,
          references(:players, type: :binary_id, on_delete: :delete_all),
          null: false,
          primary_key: true
    end

    create index(:line_preset_players, [:player_id])
  end
end
