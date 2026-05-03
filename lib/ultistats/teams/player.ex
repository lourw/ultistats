defmodule Ultistats.Teams.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @gender_roles [:female_matching, :male_matching]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "players" do
    field :first_name, :string
    field :last_name, :string
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

  @doc """
  Returns the player's display name — `"First Last"`. Used everywhere
  the UI needs a single-string label for a player.
  """
  def display_name(%__MODULE__{first_name: first, last_name: last}) do
    [first, last]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  @doc false
  def changeset(player, attrs) do
    player
    |> cast(attrs, [:first_name, :last_name, :jersey_number, :gender_role, :team_id])
    |> validate_required([:first_name, :last_name, :gender_role, :team_id])
    |> validate_length(:first_name, min: 1, max: 40)
    |> validate_length(:last_name, min: 1, max: 40)
    |> validate_length(:jersey_number, max: 4)
    |> assoc_constraint(:team)
  end
end
