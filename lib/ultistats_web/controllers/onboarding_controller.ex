defmodule UltistatsWeb.OnboardingController do
  use UltistatsWeb, :controller

  alias Ultistats.Accounts

  def edit(conn, _params) do
    user = conn.assigns.current_scope.user
    render(conn, :edit, profile_changeset: Accounts.change_user_profile(user))
  end

  def update(conn, %{"user" => user_params}) do
    user = conn.assigns.current_scope.user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Profile saved.")
        |> redirect(to: ~p"/")

      {:error, changeset} ->
        render(conn, :edit, profile_changeset: changeset)
    end
  end
end
