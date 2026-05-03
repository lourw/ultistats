defmodule Ultistats.Repo.Migrations.CreateLinePresetPlayers do
  use Ecto.Migration

  def change do
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
