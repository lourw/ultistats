defmodule Ultistats.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :point_id,
          references(:points, type: :binary_id, on_delete: :delete_all),
          null: false

      add :sequence, :integer, null: false
      # type is Ecto.Enum at the app layer — full per-throw set
      # (pull / catch / throwaway / drop / stall / goal / block /
      # opponent_turnover / opponent_goal / pick / foul).
      add :type, :string, null: false

      # Passer / receiver are both nullable — `nil` means "Unknown"
      # (the tracker missed who threw or caught it). Per-type field
      # shape is enforced in `Event.changeset/2`.
      add :passer_user_id,
          references(:users, type: :binary_id, on_delete: :nilify_all),
          null: true

      add :receiver_user_id,
          references(:users, type: :binary_id, on_delete: :nilify_all),
          null: true

      add :occurred_at, :utc_datetime, null: false
      # Soft-delete timestamp; reads filter `deleted_at IS NULL`.
      add :deleted_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:point_id, :sequence])
    create index(:events, [:passer_user_id])
    create index(:events, [:receiver_user_id])
  end
end
