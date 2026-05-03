defmodule Ultistats.Repo.Migrations.AddThrowTrackingToEvents do
  use Ecto.Migration

  def change do
    rename table(:events), :player_id, to: :passer_id

    alter table(:events) do
      add :receiver_id,
          references(:players, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    create index(:events, [:receiver_id])
  end
end
