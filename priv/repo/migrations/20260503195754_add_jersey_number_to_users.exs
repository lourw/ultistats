defmodule Ultistats.Repo.Migrations.AddJerseyNumberToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :jersey_number, :string
    end
  end
end
