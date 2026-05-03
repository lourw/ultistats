defmodule UltistatsWeb.UserRegistrationController do
  use UltistatsWeb, :controller

  alias Ultistats.Accounts
  alias Ultistats.Accounts.User
  alias UltistatsWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user_with_password(user_params) do
      {:ok, user} ->
        user = Accounts.confirm_user!(user)

        # Preserve any pre-register `:user_return_to` (e.g. a `/join/:token`
        # the visitor was bounced from). Only fall back to /teams when
        # nothing was stashed.
        return_to = get_session(conn, :user_return_to) || ~p"/teams"

        conn
        |> put_flash(:info, "Account created. Welcome!")
        |> put_session(:user_return_to, return_to)
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
