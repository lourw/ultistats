defmodule Ultistats.Teams.LinePreset do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "line_presets" do
    field :name, :string

    belongs_to :team, Ultistats.Teams.Team

    many_to_many :users, Ultistats.Accounts.User,
      join_through: "line_preset_users",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Base changeset — casts and validates the scalar fields.

  The associated `:users` collection is *not* set here; the context
  layer loads the corresponding User rows (scoped to the same team
  for safety) and calls `put_assoc(:users, users)` separately.
  """
  def changeset(line_preset, attrs) do
    line_preset
    |> cast(attrs, [:name, :team_id])
    |> validate_required([:name, :team_id])
    |> validate_length(:name, min: 1, max: 80)
    |> assoc_constraint(:team)
  end
end
