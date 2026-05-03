defmodule Ultistats.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @gender_roles [:female_matching, :male_matching]
  @positions [:handler, :cutter, :hybrid]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    # Ultimate-domain profile fields (formerly on Ultistats.Teams.Player).
    # Stub users (created from a roster, not yet self-registered) carry
    # these but have a sentinel email and a null hashed_password until the
    # claim flow runs.
    field :first_name, :string
    field :last_name, :string
    field :gender_role, Ecto.Enum, values: @gender_roles
    field :position, Ecto.Enum, values: @positions
    field :jersey_number, :string
    field :claimed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid gender role values for the mixed-division
  prevailing-gender rule (USAU FMP/MMP).
  """
  def gender_roles, do: @gender_roles

  @doc """
  Returns the list of valid on-field positions.
  """
  def positions, do: @positions

  @doc """
  Returns the user's display name — `"First Last"`. Used everywhere
  the UI needs a single-string label for a user/player.
  """
  def display_name(%__MODULE__{first_name: first, last_name: last}) do
    [first, last]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  @doc """
  A user changeset for registration with email and password. Used by the
  signup form — validates both fields, hashes the password, and (combined
  with the controller setting `confirmed_at`) yields an immediately
  usable, logged-in user.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Ultistats.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A changeset for the ultimate-domain profile fields
  (`first_name`, `last_name`, `gender_role`, `position`). Used when
  registering a real user (alongside email/password changesets) and when
  editing profile metadata. Independent of email/password — does not
  touch credentials.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:first_name, :last_name, :gender_role, :position, :jersey_number])
    |> validate_required([:first_name, :last_name, :gender_role, :position])
    |> validate_length(:first_name, min: 1, max: 40)
    |> validate_length(:last_name, min: 1, max: 40)
    |> validate_length(:jersey_number, max: 4)
  end

  @doc """
  A changeset for stub users created from a roster (no password yet, no
  self-registration yet). Casts the sentinel email plus the four profile
  fields. The `email` is generated by the caller (see
  `Ultistats.Accounts.create_stub_user/1`) — this changeset just
  validates and persists it.
  """
  def stub_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:email, :first_name, :last_name, :gender_role, :position])
    |> validate_required([:email, :first_name, :last_name, :gender_role, :position])
    |> validate_length(:first_name, min: 1, max: 40)
    |> validate_length(:last_name, min: 1, max: 40)
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Ultistats.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
