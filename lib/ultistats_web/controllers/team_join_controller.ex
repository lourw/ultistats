defmodule UltistatsWeb.TeamJoinController do
  @moduledoc """
  Public team-join flow.

  An admin copies a single `/join/:token` URL off a team's page and
  shares it. The recipient lands here; if they're not signed in yet we
  point them at log-in / register with `:user_return_to` set so post-auth
  they bounce back. Once authenticated they either:

    * pick an existing unclaimed stub on the team — runs through
      `Accounts.claim_stub_user/2` to reassign the stub's memberships
      and event references, or
    * add themselves as a fresh player via
      `Teams.join_team_as_new_player/3`, which updates their profile and
      inserts a new `TeamMembership`.
  """

  use UltistatsWeb, :controller

  alias Ultistats.Accounts
  alias Ultistats.Accounts.User
  alias Ultistats.Teams
  alias Ultistats.Teams.TeamMembership

  def show(conn, %{"token" => token}) do
    case Teams.verify_team_join_token(token) do
      {:ok, team} ->
        conn = put_session(conn, :user_return_to, ~p"/join/#{token}")

        case current_user(conn) do
          nil ->
            render(conn, :show, team: team, token: token)

          %User{} = current_user ->
            if Teams.user_member_of?(current_user, team) do
              conn
              |> put_flash(:info, "You're already on this team.")
              |> redirect(to: ~p"/teams/#{team.id}")
            else
              render_pick(conn, team, token, current_user, %{})
            end
        end

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "That join link is invalid or has expired.")
        |> redirect(to: ~p"/")
    end
  end

  def claim_show(conn, %{"token" => token, "membership_id" => membership_id}) do
    case Teams.verify_team_join_token(token) do
      {:ok, team} ->
        case current_user(conn) do
          nil ->
            conn
            |> put_session(:user_return_to, ~p"/join/#{token}")
            |> put_flash(:error, "Please log in or register to join this team.")
            |> redirect(to: ~p"/users/log-in")

          %User{} = current_user ->
            do_claim_show(conn, team, token, current_user, membership_id, %{})
        end

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "That join link is invalid or has expired.")
        |> redirect(to: ~p"/")
    end
  end

  def claim(conn, %{"token" => token, "membership_id" => membership_id} = params) do
    case Teams.verify_team_join_token(token) do
      {:ok, team} ->
        case current_user(conn) do
          nil ->
            conn
            |> put_session(:user_return_to, ~p"/join/#{token}")
            |> put_flash(:error, "Please log in or register to join this team.")
            |> redirect(to: ~p"/users/log-in")

          %User{} = current_user ->
            do_claim(conn, team, token, current_user, membership_id, params["member"] || %{})
        end

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "That join link is invalid or has expired.")
        |> redirect(to: ~p"/")
    end
  end

  def create(conn, %{"token" => token} = params) do
    case Teams.verify_team_join_token(token) do
      {:ok, team} ->
        case current_user(conn) do
          nil ->
            conn
            |> put_session(:user_return_to, ~p"/join/#{token}")
            |> put_flash(:error, "Please log in or register to join this team.")
            |> redirect(to: ~p"/users/log-in")

          %User{} = current_user ->
            if Teams.user_member_of?(current_user, team) do
              conn
              |> put_flash(:info, "You're already on this team.")
              |> redirect(to: ~p"/teams/#{team.id}")
            else
              do_create(conn, team, token, current_user, params["member"] || %{})
            end
        end

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "That join link is invalid or has expired.")
        |> redirect(to: ~p"/")
    end
  end

  ## ---- internal handlers -----------------------------------------------

  defp do_claim_show(conn, team, token, current_user, membership_id, member_params)
       when is_binary(membership_id) do
    with %TeamMembership{} = membership <- fetch_membership(membership_id),
         :ok <- guard_membership_on_team(membership, team),
         :ok <- guard_membership_unclaimed(membership) do
      render_claim(conn, team, token, current_user, membership, member_params)
    else
      reason -> redirect_claim_error(conn, token, reason)
    end
  end

  defp do_claim(conn, team, token, current_user, membership_id, member_params)
       when is_binary(membership_id) do
    with %TeamMembership{} = membership <- fetch_membership(membership_id),
         :ok <- guard_membership_on_team(membership, team),
         :ok <- guard_membership_unclaimed(membership) do
      attrs = parse_member_params(member_params)

      profile_attrs =
        Map.take(attrs, [:first_name, :last_name, :gender_role, :position])

      membership_attrs = Map.take(attrs, [:jersey_number, :position])

      case Teams.claim_stub_with_profile(
             membership,
             current_user,
             profile_attrs,
             membership_attrs
           ) do
        {:ok, _result} ->
          conn
          |> put_flash(:info, "You're on #{team.name}.")
          |> redirect(to: ~p"/teams/#{team.id}")

        {:error, {:profile, %Ecto.Changeset{} = changeset}} ->
          form = Phoenix.Component.to_form(changeset, as: "member")

          render(conn, :claim_show,
            team: team,
            token: token,
            current_user: current_user,
            membership: membership,
            form: form
          )

        {:error, {:membership, %Ecto.Changeset{} = changeset}} ->
          form = Phoenix.Component.to_form(changeset, as: "member")

          render(conn, :claim_show,
            team: team,
            token: token,
            current_user: current_user,
            membership: membership,
            form: form
          )

        {:error, :same_user} ->
          conn
          |> put_flash(:error, "You can't claim your own profile.")
          |> redirect(to: ~p"/join/#{token}")

        {:error, :not_a_stub} ->
          conn
          |> put_flash(:error, "That profile has already been claimed.")
          |> redirect(to: ~p"/join/#{token}")

        {:error, {:conflicting_membership, _ids}} ->
          conn
          |> put_flash(
            :error,
            "You're already on this team — ask an admin to merge by hand."
          )
          |> redirect(to: ~p"/teams/#{team.id}")

        {:error, _other} ->
          conn
          |> put_flash(:error, "Couldn't claim that profile. Try again later.")
          |> redirect(to: ~p"/join/#{token}")
      end
    else
      reason -> redirect_claim_error(conn, token, reason)
    end
  end

  defp render_claim(
         conn,
         team,
         token,
         current_user,
         %TeamMembership{} = membership,
         member_params
       ) do
    # Prefill the verify form from the stub's profile + the
    # membership's per-team overrides — the user clicked "That's me",
    # so the stub's data is the best starting point. Fall back to
    # whatever the user just submitted when re-rendering on validation
    # error.
    %User{} = stub = membership.user

    initial_attrs =
      member_params_or_defaults(member_params, %{
        first_name: stub.first_name,
        last_name: stub.last_name,
        gender_role: stub.gender_role,
        position: Teams.resolved_position(membership),
        jersey_number: Teams.resolved_jersey_number(membership)
      })

    changeset =
      current_user
      |> Accounts.change_user_profile(initial_attrs)
      |> Map.put(:action, :ignore)

    form = Phoenix.Component.to_form(changeset, as: "member")

    render(conn, :claim_show,
      team: team,
      token: token,
      current_user: current_user,
      membership: membership,
      form: form
    )
  end

  defp member_params_or_defaults(params, defaults) when is_map(params) do
    if map_size(params) == 0, do: defaults, else: params
  end

  defp guard_membership_on_team(%TeamMembership{team_id: team_id}, %{id: id}) when team_id != id,
    do: {:error, :wrong_team}

  defp guard_membership_on_team(_, _), do: :ok

  defp guard_membership_unclaimed(%TeamMembership{user: %User{claimed_at: nil}}), do: :ok
  defp guard_membership_unclaimed(_), do: {:error, :already_claimed}

  defp redirect_claim_error(conn, token, nil) do
    conn
    |> put_flash(:error, "That player isn't on this team anymore.")
    |> redirect(to: ~p"/join/#{token}")
  end

  defp redirect_claim_error(conn, token, {:error, :wrong_team}) do
    conn
    |> put_flash(:error, "That player isn't on this team.")
    |> redirect(to: ~p"/join/#{token}")
  end

  defp redirect_claim_error(conn, token, {:error, :already_claimed}) do
    conn
    |> put_flash(:error, "That profile has already been claimed.")
    |> redirect(to: ~p"/join/#{token}")
  end

  defp do_create(conn, team, token, current_user, member_params) do
    attrs = parse_member_params(member_params)

    case Teams.join_team_as_new_player(team, current_user, attrs) do
      {:ok, _result} ->
        conn
        |> put_flash(:info, "Welcome to #{team.name}.")
        |> redirect(to: ~p"/teams/#{team.id}")

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        render_pick(conn, team, token, current_user, member_params, changeset)
    end
  end

  defp render_pick(conn, team, token, current_user, member_params, changeset \\ nil) do
    stubs = Teams.list_unclaimed_stub_memberships_for_team(team)

    changeset =
      changeset ||
        current_user
        |> Accounts.change_user_profile(member_params)
        |> Map.put(:action, :ignore)

    form = Phoenix.Component.to_form(changeset, as: "member")

    conn
    |> put_session(:user_return_to, ~p"/join/#{token}")
    |> render(:pick,
      team: team,
      token: token,
      current_user: current_user,
      stubs: stubs,
      form: form
    )
  end

  ## ---- helpers ---------------------------------------------------------

  defp current_user(conn) do
    case conn.assigns[:current_scope] do
      %{user: %User{} = user} -> user
      _ -> nil
    end
  end

  defp fetch_membership(id) do
    try do
      Teams.get_team_membership!(id)
    rescue
      Ecto.NoResultsError -> nil
      Ecto.Query.CastError -> nil
    end
  end

  defp parse_member_params(params) do
    %{
      first_name: nilify(params["first_name"]),
      last_name: nilify(params["last_name"]),
      gender_role: parse_gender(params["gender_role"]),
      position: parse_position(params["position"]),
      jersey_number: nilify(params["jersey_number"])
    }
  end

  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(s) when is_binary(s), do: s

  defp parse_gender("female_matching"), do: :female_matching
  defp parse_gender("male_matching"), do: :male_matching
  defp parse_gender(value) when value in [:female_matching, :male_matching], do: value
  defp parse_gender(_), do: nil

  defp parse_position("handler"), do: :handler
  defp parse_position("cutter"), do: :cutter
  defp parse_position("hybrid"), do: :hybrid
  defp parse_position(value) when value in [:handler, :cutter, :hybrid], do: value
  defp parse_position(_), do: nil
end
