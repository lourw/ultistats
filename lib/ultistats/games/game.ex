defmodule Ultistats.Games.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @formats [:usau_standard]
  @statuses [:in_progress, :finished, :abandoned]
  @first_pulls [:ours, :theirs]
  @line_sorts [:jersey, :name]
  @line_picker_sorts [:jersey, :name, :points]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "games" do
    field :opponent_name, :string
    field :format, Ecto.Enum, values: @formats
    field :status, Ecto.Enum, values: @statuses
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :first_pull, Ecto.Enum, values: @first_pulls
    field :line_sort, Ecto.Enum, values: @line_sorts, default: :jersey
    field :line_picker_sort, Ecto.Enum, values: @line_picker_sorts, default: :jersey

    belongs_to :team, Ultistats.Teams.Team
    belongs_to :ruleset, Ultistats.Games.Ruleset
    has_many :points, Ultistats.Games.Point, preload_order: [asc: :sequence]

    timestamps(type: :utc_datetime)
  end

  @doc "Valid `:format` enum values."
  def formats, do: @formats

  @doc "Valid `:status` enum values."
  def statuses, do: @statuses

  @doc "Valid `:first_pull` enum values."
  def first_pulls, do: @first_pulls

  @doc "Valid `:line_sort` enum values (the in-point on-field player order)."
  def line_sorts, do: @line_sorts

  @doc "Valid `:line_picker_sort` enum values (the between-points line picker order)."
  def line_picker_sorts, do: @line_picker_sorts

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :team_id,
      :ruleset_id,
      :opponent_name,
      :format,
      :status,
      :started_at,
      :ended_at,
      :first_pull,
      :line_sort,
      :line_picker_sort
    ])
    |> validate_required([
      :team_id,
      :opponent_name,
      :format,
      :status,
      :started_at,
      :first_pull,
      :line_sort,
      :line_picker_sort
    ])
    |> validate_length(:opponent_name, min: 1, max: 80)
    |> assoc_constraint(:team)
  end
end
