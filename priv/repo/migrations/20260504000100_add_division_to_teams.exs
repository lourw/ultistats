defmodule Ultistats.Repo.Migrations.AddDivisionToTeams do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :division, :string, null: false, default: "open"
    end
  end
end
