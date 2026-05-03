defmodule Ultistats.Games.Event do
  @moduledoc """
  An in-game event recorded against a `Point` — one of `:goal`,
  `:assist`, `:block`, `:turn`. Soft-deleted via `deleted_at`; all read
  paths must filter `deleted_at IS NULL`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @types [:goal, :assist, :block, :turn]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "events" do
    field :sequence, :integer
    field :type, Ecto.Enum, values: @types
    field :occurred_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :point, Ultistats.Games.Point
    belongs_to :player, Ultistats.Teams.Player

    timestamps(type: :utc_datetime)
  end

  @doc "Valid `:type` enum values."
  def types, do: @types

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:point_id, :sequence, :type, :player_id, :occurred_at, :deleted_at])
    |> validate_required([:point_id, :sequence, :type, :occurred_at])
    |> assoc_constraint(:point)
    |> maybe_assoc_constraint_player()
  end

  @doc """
  Changeset for the timeline edit flow — only `:type` and `:player_id`
  are editable. `:sequence`, `:occurred_at`, and `:deleted_at` are
  intentionally not cast.
  """
  def update_changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :player_id])
    |> validate_required([:type])
    |> maybe_assoc_constraint_player()
  end

  defp maybe_assoc_constraint_player(changeset) do
    case get_field(changeset, :player_id) do
      nil -> changeset
      _ -> assoc_constraint(changeset, :player)
    end
  end
end
