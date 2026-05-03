defmodule Ultistats.Games.Point do
  @moduledoc """
  A `Point` is one possession sequence within a `Game`, ending when one
  team scores. `scoring_team` is `nil` while the point is in progress.

  ## `our_line_snapshot`

  The list of user ids on the field for this point is denormalized
  here so historical points stay correct if a player is later removed
  from the team's roster.

  Stored as a `:map` (portable across SQLite and Postgres — see
  `docs/DESIGN.md` adapter rules) under a single key:

      %{"user_ids" => [<user_id>, <user_id>, ...]}

  Use string keys ("user_ids") so JSON round-trips on SQLite leave the
  shape unchanged.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @scoring_teams [:ours, :theirs]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "points" do
    field :sequence, :integer
    field :scoring_team, Ecto.Enum, values: @scoring_teams
    field :our_line_snapshot, :map
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :game, Ultistats.Games.Game
    has_many :events, Ultistats.Games.Event, preload_order: [asc: :sequence]

    timestamps(type: :utc_datetime)
  end

  @doc "Valid `:scoring_team` enum values."
  def scoring_teams, do: @scoring_teams

  @doc false
  def changeset(point, attrs) do
    point
    |> cast(attrs, [
      :game_id,
      :sequence,
      :scoring_team,
      :our_line_snapshot,
      :started_at,
      :ended_at
    ])
    |> validate_required([:game_id, :sequence, :our_line_snapshot])
    |> unique_constraint([:game_id, :sequence], name: :points_game_id_sequence_index)
    |> assoc_constraint(:game)
  end
end
