defmodule Ultistats.Accounts do
  @moduledoc """
  The Accounts context.

  ## Stub users

  A "stub user" is a `%User{}` row created from a roster without an actual
  human signing up first. Stub users:

    * have a sentinel email of the form `"stub-<uuid>@local.invalid"` so the
      unique-email constraint is satisfied without colliding with any real
      address,
    * have a `nil` `hashed_password` (they cannot log in),
    * have a `nil` `claimed_at` (claim flow is deferred to a later phase).

  The team owner can create stub users via `create_stub_user/1` to seed
  rosters before invitations are sent. When a real human registers and
  links to a stub, the stub is claimed (claim mechanics intentionally
  deferred — see Phase 2+).
  """

  import Ecto.Query, warn: false
  alias Ultistats.Repo

  alias Ultistats.Accounts.{User, UserToken, UserNotifier}
  alias Ultistats.Games.Event
  alias Ultistats.Teams.TeamMembership

  # Stub-claim tokens are stateless — `Phoenix.Token.sign/3` carries the
  # stub user's id signed by the endpoint secret. Seven days is long
  # enough for an admin to share a copied link without keeping a token
  # table around.
  @stub_claim_salt "stub claim"
  @stub_claim_max_age 60 * 60 * 24 * 7

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Returns an `%Ecto.Changeset{}` for a new registration (email +
  password). Used by the registration form to render the empty state.

  Defaults to `hash_password: false` and `validate_unique: false` so
  the form can render unsubmitted without spurious DB lookups.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_unique: false)
  end

  @doc """
  Registers a user with email + password. The caller (typically
  `UserRegistrationController`) is responsible for confirming the
  account and starting a session — this function just inserts.

  ## Examples

      iex> register_user_with_password(%{email: "a@b.co", password: "valid_password_12345"})
      {:ok, %User{}}

      iex> register_user_with_password(%{email: "bad", password: "short"})
      {:error, %Ecto.Changeset{}}

  """
  def register_user_with_password(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Marks a user as confirmed (sets `confirmed_at` to now). Returns the
  updated user. Used right after registration so newly-signed-up users
  can act on the app immediately without an email round-trip.
  """
  def confirm_user!(%User{} = user) do
    user
    |> User.confirm_changeset()
    |> Repo.update!()
  end

  @doc """
  Creates a stub user — a roster placeholder with no password and a
  sentinel email. Requires `:first_name`, `:last_name`, `:gender_role`,
  and `:position` in `attrs`.

  Returns `{:ok, %User{}}` or `{:error, %Ecto.Changeset{}}`. See the
  module doc for the full stub-user contract.
  """
  def create_stub_user(attrs) when is_map(attrs) do
    sentinel_email = "stub-#{Ecto.UUID.generate()}@local.invalid"

    attrs
    |> normalize_attrs()
    |> Map.put(:email, sentinel_email)
    |> User.stub_changeset()
    |> Repo.insert()
  end

  defp normalize_attrs(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Ultistats.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking profile changes.
  """
  def change_user_profile(%User{} = user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates the user's ultimate-domain profile fields (name, jersey
  number, gender role, position).
  """
  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Ultistats.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Stub-claim tokens

  @doc """
  Signs a stateless claim token for `stub_user`. Admins copy this URL
  off a stub roster row and hand it to the real human; the recipient
  visits `/claim/:token` and either logs in or registers, then confirms
  the claim. See `verify_stub_claim_token/1` and `claim_stub_user/2`.
  """
  def generate_stub_claim_token(%User{id: id}) do
    Phoenix.Token.sign(UltistatsWeb.Endpoint, @stub_claim_salt, id)
  end

  @doc """
  Verifies a stub-claim `token`. Returns `{:ok, %User{}}` when the
  signed user still exists, or `{:error, :invalid}` when the signature
  is bad / expired or the stub has already been claimed (and deleted).
  """
  def verify_stub_claim_token(token) when is_binary(token) do
    case Phoenix.Token.verify(UltistatsWeb.Endpoint, @stub_claim_salt, token,
           max_age: @stub_claim_max_age
         ) do
      {:ok, user_id} ->
        case Repo.get(User, user_id) do
          nil -> {:error, :invalid}
          %User{} = user -> {:ok, user}
        end

      {:error, _reason} ->
        {:error, :invalid}
    end
  end

  def verify_stub_claim_token(_), do: {:error, :invalid}

  @doc """
  Claims `stub` on behalf of `claimer`, reassigning the stub's
  TeamMembership rows and `Event.passer_user_id` / `:receiver_user_id`
  references to the claimer, then deleting the stub user.

  The whole reassignment runs in a single `Ecto.Multi` transaction.

  Returns:

    * `{:ok, %{teams: [team_id, ...]}}` on success — `:teams` is the
      list of team ids the claimer was newly added to (in stub order).
    * `{:error, :same_user}` if `stub.id == claimer.id`.
    * `{:error, :not_a_stub}` if `stub.claimed_at` is set (i.e. it's
      already a real, claimed user).
    * `{:error, :conflicting_membership, [team_id, ...]}` if the
      claimer is already a member of any team where the stub also has
      a membership. Surfaces explicitly so the admin/UI can reconcile.
  """
  def claim_stub_user(%User{} = stub, %User{} = claimer) do
    cond do
      stub.id == claimer.id ->
        {:error, :same_user}

      not is_nil(stub.claimed_at) ->
        {:error, :not_a_stub}

      true ->
        do_claim_stub_user(stub, claimer)
    end
  end

  defp do_claim_stub_user(%User{} = stub, %User{} = claimer) do
    stub_team_ids =
      from(m in TeamMembership, where: m.user_id == ^stub.id, select: m.team_id)
      |> Repo.all()

    claimer_team_ids =
      from(m in TeamMembership,
        where: m.user_id == ^claimer.id and m.team_id in ^stub_team_ids,
        select: m.team_id
      )
      |> Repo.all()

    case claimer_team_ids do
      [] ->
        run_claim_multi(stub, claimer, stub_team_ids)

      conflicts ->
        {:error, :conflicting_membership, conflicts}
    end
  end

  defp run_claim_multi(%User{} = stub, %User{} = claimer, stub_team_ids) do
    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update_all(
        :memberships,
        from(m in TeamMembership, where: m.user_id == ^stub.id),
        set: [user_id: claimer.id, updated_at: DateTime.utc_now(:second)]
      )
      |> Ecto.Multi.update_all(
        :events_passer,
        from(e in Event, where: e.passer_user_id == ^stub.id),
        set: [passer_user_id: claimer.id, updated_at: DateTime.utc_now(:second)]
      )
      |> Ecto.Multi.update_all(
        :events_receiver,
        from(e in Event, where: e.receiver_user_id == ^stub.id),
        set: [receiver_user_id: claimer.id, updated_at: DateTime.utc_now(:second)]
      )
      |> Ecto.Multi.delete(:stub, stub)

    case Repo.transaction(multi) do
      {:ok, _changes} -> {:ok, %{teams: stub_team_ids}}
      {:error, _step, _value, _changes} -> {:error, :claim_failed}
    end
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
