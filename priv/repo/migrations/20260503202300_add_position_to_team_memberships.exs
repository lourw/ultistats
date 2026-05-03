defmodule Ultistats.Repo.Migrations.AddPositionToTeamMemberships do
  use Ecto.Migration

  def change do
    alter table(:team_memberships) do
      # position is enforced as Ecto.Enum at the application layer
      # (values: :handler | :cutter | :hybrid). Stored as plain :string
      # for adapter portability. Nullable: nil means "fall back to the
      # user's default position".
      add :position, :string
    end
  end
end
