defmodule Ultistats.AccountsTest do
  use Ultistats.DataCase

  alias Ultistats.Accounts

  import Ultistats.AccountsFixtures
  alias Ultistats.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user_with_password/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user_with_password(%{})

      assert %{
               email: ["can't be blank"],
               password: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email format" do
      {:error, changeset} =
        Accounts.register_user_with_password(%{
          email: "not valid",
          password: valid_user_password()
        })

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates password length" do
      {:error, changeset} =
        Accounts.register_user_with_password(%{email: unique_user_email(), password: "short"})

      assert %{password: ["should be at least 12 character(s)"]} = errors_on(changeset)
    end

    test "validates maximum email length" do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.register_user_with_password(%{email: too_long, password: valid_user_password()})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness (case-insensitive)" do
      %{email: email} = user_fixture()

      {:error, changeset} =
        Accounts.register_user_with_password(%{email: email, password: valid_user_password()})

      assert "has already been taken" in errors_on(changeset).email

      {:error, changeset} =
        Accounts.register_user_with_password(%{
          email: String.upcase(email),
          password: valid_user_password()
        })

      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a hashed password and no confirmed_at" do
      email = unique_user_email()

      {:ok, user} =
        Accounts.register_user_with_password(%{email: email, password: valid_user_password()})

      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.password)
      assert is_nil(user.confirmed_at)
    end
  end

  describe "confirm_user!/1" do
    test "sets confirmed_at on the user" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at

      confirmed = Accounts.confirm_user!(user)
      assert confirmed.confirmed_at
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "stub-claim tokens" do
    test "generate + verify round-trip returns the user" do
      {:ok, stub} =
        Accounts.create_stub_user(%{
          first_name: "Stub",
          last_name: "Person",
          gender_role: :male_matching,
          position: :handler
        })

      token = Accounts.generate_stub_claim_token(stub)
      assert is_binary(token)

      assert {:ok, %User{id: id}} = Accounts.verify_stub_claim_token(token)
      assert id == stub.id
    end

    test "tampered token returns :invalid" do
      {:ok, stub} =
        Accounts.create_stub_user(%{
          first_name: "Stub",
          last_name: "Person",
          gender_role: :male_matching,
          position: :handler
        })

      token = Accounts.generate_stub_claim_token(stub) <> "garbage"
      assert {:error, :invalid} = Accounts.verify_stub_claim_token(token)
    end

    test "non-binary token returns :invalid" do
      assert {:error, :invalid} = Accounts.verify_stub_claim_token(nil)
    end

    test "verify returns :invalid when the underlying user is gone" do
      {:ok, stub} =
        Accounts.create_stub_user(%{
          first_name: "Gone",
          last_name: "Soon",
          gender_role: :female_matching,
          position: :cutter
        })

      token = Accounts.generate_stub_claim_token(stub)
      Repo.delete!(stub)

      assert {:error, :invalid} = Accounts.verify_stub_claim_token(token)
    end
  end

  describe "claim_stub_user/2" do
    alias Ultistats.Games
    alias Ultistats.Repo
    alias Ultistats.Teams
    alias Ultistats.Teams.TeamMembership

    import Ultistats.TeamsFixtures
    import Ultistats.GamesFixtures, only: [game_fixture: 1]

    defp claimer_fixture do
      user_fixture()
    end

    defp stub_with_team(team) do
      {:ok, stub} =
        Accounts.create_stub_user(%{
          first_name: "Stub",
          last_name: "User",
          gender_role: :male_matching,
          position: :handler
        })

      {:ok, _m} = Teams.add_team_member(team, stub, %{role: :member, is_player: true})
      stub
    end

    test "moves memberships, repoints events, deletes stub" do
      team = team_fixture()
      stub = stub_with_team(team)
      claimer = claimer_fixture()

      # Build a game + point + event referring to the stub so we can
      # confirm passer_user_id / receiver_user_id get rewritten.
      receiver_member = team_membership_fixture(team_id: team.id)
      receiver = receiver_member.user

      game = game_fixture(team_id: team.id)
      {:ok, point} = Games.start_point(game, [stub.id, receiver.id])
      {:ok, ev1} = Games.record_throw(point, :catch, stub.id, receiver.id)
      {:ok, ev2} = Games.record_throw(point, :goal, receiver.id, stub.id)

      assert {:ok, %{teams: [team_id]}} = Accounts.claim_stub_user(stub, claimer)
      assert team_id == team.id

      # Stub is gone.
      refute Repo.get(User, stub.id)

      # Membership now belongs to the claimer.
      assert Teams.user_member_of?(claimer, team)

      # Events are repointed.
      ev1_after = Repo.get!(Ultistats.Games.Event, ev1.id)
      ev2_after = Repo.get!(Ultistats.Games.Event, ev2.id)
      assert ev1_after.passer_user_id == claimer.id
      assert ev1_after.receiver_user_id == receiver.id
      assert ev2_after.passer_user_id == receiver.id
      assert ev2_after.receiver_user_id == claimer.id
    end

    test "refuses :same_user when stub == claimer" do
      claimer = claimer_fixture()

      assert {:error, :same_user} = Accounts.claim_stub_user(claimer, claimer)
    end

    test "refuses :not_a_stub when target is already claimed" do
      team = team_fixture()
      claimer = claimer_fixture()

      already_claimed = user_fixture()

      already_claimed
      |> Ecto.Changeset.change(claimed_at: DateTime.utc_now(:second))
      |> Repo.update!()

      reloaded = Repo.get!(User, already_claimed.id)
      {:ok, _} = Teams.add_team_member(team, reloaded, %{role: :member, is_player: true})

      assert {:error, :not_a_stub} = Accounts.claim_stub_user(reloaded, claimer)
    end

    test "refuses :conflicting_membership when claimer is already on a stub team" do
      team = team_fixture()
      stub = stub_with_team(team)
      claimer = claimer_fixture()
      {:ok, _} = Teams.add_team_member(team, claimer, %{role: :member, is_player: true})

      assert {:error, :conflicting_membership, [tid]} =
               Accounts.claim_stub_user(stub, claimer)

      assert tid == team.id

      # Nothing should have moved — stub still has its membership and the
      # row is still in the DB.
      assert Repo.get(User, stub.id)
      assert Repo.get_by(TeamMembership, user_id: stub.id, team_id: team.id)
    end
  end
end
