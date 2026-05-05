defmodule Ultistats.Accounts.UserSettings do
  @moduledoc """
  Per-user preferences (1:1 with `User`). Lazy-created on first read so
  every existing user picks up the schema defaults without a backfill.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @line_sorts [:jersey, :name]
  @line_picker_sorts [:jersey, :name, :points]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_settings" do
    field :default_line_sort, Ecto.Enum, values: @line_sorts, default: :jersey
    field :default_line_picker_sort, Ecto.Enum, values: @line_picker_sorts, default: :jersey

    belongs_to :user, Ultistats.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Valid `:default_line_sort` enum values."
  def line_sorts, do: @line_sorts

  @doc "Valid `:default_line_picker_sort` enum values."
  def line_picker_sorts, do: @line_picker_sorts

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:user_id, :default_line_sort, :default_line_picker_sort])
    |> validate_required([:user_id, :default_line_sort, :default_line_picker_sort])
    |> assoc_constraint(:user)
    |> unique_constraint(:user_id)
  end
end
