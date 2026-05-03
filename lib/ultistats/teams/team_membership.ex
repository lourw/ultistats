defmodule Ultistats.Teams.TeamMembership do
  @moduledoc """
  Join row connecting a `User` to a `Team`. Carries the user's role on
  that team (`:admin | :member`), whether they're an active player on
  the roster (`:is_player`), and an optional jersey number.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @roles [:admin, :member]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "team_memberships" do
    field :role, Ecto.Enum, values: @roles
    field :is_player, :boolean, default: true
    field :jersey_number, :string
    # Per-team position override. Nil means "fall back to the user's
    # default position" — see `Ultistats.Teams.resolved_position/1`.
    field :position, Ecto.Enum, values: Ultistats.Accounts.User.positions()

    belongs_to :user, Ultistats.Accounts.User
    belongs_to :team, Ultistats.Teams.Team

    timestamps(type: :utc_datetime)
  end

  @doc "Valid `:role` enum values."
  def roles, do: @roles

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :team_id, :role, :is_player, :jersey_number, :position])
    |> validate_required([:user_id, :team_id, :role])
    |> validate_length(:jersey_number, max: 4)
    |> validate_inclusion(:position, Ultistats.Accounts.User.positions())
    |> assoc_constraint(:user)
    |> assoc_constraint(:team)
    |> unique_constraint([:team_id, :user_id])
  end
end
