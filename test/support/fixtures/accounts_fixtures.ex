defmodule Ultistats.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ultistats.Accounts` context.
  """

  import Ecto.Query

  alias Ultistats.Accounts
  alias Ultistats.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  @doc """
  Inserts an unconfirmed user (no `confirmed_at`) but with a password set.
  Useful for tests around the email-update confirmation flow that need a
  pre-existing user without a confirmation timestamp.
  """
  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user_with_password()

    user
  end

  @doc """
  Inserts a confirmed, password-having user. The default for tests that
  just need "some authenticated user".
  """
  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)
    Accounts.confirm_user!(user)
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  @doc """
  Returns the given user — registration already sets the password to
  `valid_user_password/0`. Kept for back-compat with tests written when
  password was set in a separate step.
  """
  def set_password(user), do: user

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Ultistats.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Ultistats.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
