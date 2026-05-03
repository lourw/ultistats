defmodule UltistatsWeb.UserClaimController do
  @moduledoc """
  Public stub-claim flow.

  An admin copies a `/claim/:token` URL off a stub roster row and
  shares it. The recipient lands here; if they're not signed in yet
  we point them at log-in / register with `:user_return_to` set so
  post-auth they bounce back. Once authenticated they confirm, and
  `Accounts.claim_stub_user/2` reassigns the stub's memberships and
  event references to them.
  """

  use UltistatsWeb, :controller

  alias Ultistats.Accounts
  alias Ultistats.Accounts.User

  def show(conn, %{"token" => token}) do
    case Accounts.verify_stub_claim_token(token) do
      {:ok, %User{} = stub} ->
        conn = put_session(conn, :user_return_to, ~p"/claim/#{token}")

        case current_user(conn) do
          nil ->
            render(conn, :show, stub: stub, token: token)

          %User{} = current_user ->
            render(conn, :confirm, stub: stub, token: token, current_user: current_user)
        end

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "That claim link is invalid or has expired.")
        |> redirect(to: ~p"/")
    end
  end

  def create(conn, %{"token" => token}) do
    case Accounts.verify_stub_claim_token(token) do
      {:ok, %User{} = stub} ->
        case current_user(conn) do
          nil ->
            conn
            |> put_session(:user_return_to, ~p"/claim/#{token}")
            |> put_flash(:error, "Please log in or register to claim this profile.")
            |> redirect(to: ~p"/users/log-in")

          %User{} = current_user ->
            do_claim(conn, stub, current_user)
        end

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "That claim link is invalid or has expired.")
        |> redirect(to: ~p"/")
    end
  end

  defp do_claim(conn, stub, current_user) do
    case Accounts.claim_stub_user(stub, current_user) do
      {:ok, %{teams: [team_id | _]}} ->
        conn
        |> put_flash(:info, "Profile linked.")
        |> redirect(to: ~p"/teams/#{team_id}")

      {:ok, %{teams: []}} ->
        # Stub had no memberships — nothing to land on; send to teams
        # index. Edge case in practice (a stub with zero memberships).
        conn
        |> put_flash(:info, "Profile linked.")
        |> redirect(to: ~p"/teams")

      {:error, :same_user} ->
        conn
        |> put_flash(:error, "You can't claim your own profile.")
        |> redirect(to: ~p"/")

      {:error, :not_a_stub} ->
        conn
        |> put_flash(:error, "That profile has already been claimed.")
        |> redirect(to: ~p"/")

      {:error, :conflicting_membership, team_ids} ->
        conn
        |> put_flash(
          :error,
          "You're already on #{Enum.count(team_ids)} of those teams; ask an admin to merge by hand."
        )
        |> redirect(to: ~p"/")

      {:error, _other} ->
        conn
        |> put_flash(:error, "Couldn't claim that profile. Try again later.")
        |> redirect(to: ~p"/")
    end
  end

  defp current_user(conn) do
    case conn.assigns[:current_scope] do
      %{user: %User{} = user} -> user
      _ -> nil
    end
  end
end
