defmodule Ultistats.Games.Event do
  @moduledoc """
  A per-throw event recorded against a `Point`. Each event has a type
  plus optional `passer_id` and `receiver_id` (both nullable — `nil`
  means "Unknown", recorded when the tracker missed who threw or caught).

  Soft-deleted via `deleted_at`; all read paths must filter
  `deleted_at IS NULL`. Possession is derived event-by-event in the
  Games context — no possession state on the DB.

  See `docs/DESIGN.md` for the full per-type field-shape table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  # Per-type rules used by `validate_shape/1`:
  #   :passer  ⇒ passer_id allowed (nullable), receiver_id must be nil
  #   :both    ⇒ both ids allowed (nullable)
  #   :neither ⇒ both ids must be nil
  @shapes %{
    pull: :passer,
    catch: :both,
    throwaway: :passer,
    drop: :both,
    stall: :passer,
    goal: :both,
    block: :passer,
    opponent_turnover: :neither,
    opponent_goal: :neither,
    pick: :neither,
    foul: :neither
  }

  @types Map.keys(@shapes)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "events" do
    field :sequence, :integer
    field :type, Ecto.Enum, values: @types
    field :occurred_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :point, Ultistats.Games.Point
    belongs_to :passer, Ultistats.Teams.Player
    belongs_to :receiver, Ultistats.Teams.Player

    timestamps(type: :utc_datetime)
  end

  @doc "Valid `:type` enum values."
  def types, do: @types

  @doc """
  Returns the valid field shape for `type`:

    * `:passer`  — `passer_id` allowed, `receiver_id` must be nil.
    * `:both`    — both ids allowed.
    * `:neither` — both ids must be nil.
  """
  def shape(type), do: Map.fetch!(@shapes, type)

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :point_id,
      :sequence,
      :type,
      :passer_id,
      :receiver_id,
      :occurred_at,
      :deleted_at
    ])
    |> validate_required([:point_id, :sequence, :type, :occurred_at])
    |> validate_shape()
    |> assoc_constraint(:point)
    |> maybe_assoc_constraint(:passer, :passer_id)
    |> maybe_assoc_constraint(:receiver, :receiver_id)
  end

  @doc """
  Changeset for the timeline edit flow — only `:type`, `:passer_id`,
  and `:receiver_id` are editable. `:sequence`, `:occurred_at`, and
  `:deleted_at` are intentionally not cast.
  """
  def update_changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :passer_id, :receiver_id])
    |> validate_required([:type])
    |> validate_shape()
    |> maybe_assoc_constraint(:passer, :passer_id)
    |> maybe_assoc_constraint(:receiver, :receiver_id)
  end

  defp validate_shape(changeset) do
    case get_field(changeset, :type) do
      nil ->
        changeset

      type ->
        case shape(type) do
          :passer ->
            forbid_field(changeset, :receiver_id, type)

          :neither ->
            changeset
            |> forbid_field(:passer_id, type)
            |> forbid_field(:receiver_id, type)

          :both ->
            changeset
        end
    end
  end

  defp forbid_field(changeset, field, type) do
    case get_field(changeset, field) do
      nil ->
        changeset

      _ ->
        add_error(changeset, field, "is not allowed for #{type} events")
    end
  end

  defp maybe_assoc_constraint(changeset, assoc, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _ -> assoc_constraint(changeset, assoc)
    end
  end
end
