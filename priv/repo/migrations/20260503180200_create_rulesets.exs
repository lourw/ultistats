defmodule Ultistats.Repo.Migrations.CreateRulesets do
  use Ecto.Migration

  def change do
    create table(:rulesets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :team_id,
          references(:teams, type: :binary_id, on_delete: :delete_all),
          null: false

      # Required only for `:template` rows; `:game_instance` rows are
      # anonymous clones, so the column itself is nullable.
      add :name, :string

      # kind / gender_ratio_rule / default_starting_ratio are Ecto.Enum
      # at the app layer. Stored as plain :string so migrations stay
      # adapter-portable across SQLite and Postgres.
      # Note: `:default_starting_ratio` is dropped in a later migration
      # (`20260503212315_replace_starting_ratio_with_counts`).
      add :kind, :string, null: false
      add :archived_at, :utc_datetime

      add :score_cap, :integer
      add :halftime_target, :integer
      add :halftime_cap_minutes, :integer
      add :soft_cap_minutes, :integer
      add :hard_cap_minutes, :integer
      add :timeouts_per_half, :integer, null: false, default: 2
      add :gender_ratio_rule, :string, null: false
      add :default_starting_ratio, :string

      timestamps(type: :utc_datetime)
    end

    create index(:rulesets, [:team_id, :kind, :archived_at])
  end
end
