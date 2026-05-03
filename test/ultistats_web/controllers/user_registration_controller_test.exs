defmodule UltistatsWeb.UserRegistrationControllerTest do
  use UltistatsWeb.ConnCase

  alias Ultistats.Accounts
  import Ultistats.AccountsFixtures

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ ~p"/users/log-in"
      assert response =~ ~p"/users/register"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /users/register" do
    test "creates a confirmed account, logs in, and redirects to /teams", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/teams"

      user = Accounts.get_user_by_email(email)
      assert user
      assert user.confirmed_at
    end

    test "preserves a pre-stashed :user_return_to (e.g. a /join/:token bounce)",
         %{conn: conn} do
      return_to = "/join/some-token"

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{user_return_to: return_to})
        |> post(~p"/users/register", %{
          "user" => valid_user_attributes()
        })

      assert get_session(conn, :user_token)
      # Post-register redirect lands on the original return-to URL,
      # not the /teams default.
      assert redirected_to(conn) == return_to
    end

    test "render errors for invalid email", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "with spaces", "password" => valid_user_password()}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "must have the @ sign and no spaces"
    end

    test "render errors for short password", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => unique_user_email(), "password" => "short"}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "should be at least 12 character"
    end
  end
end
