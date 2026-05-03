defmodule Ultistats.Games.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @formats [:usau_standard]
  @statuses [:in_progress, :finished, :abandoned]
  @first_pulls [:ours, :theirs]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "games" do
    field :opponent_name, :string
    field :format, Ecto.Enum, values: @formats
    field :status, Ecto.Enum, values: @statuses
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :first_pull, Ecto.Enum, values: @first_pulls

    belongs_to :team, Ultistats.Teams.Team
    has_many :points, Ultistats.Games.Point, preload_order: [asc: :sequence]

    timestamps(type: :utc_datetime)
  end

  @doc "Valid `:format` enum values."
  def formats, do: @formats

  @doc "Valid `:status` enum values."
  def statuses, do: @statuses

  @doc "Valid `:first_pull` enum values."
  def first_pulls, do: @first_pulls

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :team_id,
      :opponent_name,
      :format,
      :status,
      :started_at,
      :ended_at,
      :first_pull
    ])
    |> validate_required([
      :team_id,
      :opponent_name,
      :format,
      :status,
      :started_at,
      :first_pull
    ])
    |> validate_length(:opponent_name, min: 1, max: 80)
    |> assoc_constraint(:team)
  end
end
