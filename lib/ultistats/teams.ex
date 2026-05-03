defmodule Ultistats.Teams do
  @moduledoc """
  The Teams context.
  """

  import Ecto.Query, warn: false
  alias Ultistats.Repo

  alias Ultistats.Accounts.User
  alias Ultistats.Teams.{LinePreset, Team, TeamMembership}

  # Team-join tokens are stateless — `Phoenix.Token.sign/3` carries the
  # team's id signed by the endpoint secret. 30 days is long enough for
  # an admin to share a copied link without keeping a token table around.
  @team_join_salt "team join"
  @team_join_max_age 60 * 60 * 24 * 30

  @doc """
  Returns the list of teams.

  ## Examples

      iex> list_teams()
      [%Team{}, ...]

  """
  def list_teams do
    Repo.all(Team)
  end

  @doc """
  Gets a single team.

  Raises `Ecto.NoResultsError` if the Team does not exist.

  ## Examples

      iex> get_team!(123)
      %Team{}

      iex> get_team!(456)
      ** (Ecto.NoResultsError)

  """
  def get_team!(id), do: Repo.get!(Team, id)

  @doc """
  Creates a team.

  ## Examples

      iex> create_team(%{field: value})
      {:ok, %Team{}}

      iex> create_team(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_team(attrs) do
    %Team{}
    |> Team.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a team and inserts a TeamMembership for `user` with
  `role: :admin, is_player: true` in a single `Ecto.Multi`.

  Returns `{:ok, %{team: team, membership: membership}}` on success or
  `{:error, step, value, _changes}` on failure (where `step` is `:team`
  or `:membership`).

  Use this for the team-creation flow where the creator should
  automatically become an admin of the new team.
  """
  def create_team_with_admin(attrs, %User{} = user) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:team, Team.changeset(%Team{}, attrs))
    |> Ecto.Multi.run(:membership, fn _repo, %{team: team} ->
      add_team_member(team, user, %{role: :admin, is_player: true})
    end)
    |> Repo.transaction()
  end

  @doc """
  Updates a team.

  ## Examples

      iex> update_team(team, %{field: new_value})
      {:ok, %Team{}}

      iex> update_team(team, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_team(%Team{} = team, attrs) do
    team
    |> Team.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a team.

  ## Examples

      iex> delete_team(team)
      {:ok, %Team{}}

      iex> delete_team(team)
      {:error, %Ecto.Changeset{}}

  """
  def delete_team(%Team{} = team) do
    Repo.delete(team)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking team changes.

  ## Examples

      iex> change_team(team)
      %Ecto.Changeset{data: %Team{}}

  """
  def change_team(%Team{} = team, attrs \\ %{}) do
    Team.changeset(team, attrs)
  end

  alias Ultistats.Games
  alias Ultistats.Games.Game

  @doc """
  Returns aggregate stats for `team` for use on the teams index.

  Stats:

      %{
        total_players: integer,
        male_matching: integer,
        female_matching: integer,
        games_in_progress: integer,
        wins: integer,           # finished games where our_score > their_score
        losses: integer,         # finished games where our_score < their_score
        ties: integer            # rare; finished games with equal scores
      }

  Player counts come from team_memberships joined to users, filtered
  to memberships where `is_player == true`.
  """
  @spec team_stats(Team.t()) :: %{
          total_players: non_neg_integer(),
          male_matching: non_neg_integer(),
          female_matching: non_neg_integer(),
          games_in_progress: non_neg_integer(),
          wins: non_neg_integer(),
          losses: non_neg_integer(),
          ties: non_neg_integer()
        }
  def team_stats(%Team{} = team) do
    gender_counts =
      from(m in TeamMembership,
        join: u in User,
        on: u.id == m.user_id,
        where: m.team_id == ^team.id and m.is_player == true,
        group_by: u.gender_role,
        select: {u.gender_role, count(m.id)}
      )
      |> Repo.all()
      |> Map.new()

    female_matching = Map.get(gender_counts, :female_matching, 0)
    male_matching = Map.get(gender_counts, :male_matching, 0)
    total_players = female_matching + male_matching

    games =
      Game
      |> where([g], g.team_id == ^team.id)
      |> Repo.all()

    games_in_progress = Enum.count(games, &(&1.status == :in_progress))

    # N+1 over finished games via Games.score/1 — acceptable at MVP scale
    # (a team has at most a handful of finished games). If this hot-spots
    # at scale, the per-finished-game score derivation can move into a
    # single SQL aggregation.
    {wins, losses, ties} =
      games
      |> Enum.filter(&(&1.status == :finished))
      |> Enum.reduce({0, 0, 0}, fn game, {w, l, t} ->
        %{ours: ours, theirs: theirs} = Games.score(game)

        cond do
          ours > theirs -> {w + 1, l, t}
          ours < theirs -> {w, l + 1, t}
          true -> {w, l, t + 1}
        end
      end)

    %{
      total_players: total_players,
      male_matching: male_matching,
      female_matching: female_matching,
      games_in_progress: games_in_progress,
      wins: wins,
      losses: losses,
      ties: ties
    }
  end

  @doc """
  Returns `[%{team: %Team{}, stats: %{...}}]` ordered by team name.
  """
  @spec list_teams_with_stats() :: [%{team: Team.t(), stats: map()}]
  def list_teams_with_stats do
    Team
    |> order_by([t], asc: t.name)
    |> Repo.all()
    |> Enum.map(fn team -> %{team: team, stats: team_stats(team)} end)
  end

  @doc """
  Returns the list of teams `user` has a membership on, regardless of
  role or `is_player`. Ordered by team name asc.
  """
  def list_teams_for_user(%User{id: user_id}), do: list_teams_for_user(user_id)

  def list_teams_for_user(user_id) when is_binary(user_id) do
    from(t in Team,
      join: m in TeamMembership,
      on: m.team_id == t.id,
      where: m.user_id == ^user_id,
      order_by: [asc: t.name],
      distinct: true
    )
    |> Repo.all()
  end

  def list_teams_for_user(_), do: []

  @doc """
  Same as `list_teams_with_stats/0` but scoped to teams `user` is a
  member of.
  """
  @spec list_teams_with_stats_for_user(User.t() | binary()) :: [
          %{team: Team.t(), stats: map()}
        ]
  def list_teams_with_stats_for_user(user_or_id) do
    user_or_id
    |> list_teams_for_user()
    |> Enum.map(fn team -> %{team: team, stats: team_stats(team)} end)
  end

  @doc """
  Returns true if `user` has a TeamMembership for `team`, regardless of
  role or `is_player`.
  """
  def user_member_of?(%User{id: user_id}, %Team{id: team_id}),
    do: user_member_of?(user_id, team_id)

  def user_member_of?(%User{id: user_id}, team_id) when is_binary(team_id),
    do: user_member_of?(user_id, team_id)

  def user_member_of?(user_id, %Team{id: team_id}) when is_binary(user_id),
    do: user_member_of?(user_id, team_id)

  def user_member_of?(user_id, team_id) when is_binary(user_id) and is_binary(team_id) do
    Repo.exists?(
      from m in TeamMembership,
        where: m.user_id == ^user_id and m.team_id == ^team_id
    )
  end

  def user_member_of?(_, _), do: false

  @doc """
  Returns true if `user` has a TeamMembership for `team` with
  `role: :admin`.
  """
  def user_admin_of?(%User{id: user_id}, %Team{id: team_id}),
    do: user_admin_of?(user_id, team_id)

  def user_admin_of?(%User{id: user_id}, team_id) when is_binary(team_id),
    do: user_admin_of?(user_id, team_id)

  def user_admin_of?(user_id, %Team{id: team_id}) when is_binary(user_id),
    do: user_admin_of?(user_id, team_id)

  def user_admin_of?(user_id, team_id) when is_binary(user_id) and is_binary(team_id) do
    Repo.exists?(
      from m in TeamMembership,
        where: m.user_id == ^user_id and m.team_id == ^team_id and m.role == :admin
    )
  end

  def user_admin_of?(_, _), do: false

  # ===========================================================================
  # Team memberships
  # ===========================================================================

  @doc """
  Returns all team memberships for `team`, preloaded with `:user`.
  Order: players first (membership.is_player desc), then by user
  last_name asc, then by jersey_number asc.
  """
  def list_team_members_for_team(%Team{id: team_id}), do: list_team_members_for_team(team_id)

  def list_team_members_for_team(team_id) when is_binary(team_id) do
    from(m in TeamMembership,
      join: u in User,
      on: u.id == m.user_id,
      where: m.team_id == ^team_id,
      order_by: [desc: m.is_player, asc: u.last_name, asc: m.jersey_number],
      preload: [user: u]
    )
    |> Repo.all()
  end

  @doc """
  Returns the team's memberships whose underlying user is a true stub
  — i.e. has no `:hashed_password` (cannot log in) AND no `:claimed_at`.
  Preloaded with `:user`, ordered by jersey number then by user
  last_name. Used by the public team-join page so a visitor can pick
  the stub that represents them.

  Filtering on `is_nil(u.hashed_password)` is important: a real
  registered user who joined directly via the new-player flow also has
  `claimed_at == nil` (the field is only set during the stub-claim
  process), but they should never appear in the picker. The stub
  contract (see `Ultistats.Accounts` moduledoc) is: stubs have a
  sentinel email, no password hash, and no claimed_at.
  """
  def list_unclaimed_stub_memberships_for_team(%Team{id: team_id}),
    do: list_unclaimed_stub_memberships_for_team(team_id)

  def list_unclaimed_stub_memberships_for_team(team_id) when is_binary(team_id) do
    from(m in TeamMembership,
      join: u in User,
      on: u.id == m.user_id,
      where:
        m.team_id == ^team_id and
          is_nil(u.claimed_at) and
          is_nil(u.hashed_password),
      order_by: [asc: m.jersey_number, asc: u.last_name],
      preload: [user: u]
    )
    |> Repo.all()
  end

  @doc """
  Signs a stateless join token for `team`. Admins copy a single
  `/join/:token` URL off the team page and share it; recipients land on
  the join controller and either pick an unclaimed stub that represents
  them or add themselves as a fresh player on the roster. See
  `verify_team_join_token/1`.
  """
  def generate_team_join_token(%Team{id: id}) do
    Phoenix.Token.sign(UltistatsWeb.Endpoint, @team_join_salt, id)
  end

  @doc """
  Verifies a team-join `token`. Returns `{:ok, %Team{}}` when the
  signed team still exists, or `{:error, :invalid}` when the signature
  is bad / expired or the team is gone.
  """
  def verify_team_join_token(token) when is_binary(token) do
    case Phoenix.Token.verify(UltistatsWeb.Endpoint, @team_join_salt, token,
           max_age: @team_join_max_age
         ) do
      {:ok, team_id} ->
        case Repo.get(Team, team_id) do
          nil -> {:error, :invalid}
          %Team{} = team -> {:ok, team}
        end

      {:error, _reason} ->
        {:error, :invalid}
    end
  end

  def verify_team_join_token(_), do: {:error, :invalid}

  @doc """
  Claims a stub membership for `claimer`, copying the verified profile
  (`profile_attrs`) onto the claimer's `User` row and any per-team
  overrides (`membership_attrs`, e.g. `:jersey_number`, `:position`)
  onto the soon-to-be-reassigned `TeamMembership`.

  Runs as a single transaction:

    1. Update the claimer's profile via
       `Ultistats.Accounts.User.profile_changeset/2`. Required so a
       fresh registered user actually ends up with a name on the
       roster (the stub's profile is otherwise lost when the stub row
       is deleted in step 3).
    2. Update the membership row's per-team fields
       (`:jersey_number`, `:position`).
    3. Hand off to `Ultistats.Accounts.claim_stub_user/2` to reassign
       all of the stub's memberships and event references to the
       claimer, then delete the stub user.

  Returns `{:ok, %{teams: [team_id, ...]}}` on success (mirrors
  `Accounts.claim_stub_user/2`'s success shape) or `{:error, reason}`
  where `reason` is one of:

    * `{:profile, %Ecto.Changeset{}}` — the claimer's profile params
      were invalid.
    * `{:membership, %Ecto.Changeset{}}` — per-team override invalid.
    * `:same_user`, `:not_a_stub`, `{:conflicting_membership, [_]}`,
      `:claim_failed` — bubble up from `Accounts.claim_stub_user/2`.
  """
  def claim_stub_with_profile(
        %TeamMembership{user: %User{} = stub} = membership,
        %User{} = claimer,
        profile_attrs,
        membership_attrs
      )
      when is_map(profile_attrs) and is_map(membership_attrs) do
    profile_attrs = normalize_membership_attrs(profile_attrs)
    membership_attrs = normalize_membership_attrs(membership_attrs)

    Repo.transact(fn ->
      with {:ok, _claimer} <- update_claimer_profile(claimer, profile_attrs),
           {:ok, _membership} <- update_membership_overrides(membership, membership_attrs),
           {:ok, result} <- do_claim_stub(stub, claimer) do
        {:ok, result}
      end
    end)
  end

  defp update_claimer_profile(%User{} = claimer, profile_attrs) do
    case Ultistats.Accounts.update_user_profile(claimer, profile_attrs) do
      {:ok, user} -> {:ok, user}
      {:error, %Ecto.Changeset{} = cs} -> {:error, {:profile, cs}}
    end
  end

  defp update_membership_overrides(%TeamMembership{} = membership, membership_attrs) do
    overrides = Map.take(membership_attrs, [:jersey_number, :position])

    membership
    |> TeamMembership.changeset(overrides)
    |> Repo.update()
    |> case do
      {:ok, m} -> {:ok, m}
      {:error, %Ecto.Changeset{} = cs} -> {:error, {:membership, cs}}
    end
  end

  defp do_claim_stub(%User{} = stub, %User{} = claimer) do
    case Ultistats.Accounts.claim_stub_user(stub, claimer) do
      {:ok, result} -> {:ok, result}
      {:error, :conflicting_membership, ids} -> {:error, {:conflicting_membership, ids}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Joins `current_user` to `team` as a brand-new player using `attrs`.

  Runs in a single `Ecto.Multi`:

    * updates the user's profile (`first_name`, `last_name`,
      `gender_role`, `position`) via `Accounts.update_user_profile/2`,
    * inserts a `%TeamMembership{}` for `(team, current_user)` with
      `role: :member, is_player: true` plus the per-team `:position`
      and `:jersey_number` overrides.

  Returns `{:ok, %{user: user, membership: membership}}` on success,
  or `{:error, step, %Ecto.Changeset{}, _changes}` where `step` is
  `:user` or `:membership`.
  """
  def join_team_as_new_player(%Team{} = team, %User{} = current_user, attrs)
      when is_map(attrs) do
    attrs = normalize_membership_attrs(attrs)

    profile_attrs =
      Map.take(attrs, [:first_name, :last_name, :gender_role, :position])

    membership_attrs =
      attrs
      |> Map.take([:jersey_number, :position])
      |> Map.merge(%{
        team_id: team.id,
        user_id: current_user.id,
        role: :member,
        is_player: true
      })

    Ecto.Multi.new()
    |> Ecto.Multi.update(
      :user,
      Ultistats.Accounts.User.profile_changeset(current_user, profile_attrs)
    )
    |> Ecto.Multi.insert(
      :membership,
      TeamMembership.changeset(%TeamMembership{}, membership_attrs)
    )
    |> Repo.transaction()
  end

  @doc """
  Returns memberships for `team` where `is_player == true`,
  preloaded with `:user`, ordered by jersey_number asc, then by
  user last_name asc.

  Kept under the `list_players_for_team` name (used by Games and the
  team-roster UI) for compatibility through the Phase 4 UI rewrite.
  """
  def list_players_for_team(%Team{id: team_id}), do: list_players_for_team(team_id)

  def list_players_for_team(team_id) when is_binary(team_id) do
    from(m in TeamMembership,
      join: u in User,
      on: u.id == m.user_id,
      where: m.team_id == ^team_id and m.is_player == true,
      order_by: [asc: m.jersey_number, asc: u.last_name],
      preload: [user: u]
    )
    |> Repo.all()
  end

  @doc "Gets a single team_membership. Raises if not found."
  def get_team_membership!(id) do
    TeamMembership
    |> Repo.get!(id)
    |> Repo.preload(:user)
  end

  @doc """
  Looks up the membership row for `(team, user)`, or returns `nil`.
  Accepts `%Team{}` / `%User{}` or their binary ids.
  """
  def get_team_membership_by_team_and_user(%Team{id: team_id}, %User{id: user_id}),
    do: get_team_membership_by_team_and_user(team_id, user_id)

  def get_team_membership_by_team_and_user(team_id, user_id)
      when is_binary(team_id) and is_binary(user_id) do
    Repo.get_by(TeamMembership, team_id: team_id, user_id: user_id)
  end

  @doc """
  Adds `user` to `team` as a member, with the given attrs (`:role`,
  `:is_player`, `:jersey_number`, `:position`).

  When `attrs` doesn't carry `:position` or `:jersey_number`, those
  fields are pre-filled from the user's defaults (`user.position`,
  `user.jersey_number`) so a user joining a new team starts with their
  personal defaults — overridable per-team.
  """
  def add_team_member(%Team{} = team, %User{} = user, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_membership_attrs()
      |> prefill_from_user(user)
      |> Map.put(:team_id, team.id)
      |> Map.put(:user_id, user.id)

    %TeamMembership{}
    |> TeamMembership.changeset(attrs)
    |> Repo.insert()
  end

  defp prefill_from_user(attrs, %User{} = user) do
    attrs
    |> maybe_put_default(:position, user.position)
    |> maybe_put_default(:jersey_number, user.jersey_number)
  end

  defp maybe_put_default(attrs, key, default) do
    case Map.get(attrs, key) do
      nil -> if is_nil(default), do: attrs, else: Map.put(attrs, key, default)
      "" -> if is_nil(default), do: attrs, else: Map.put(attrs, key, default)
      _ -> attrs
    end
  end

  @doc """
  Updates a team membership's role / is_player / jersey_number.
  """
  def update_team_membership(%TeamMembership{} = membership, attrs) do
    membership
    |> TeamMembership.changeset(normalize_membership_attrs(attrs))
    |> Repo.update()
  end

  @doc "Removes a team member (deletes the membership row)."
  def remove_team_member(%TeamMembership{} = membership) do
    Repo.delete(membership)
  end

  @doc "Returns an `%Ecto.Changeset{}` for tracking membership changes."
  def change_team_membership(%TeamMembership{} = membership, attrs \\ %{}) do
    TeamMembership.changeset(membership, normalize_membership_attrs(attrs))
  end

  @doc """
  Creates a stub user via `Ultistats.Accounts.create_stub_user/1` and
  attaches it to `team` as a membership in a single `Ecto.Multi`.

  `attrs` should carry `:first_name`, `:last_name`, `:gender_role`,
  `:position` (for the stub user) plus `:role`, `:is_player`,
  `:jersey_number` (for the membership).

  Returns `{:ok, %{user: user, membership: membership}}` on success
  or `{:error, step, value, _changes}` on failure (where `step` is
  `:user` or `:membership`).
  """
  def create_member_with_stub_user(%Team{} = team, attrs) when is_map(attrs) do
    attrs = normalize_membership_attrs(attrs)

    user_attrs =
      Map.take(attrs, [:first_name, :last_name, :gender_role, :position])

    membership_defaults = %{role: :member, is_player: true}

    membership_attrs =
      attrs
      |> Map.take([:role, :is_player, :jersey_number])
      |> then(&Map.merge(membership_defaults, &1))

    Ecto.Multi.new()
    |> Ecto.Multi.run(:user, fn _repo, _changes ->
      Ultistats.Accounts.create_stub_user(user_attrs)
    end)
    |> Ecto.Multi.run(:membership, fn _repo, %{user: user} ->
      add_team_member(team, user, membership_attrs)
    end)
    |> Repo.transaction()
  end

  @doc """
  Bulk-creates stub users + memberships for `team` in a single
  `Ecto.Multi`. Mirrors `create_member_with_stub_user/2` per row.

  Each `attrs` map should carry stub-user fields (`:first_name`,
  `:last_name`, `:gender_role`, `:position`) plus membership fields
  (`:role`, `:is_player`, `:jersey_number`).

  Rows where both `:first_name` and `:last_name` are blank are dropped
  before insert (lets the bulk-add form ship over-allocated buffers).

  Returns:

    * `{:ok, [%{user: user, membership: membership}, ...]}` — all rows in.
    * `{:error, {row_index, step, %Ecto.Changeset{}}}` — `row_index` is
      into the *post-filter* (non-blank) row list; `step` is `:user`
      or `:membership`. The whole transaction is rolled back.
  """
  @spec bulk_create_members_with_stub_users(Team.t(), [map()]) ::
          {:ok, [%{user: Ultistats.Accounts.User.t(), membership: TeamMembership.t()}]}
          | {:error, {non_neg_integer(), atom(), Ecto.Changeset.t()}}
  def bulk_create_members_with_stub_users(%Team{} = team, rows) when is_list(rows) do
    non_blank =
      rows
      |> Enum.map(&normalize_membership_attrs/1)
      |> Enum.reject(&blank_member_row?/1)

    multi =
      non_blank
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {attrs, idx}, multi ->
        user_attrs = Map.take(attrs, [:first_name, :last_name, :gender_role, :position])

        membership_defaults = %{role: :member, is_player: true}

        membership_attrs =
          attrs
          |> Map.take([:role, :is_player, :jersey_number])
          |> then(&Map.merge(membership_defaults, &1))

        multi
        |> Ecto.Multi.run({:user, idx}, fn _repo, _changes ->
          Ultistats.Accounts.create_stub_user(user_attrs)
        end)
        |> Ecto.Multi.run({:membership, idx}, fn _repo, changes ->
          user = Map.fetch!(changes, {:user, idx})
          add_team_member(team, user, membership_attrs)
        end)
      end)

    case Repo.transaction(multi) do
      {:ok, results} ->
        rows_out =
          non_blank
          |> Enum.with_index()
          |> Enum.map(fn {_attrs, idx} ->
            %{
              user: Map.fetch!(results, {:user, idx}),
              membership: Map.fetch!(results, {:membership, idx})
            }
          end)

        {:ok, rows_out}

      {:error, {step, idx}, changeset, _changes} when step in [:user, :membership] ->
        {:error, {idx, step, changeset}}
    end
  end

  defp blank_member_row?(%{first_name: first, last_name: last}) do
    blank_string?(first) and blank_string?(last)
  end

  defp blank_member_row?(_), do: true

  defp blank_string?(nil), do: true
  defp blank_string?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank_string?(_), do: true

  @doc """
  Returns all team memberships across all teams, preloaded with `:user`
  and `:team`, ordered by team name then jersey number then user
  last_name.
  """
  def list_team_memberships do
    from(m in TeamMembership,
      join: u in User,
      on: u.id == m.user_id,
      join: t in Team,
      on: t.id == m.team_id,
      order_by: [asc: t.name, asc: m.jersey_number, asc: u.last_name],
      preload: [user: u, team: t]
    )
    |> Repo.all()
  end

  @doc """
  Updates a `TeamMembership` and its underlying `User` profile in a
  single `Ecto.Multi`. Splits `attrs` into user-profile keys
  (`:first_name`, `:last_name`, `:gender_role`) and membership keys
  (`:role`, `:is_player`, `:jersey_number`, `:position`).

  The user's profile is only updated when the user is a stub
  (`claimed_at == nil`). For real (claimed) users, only the membership
  half is updated — their profile is theirs to edit on their own
  settings page.

  Returns `{:ok, %{user: user, membership: membership}}` on success
  or `{:error, step, %Ecto.Changeset{}, _changes}` where `step` is
  `:user` or `:membership`.
  """
  def update_member_with_user(%TeamMembership{} = membership, attrs) when is_map(attrs) do
    attrs = normalize_membership_attrs(attrs)
    user = membership.user || Repo.preload(membership, :user).user

    user_attrs = Map.take(attrs, [:first_name, :last_name, :gender_role])
    membership_attrs = Map.take(attrs, [:role, :is_player, :jersey_number, :position])

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update(:membership, TeamMembership.changeset(membership, membership_attrs))

    multi =
      if stub_user?(user) do
        Ecto.Multi.update(
          multi,
          :user,
          Ultistats.Accounts.User.profile_changeset(user, user_attrs)
        )
      else
        # Real user — surface the unchanged user in the multi result so
        # callers can pattern-match `%{user: user, membership: m}`
        # uniformly. The user's profile is theirs to edit on their own
        # settings page.
        Ecto.Multi.run(multi, :user, fn _repo, _changes -> {:ok, user} end)
      end

    Repo.transaction(multi)
  end

  defp stub_user?(%User{claimed_at: nil}), do: true
  defp stub_user?(%User{}), do: false

  @doc """
  Returns the effective position for `membership` — the per-team
  override if set, otherwise the user's default. The membership must
  be preloaded with `:user`.
  """
  @spec resolved_position(TeamMembership.t()) :: atom() | nil
  def resolved_position(%TeamMembership{position: pos}) when not is_nil(pos), do: pos
  def resolved_position(%TeamMembership{user: %User{position: pos}}), do: pos
  def resolved_position(%TeamMembership{}), do: nil

  @doc """
  Returns the effective jersey number for `membership` — the per-team
  override if set, otherwise the user's default. The membership must
  be preloaded with `:user`.
  """
  @spec resolved_jersey_number(TeamMembership.t()) :: String.t() | nil
  def resolved_jersey_number(%TeamMembership{jersey_number: j})
      when not is_nil(j) and j != "",
      do: j

  def resolved_jersey_number(%TeamMembership{user: %User{jersey_number: j}}), do: j
  def resolved_jersey_number(%TeamMembership{}), do: nil

  defp normalize_membership_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {k, v}, acc when is_atom(k) ->
        Map.put(acc, k, v)

      {k, v}, acc when is_binary(k) ->
        case safe_to_existing_atom(k) do
          nil -> acc
          atom -> Map.put(acc, atom, v)
        end
    end)
  end

  defp safe_to_existing_atom(s) when is_binary(s) do
    String.to_existing_atom(s)
  rescue
    ArgumentError -> nil
  end

  # ===========================================================================
  # Line presets
  # ===========================================================================

  @doc """
  Returns the list of line_presets (across all teams), with users preloaded.
  """
  def list_line_presets do
    LinePreset
    |> order_by([lp], asc: lp.name)
    |> preload(:users)
    |> Repo.all()
  end

  @doc """
  Returns the line presets for a given team, ordered by name, with
  users preloaded.
  """
  def list_line_presets_for_team(%Team{id: team_id}), do: list_line_presets_for_team(team_id)

  def list_line_presets_for_team(team_id) when is_binary(team_id) do
    LinePreset
    |> where([lp], lp.team_id == ^team_id)
    |> order_by([lp], asc: lp.name)
    |> preload(:users)
    |> Repo.all()
  end

  @doc """
  Gets a single line_preset, with `:users` preloaded so an edit form
  can populate selection state.

  Raises `Ecto.NoResultsError` if the Line preset does not exist.
  """
  def get_line_preset!(id) do
    LinePreset
    |> Repo.get!(id)
    |> Repo.preload(:users)
  end

  @doc """
  Creates a line_preset.

  Accepts a `:user_ids` (or `"user_ids"`) key alongside the usual
  attrs. User ids are filtered defensively to users who hold a
  membership on the same team_id, so it's never possible to attach
  users from another team to a preset.
  """
  def create_line_preset(attrs) do
    {user_ids, attrs} = pop_user_ids(attrs)

    %LinePreset{}
    |> LinePreset.changeset(attrs)
    |> put_users_assoc(user_ids)
    |> Repo.insert()
  end

  @doc """
  Updates a line_preset, replacing its user set when `:user_ids`
  (or `"user_ids"`) is present in attrs. Replacement (not append) is
  guaranteed by the `on_replace: :delete` declaration on the schema's
  `many_to_many :users`.
  """
  def update_line_preset(%LinePreset{} = line_preset, attrs) do
    {user_ids, attrs} = pop_user_ids(attrs)

    line_preset = Repo.preload(line_preset, :users)

    line_preset
    |> LinePreset.changeset(attrs)
    |> put_users_assoc(user_ids, line_preset.team_id)
    |> Repo.update()
  end

  @doc """
  Deletes a line_preset. The join-table rows are removed by the
  `on_delete: :delete_all` constraint on `line_preset_users`.
  """
  def delete_line_preset(%LinePreset{} = line_preset) do
    Repo.delete(line_preset)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking line_preset changes.
  """
  def change_line_preset(%LinePreset{} = line_preset, attrs \\ %{}) do
    LinePreset.changeset(line_preset, attrs)
  end

  # ----- private helpers for line_preset user association -----

  defp pop_user_ids(attrs) when is_map(attrs) do
    case Map.pop(attrs, :user_ids, :__missing__) do
      {:__missing__, attrs} ->
        case Map.pop(attrs, "user_ids", :__missing__) do
          {:__missing__, attrs} -> {nil, attrs}
          {ids, attrs} -> {ids, attrs}
        end

      {ids, attrs} ->
        {ids, attrs}
    end
  end

  # No user_ids supplied — leave the changeset alone (creates with
  # no users for new records; preserves existing users on update).
  defp put_users_assoc(changeset, nil), do: changeset

  defp put_users_assoc(changeset, user_ids) when is_list(user_ids) do
    team_id = Ecto.Changeset.get_field(changeset, :team_id)
    put_users_assoc(changeset, user_ids, team_id)
  end

  defp put_users_assoc(changeset, nil, _team_id), do: changeset

  defp put_users_assoc(changeset, user_ids, team_id) when is_list(user_ids) do
    users = load_team_scoped_users(user_ids, team_id)
    Ecto.Changeset.put_assoc(changeset, :users, users)
  end

  defp load_team_scoped_users([], _team_id), do: []
  defp load_team_scoped_users(_ids, nil), do: []

  defp load_team_scoped_users(ids, team_id) do
    from(u in User,
      join: m in TeamMembership,
      on: m.user_id == u.id,
      where: m.team_id == ^team_id and u.id in ^ids,
      distinct: true
    )
    |> Repo.all()
  end
end
