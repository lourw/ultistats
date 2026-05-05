defmodule Ultistats.Repo.Migrations.AddUserSettingsAndGamePlayerSort do
  use Ecto.Migration

  def change do
    create table(:user_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :default_line_sort, :string, null: false, default: "jersey"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_settings, [:user_id])

    alter table(:games) do
      add :line_sort, :string, null: false, default: "jersey"
    end
  end
end
