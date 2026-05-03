defmodule Ultistats.Repo.Migrations.CreateTeamMemberships do
  use Ecto.Migration

  def change do
    create table(:team_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :team_id,
          references(:teams, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      # role is enforced as Ecto.Enum at the application layer
      # (values: :admin | :member). Stored as plain :string for
      # adapter portability.
      add :role, :string, null: false
      add :is_player, :boolean, null: false, default: true
      add :jersey_number, :string

      timestamps(type: :utc_datetime)
    end

    create index(:team_memberships, [:team_id])
    create unique_index(:team_memberships, [:team_id, :user_id])
  end
end
