defmodule Ultistats.Repo.Migrations.AddRulesetIdToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      # Nullable: pre-Ruleset games (and games started without a
      # template) read defaults via Games.usau_standard_attrs/0.
      # on_delete: :restrict — a ruleset row referenced by any game
      # cannot be deleted; the UI archives instead.
      add :ruleset_id,
          references(:rulesets, type: :binary_id, on_delete: :restrict),
          null: true
    end

    create index(:games, [:ruleset_id])
  end
end
