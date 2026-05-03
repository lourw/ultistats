defmodule Ultistats.Teams.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @divisions [:open, :womens, :mixed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "teams" do
    field :name, :string
    field :division, Ecto.Enum, values: @divisions, default: :open

    timestamps(type: :utc_datetime)
  end

  def divisions, do: @divisions

  @doc false
  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :division])
    |> validate_required([:name, :division])
    |> validate_length(:name, min: 1, max: 80)
  end
end
