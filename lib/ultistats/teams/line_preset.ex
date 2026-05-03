defmodule Ultistats.Teams.LinePreset do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "line_presets" do
    field :name, :string

    belongs_to :team, Ultistats.Teams.Team

    many_to_many :players, Ultistats.Teams.Player,
      join_through: "line_preset_players",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Base changeset — casts and validates the scalar fields.

  The associated `:players` collection is *not* set here; the context
  layer loads the corresponding Player rows (scoped to the same team
  for safety) and calls `put_assoc(:players, players)` separately.
  """
  def changeset(line_preset, attrs) do
    line_preset
    |> cast(attrs, [:name, :team_id])
    |> validate_required([:name, :team_id])
    |> validate_length(:name, min: 1, max: 80)
    |> assoc_constraint(:team)
  end
end
