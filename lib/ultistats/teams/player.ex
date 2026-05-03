defmodule Ultistats.Teams.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @gender_roles [:female_matching, :male_matching]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "players" do
    field :name, :string
    field :jersey_number, :string
    field :gender_role, Ecto.Enum, values: @gender_roles

    belongs_to :team, Ultistats.Teams.Team

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid gender role values for the mixed-division
  prevailing-gender rule (USAU FMP/MMP).
  """
  def gender_roles, do: @gender_roles

  @doc false
  def changeset(player, attrs) do
    player
    |> cast(attrs, [:name, :jersey_number, :gender_role, :team_id])
    |> validate_required([:name, :jersey_number, :gender_role, :team_id])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:jersey_number, min: 1, max: 4)
    |> assoc_constraint(:team)
  end
end
