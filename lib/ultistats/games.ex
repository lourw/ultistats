defmodule Ultistats.Games do
  @moduledoc """
  The Games context — game lifecycle, point lifecycle, and event capture
  for live in-game stat tracking.

  Read-path conventions:
  - All event reads filter `deleted_at IS NULL` (soft-delete pattern).
  - `points` are ordered by `sequence` ascending.
  """

  import Ecto.Query, warn: false
  alias Ultistats.Repo

  alias Ultistats.Accounts.User
  alias Ultistats.Games.{Event, Game, Point, Ruleset}
  alias Ultistats.Teams
  alias Ultistats.Teams.{Team, TeamMembership}

  # USAU-standard defaults — used both as the fallback for games with
  # no ruleset attached (legacy / dev rows) and as the seed when
  # synthesizing a `:game_instance` from raw overrides at game-start.
  defp usau_standard_attrs do
    %{
      score_cap: 15,
      halftime_target: 8,
      halftime_cap_minutes: nil,
      soft_cap_minutes: nil,
      hard_cap_minutes: nil,
      timeouts_per_half: 2,
      line_size: 7,
      gender_ratio_rule: :endzone,
      starting_male_count: 4,
      starting_female_count: 3
    }
  end

  # ===========================================================================
  # Game CRUD (generator-style; used by admin/list flows)
  # ===========================================================================

  @doc "Returns the list of games."
  def list_games do
    Repo.all(Game)
  end

  @doc """
  Returns games for a team, newest-started first. Accepts a `%Team{}`
  or a binary team id.
  """
  def list_games_for_team(%Team{id: team_id}), do: list_games_for_team(team_id)

  def list_games_for_team(team_id) when is_binary(team_id) do
    Game
    |> where([g], g.team_id == ^team_id)
    |> order_by([g], desc: g.started_at)
    |> Repo.all()
  end

  @doc """
  Returns games for the teams `user` is a member of, newest-started
  first, with `:team` preloaded.
  """
  def list_games_for_user(%User{id: user_id}), do: list_games_for_user(user_id)

  def list_games_for_user(user_id) when is_binary(user_id) do
    from(g in Game,
      join: m in TeamMembership,
      on: m.team_id == g.team_id,
      where: m.user_id == ^user_id,
      order_by: [desc: g.started_at],
      distinct: true,
      preload: :team
    )
    |> Repo.all()
  end

  def list_games_for_user(_), do: []

  @doc "Gets a single game. Raises `Ecto.NoResultsError` if not found."
  def get_game!(id), do: Repo.get!(Game, id)

  @doc """
  Gets a game with its `:points` preloaded in `sequence` order. Raises
  if the game does not exist.
  """
  def get_game_with_points!(id) do
    Game
    |> Repo.get!(id)
    |> Repo.preload(points: from(p in Point, order_by: [asc: p.sequence]))
  end

  @doc "Creates a game."
  def create_game(attrs) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a game."
  def update_game(%Game{} = game, attrs) do
    game
    |> Game.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a game (cascades to points and events via FK)."
  def delete_game(%Game{} = game) do
    Repo.delete(game)
  end

  @doc "Returns an `%Ecto.Changeset{}` for tracking game changes."
  def change_game(%Game{} = game, attrs \\ %{}) do
    Game.changeset(game, attrs)
  end

  # ===========================================================================
  # Game lifecycle
  # ===========================================================================

  @doc """
  Starts a new game. Defaults `status: :in_progress` and
  `started_at: DateTime.utc_now/0` if not supplied.

  Ruleset resolution:

    * `ruleset_id` present → loads the template, runs
      `clone_ruleset_for_game/2` with `rule_overrides` (default
      `%{}`), and stores the resolved id on the game (which may be
      the template's own id if no overrides differ).
    * `ruleset_id` absent and `rule_overrides` empty → game stores
      `ruleset_id: nil`; reads fall back to USAU defaults.
    * `ruleset_id` absent but `rule_overrides` present → synthesizes a
      `:game_instance` row from `usau_standard_attrs/0` merged with
      the overrides, owned by the game's `team_id`, and stores its id.

  `rule_overrides` is consumed here and never passed to `create_game/1`.
  """
  def start_game(attrs) do
    attrs = normalize_keys(attrs)
    {ruleset_id, attrs} = Map.pop(attrs, :ruleset_id, nil)
    {rule_overrides, attrs} = Map.pop(attrs, :rule_overrides, %{})
    rule_overrides = rule_overrides || %{}

    with {:ok, resolved_id} <- resolve_ruleset_id(ruleset_id, rule_overrides, attrs[:team_id]) do
      attrs
      |> Map.put(:ruleset_id, resolved_id)
      |> Map.put_new(:status, :in_progress)
      |> Map.put_new_lazy(:started_at, &now/0)
      |> create_game()
    end
  end

  # No template + no overrides — game has no ruleset; defaults apply.
  defp resolve_ruleset_id(nil, overrides, _team_id) when overrides == %{},
    do: {:ok, nil}

  # No template, but overrides present — synthesize a :game_instance
  # off USAU defaults, owned by the game's team.
  defp resolve_ruleset_id(nil, overrides, team_id)
       when is_map(overrides) and is_binary(team_id) do
    attrs =
      usau_standard_attrs()
      |> Map.merge(overrides)
      |> Map.put(:team_id, team_id)
      |> Map.put(:kind, :game_instance)
      |> Map.put(:name, nil)

    case create_ruleset(attrs) do
      {:ok, instance} -> {:ok, instance.id}
      {:error, _changeset} = err -> err
    end
  end

  defp resolve_ruleset_id(nil, _overrides, _team_id), do: {:ok, nil}

  # Template provided — clone-on-write through the local helper.
  defp resolve_ruleset_id(ruleset_id, overrides, _team_id) when is_binary(ruleset_id) do
    template = get_ruleset!(ruleset_id)
    clone_ruleset_for_game(template, overrides || %{})
  end

  @doc """
  Ends the given game. Sets `ended_at` to now and `status` to
  `opts[:status]` (default `:finished`; `:abandoned` is also valid).
  """
  def end_game(%Game{} = game, opts \\ []) do
    status = Keyword.get(opts, :status, :finished)
    update_game(game, %{status: status, ended_at: now()})
  end

  # ===========================================================================
  # Point lifecycle
  # ===========================================================================

  @doc """
  Starts a new point on `game` with the given line of `user_ids`.

  User ids are filtered defensively to users who hold a membership on
  the game's team — ids belonging to another team are silently dropped
  (same pattern as line presets). Returns `{:error, changeset}` if the
  resulting filtered list is empty.
  """
  def start_point(%Game{} = game, user_ids) when is_list(user_ids) do
    scoped_ids = scope_user_ids_to_team(user_ids, game.team_id)

    if length(scoped_ids) != line_size_for(game) do
      {:error, :wrong_line_size}
    else
      attrs = %{
        game_id: game.id,
        sequence: next_point_sequence(game),
        our_line_snapshot: %{"user_ids" => scoped_ids},
        scoring_team: nil,
        started_at: now()
      }

      %Point{}
      |> Point.changeset(attrs)
      |> validate_non_empty_line(scoped_ids)
      |> Repo.insert()
    end
  end

  @doc """
  Ends a point by setting its `scoring_team`. Idempotent if already set
  to the same value; returns `{:error, :scoring_team_conflict}` if it's
  already set to a different value.
  """
  def end_point(%Point{scoring_team: existing} = point, scoring_team)
      when scoring_team in [:ours, :theirs] do
    cond do
      existing == scoring_team ->
        {:ok, point}

      not is_nil(existing) ->
        {:error, :scoring_team_conflict}

      true ->
        point
        |> Point.changeset(%{scoring_team: scoring_team, ended_at: now()})
        |> Repo.update()
    end
  end

  @doc """
  Reopens an ended point by clearing its `scoring_team`. Used by the
  live tracker's "undo last goal" flow when the tracker accidentally
  ended a point.
  """
  def reopen_point(%Point{} = point) do
    point
    |> Point.changeset(%{scoring_team: nil, ended_at: nil})
    |> Repo.update()
  end

  def reopen_point(point_id) when is_binary(point_id) do
    Repo.get!(Point, point_id)
    |> reopen_point()
  end

  @doc """
  Returns the active (in-progress) point for `game` — the one whose
  `scoring_team` is `nil` — or `nil` if the game has no point in
  progress.
  """
  def current_point(%Game{id: game_id}) do
    Point
    |> where([p], p.game_id == ^game_id and is_nil(p.scoring_team))
    |> order_by([p], desc: p.sequence)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Total number of points (in-progress and completed) for `game`. A
  cheap aggregate; lets callers fast-path fresh games (count == 0) so
  they can skip score / events / stoppage queries entirely.
  """
  def points_count(%Game{id: game_id}) do
    Point
    |> where([p], p.game_id == ^game_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Returns who starts the point with possession (`:ours` or `:theirs`).

  For point 1, the receiving team is the one that did **not** pull
  (`game.first_pull`). For later points, the team that scored the
  previous point pulls and the other team receives.
  """
  def starting_possession(%Game{} = game, %Point{sequence: 1}) do
    receiving_side(game.first_pull)
  end

  def starting_possession(%Game{id: game_id} = game, %Point{sequence: seq} = point)
      when seq > 1 do
    if first_second_half_point?(game, point) do
      # Halftime swaps who pulls — the team that pulled at game start
      # receives the second-half pull. So second-half-point-1's starting
      # possession is `game.first_pull` itself (no swap).
      game.first_pull
    else
      prev =
        Point
        |> where([p], p.game_id == ^game_id and p.sequence == ^(seq - 1))
        |> select([p], p.scoring_team)
        |> Repo.one()

      case prev do
        :ours -> :theirs
        :theirs -> :ours
        _ -> :ours
      end
    end
  end

  defp receiving_side(:ours), do: :theirs
  defp receiving_side(:theirs), do: :ours
  defp receiving_side(_), do: :ours

  @doc """
  The next `sequence` value for a new point on `game`. Returns `1` when
  the game has no points yet.
  """
  def next_point_sequence(%Game{id: game_id}) do
    Point
    |> where([p], p.game_id == ^game_id)
    |> select([p], max(p.sequence))
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  # ===========================================================================
  # Event capture
  # ===========================================================================

  @doc """
  Records a per-throw event on `point`. `passer_user_id` and
  `receiver_user_id` are both nullable — `nil` means "Unknown" (the
  tracker missed who threw or caught it). Per-type field shape is
  enforced in `Event.changeset/2`. Any non-nil id must belong to a
  user holding a membership on the game's team or the call returns
  `{:error, :user_not_on_team}`.
  """
  def record_throw(%Point{} = point, type, passer_user_id, receiver_user_id, opts \\ []) do
    valid_ids = Keyword.get(opts, :valid_user_ids)
    sequence = Keyword.get(opts, :sequence)

    with :ok <- check_user(point, passer_user_id, valid_ids),
         :ok <- check_user(point, receiver_user_id, valid_ids) do
      attrs = %{
        game_id: point.game_id,
        point_id: point.id,
        sequence: sequence || next_event_sequence(point),
        type: type,
        passer_user_id: passer_user_id,
        receiver_user_id: receiver_user_id,
        occurred_at: now()
      }

      %Event{}
      |> Event.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Records a `:goal` event and ends the point in a single transaction.
  Saves a round trip vs. calling `record_throw/5` and `end_point/2`
  separately, and guarantees the two writes succeed or fail together.
  Returns `{:ok, %{event: event, point: ended_point}}` on success.
  """
  def score_goal(%Point{} = point, scoring_team, passer_user_id, receiver_user_id, opts \\ [])
      when scoring_team in [:ours, :theirs] do
    Repo.transaction(fn ->
      with {:ok, event} <- record_throw(point, :goal, passer_user_id, receiver_user_id, opts),
           {:ok, ended} <- end_point(point, scoring_team) do
        %{event: event, point: ended}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # In-process validation when the caller has already loaded the team
  # roster (LiveView mount). Falls back to the DB-backed check if no
  # cached MapSet is provided.
  defp check_user(_point, nil, _valid), do: :ok

  defp check_user(_point, user_id, %MapSet{} = valid_ids) when is_binary(user_id) do
    if MapSet.member?(valid_ids, user_id), do: :ok, else: {:error, :user_not_on_team}
  end

  defp check_user(point, user_id, _no_cache), do: validate_user_on_team(point, user_id)

  @doc """
  Records a game-level annotation event (timeout / halftime). When the
  game has a current point in progress, the event attaches to that point
  and uses its event sequence. Between points, `point_id` is nil and the
  sequence falls back to a per-game counter.
  """
  def record_game_event(%Game{} = game, type)
      when type in [
             :timeout_ours,
             :timeout_theirs,
             :timeout_resume,
             :halftime,
             :halftime_resume
           ] do
    point = current_point(game)

    {point_id, sequence} =
      case point do
        %Point{} = p -> {p.id, next_event_sequence(p)}
        nil -> {nil, next_game_event_sequence(game)}
      end

    attrs = %{
      game_id: game.id,
      point_id: point_id,
      sequence: sequence,
      type: type,
      occurred_at: now()
    }

    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Soft-deletes an event by stamping `deleted_at`. The row stays in the
  database for audit; downstream reads filter it out.
  """
  def soft_delete_event(%Event{} = event) do
    event
    |> Event.changeset(%{deleted_at: now()})
    |> Repo.update()
  end

  @doc """
  Restores a soft-deleted event by clearing its `deleted_at` stamp.
  Used by the live tracker's redo flow.
  """
  def restore_event(%Event{} = event) do
    event
    |> Event.changeset(%{deleted_at: nil})
    |> Repo.update()
  end

  @doc """
  Updates an event's `type`, `passer_user_id`, and/or `receiver_user_id`.
  Used by the timeline edit flow. Other fields are not editable from
  the timeline (sequence and occurred_at are stable; deleted_at is set
  via `soft_delete_event/1`).

  When `:passer_user_id` or `:receiver_user_id` is provided (non-nil),
  the referenced user must hold a membership on the same team as the
  event's point's game; otherwise `{:error, :user_not_on_team}` is
  returned without touching the row.
  """
  def update_event(%Event{} = event, attrs) do
    attrs = normalize_keys(attrs)

    with :ok <- validate_update_user(event, Map.get(attrs, :passer_user_id, :unset)),
         :ok <- validate_update_user(event, Map.get(attrs, :receiver_user_id, :unset)) do
      event
      |> Event.update_changeset(attrs)
      |> Repo.update()
    end
  end

  defp validate_update_user(_event, :unset), do: :ok
  defp validate_update_user(_event, nil), do: :ok

  defp validate_update_user(%Event{point_id: point_id}, user_id) when is_binary(user_id) do
    point = Repo.get!(Point, point_id)
    validate_user_on_team(point, user_id)
  end

  @doc """
  Returns events for `point` filtered to live (non-deleted) rows,
  ordered by `sequence`.
  """
  def events_for_point(%Point{id: point_id}) do
    Event
    |> where([e], e.point_id == ^point_id and is_nil(e.deleted_at))
    |> order_by([e], asc: e.sequence)
    |> Repo.all()
  end

  @doc """
  Returns game-level events (those recorded between points, with
  `point_id IS NULL`) for `game`, filtered to live (non-deleted) rows
  and ordered by `occurred_at`. These are the stoppages
  (timeout/halftime/resume) that the timeline buckets between point
  sections.
  """
  def list_game_level_events(%Game{id: game_id}) do
    Event
    |> where([e], e.game_id == ^game_id and is_nil(e.point_id) and is_nil(e.deleted_at))
    |> order_by([e], asc: e.occurred_at)
    |> Repo.all()
  end

  @doc """
  The next `sequence` value for a new event on `point`. Counts only
  live (non-deleted) events; soft-deleted events do not bump sequence.
  Returns `1` when the point has no events yet.
  """
  def next_event_sequence(%Point{id: point_id}) do
    Event
    |> where([e], e.point_id == ^point_id and is_nil(e.deleted_at))
    |> select([e], max(e.sequence))
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  # Sequence used for game-level annotations recorded between points
  # (timeouts, halftime). Counts only events with `point_id IS NULL` so
  # the per-point sequence remains independent.
  defp next_game_event_sequence(%Game{id: game_id}) do
    Event
    |> where(
      [e],
      e.game_id == ^game_id and is_nil(e.point_id) and is_nil(e.deleted_at)
    )
    |> select([e], max(e.sequence))
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  # ===========================================================================
  # Score & lifecycle queries
  # ===========================================================================

  @doc """
  Returns the current score as `%{ours: integer, theirs: integer}`.
  Counts only points that have ended (`scoring_team` is not nil).
  """
  def score(%Game{id: game_id}) do
    # `:ours` is counted via non-deleted goal events on `:ours` points so
    # soft-deleting a goal in the timeline recomputes the score (per
    # MVP_SPEC.md step 7). `:theirs` is counted via points alone — opposing
    # goals don't have user-attributed events.
    ours =
      from(e in Event,
        join: p in Point,
        on: p.id == e.point_id,
        where:
          p.game_id == ^game_id and
            p.scoring_team == :ours and
            e.type == :goal and
            is_nil(e.deleted_at)
      )
      |> Repo.aggregate(:count, :id)

    theirs =
      from(p in Point,
        where: p.game_id == ^game_id and p.scoring_team == :theirs
      )
      |> Repo.aggregate(:count, :id)

    %{ours: ours, theirs: theirs}
  end

  @doc """
  True when a `:halftime` event has already been recorded for this game.
  Used to gate the halftime button (one halftime per game) and to switch
  the timeout counter from first-half to second-half allotment.
  """
  def halftime_recorded?(%Game{id: game_id}) do
    Event
    |> where(
      [e],
      e.game_id == ^game_id and e.type == :halftime and is_nil(e.deleted_at)
    )
    |> Repo.exists?()
  end

  @doc """
  Number of `:timeout_ours` events still available in the current half.
  Reads `timeouts_per_half` from the resolved ruleset; if halftime has
  been recorded, only timeouts that occurred after the halftime event
  count against the second-half allotment. Never goes below zero.
  """
  def timeouts_remaining(%Game{} = game) do
    stoppage_state(game).timeouts_remaining
  end

  @doc """
  Combined `halftime_recorded?` + `timeouts_remaining` in a single
  query. Mount and post-stoppage handlers used to fire both queries
  separately; on a sideline tracker the round-trips compound, so this
  consolidates them into one pass over `events`.

  Shape: `%{halftime_recorded?: boolean, timeouts_remaining: integer}`.
  """
  def stoppage_state(%Game{id: game_id} = game) do
    per_half = timeouts_per_half(game)

    rows =
      Event
      |> where(
        [e],
        e.game_id == ^game_id and is_nil(e.deleted_at) and
          e.type in [:halftime, :timeout_ours]
      )
      |> select([e], {e.type, e.occurred_at})
      |> Repo.all()

    halftime_at =
      Enum.find_value(rows, fn
        {:halftime, ts} -> ts
        _ -> nil
      end)

    used =
      Enum.count(rows, fn
        {:timeout_ours, ts} ->
          case halftime_at do
            nil -> true
            ht -> DateTime.compare(ts, ht) == :gt
          end

        _ ->
          false
      end)

    %{
      halftime_recorded?: not is_nil(halftime_at),
      timeouts_remaining: max(per_half - used, 0)
    }
  end

  @doc """
  True when the game has reached the halftime score by either team.
  Returns `false` when the game's resolved `halftime_target` is nil
  (no halftime-by-score for this ruleset).
  """
  def halftime?(%Game{} = game) do
    case halftime_threshold(game) do
      nil ->
        false

      target when is_integer(target) ->
        s = score(game)
        max(s.ours, s.theirs) >= target
    end
  end

  @doc """
  True when the game has reached the hard cap (score cap) by either
  team. Returns `false` when the resolved `score_cap` is nil (no
  score-based end condition; only `hard_cap_minutes` can end the game).
  """
  def hard_cap_reached?(%Game{} = game), do: hard_cap_reached?(game, score(game))

  @doc """
  Same as `hard_cap_reached?/1` but uses a precomputed score map. Use
  this in hot paths where the caller already has `%{ours:, theirs:}`
  in hand to avoid a second `score(game)` round-trip.
  """
  def hard_cap_reached?(%Game{} = game, %{ours: ours, theirs: theirs}) do
    case hard_cap_threshold(game) do
      nil -> false
      cap when is_integer(cap) -> max(ours, theirs) >= cap
    end
  end

  @doc """
  Resolved halftime target for `game`. Reads from `game.ruleset` when
  attached and returns its value (including `nil` when the ruleset
  explicitly opts out of halftime-by-score). Falls back to the USAU
  default only when the game has no ruleset attached.
  """
  def halftime_threshold(%Game{} = game) do
    fetch_ruleset_field(game, :halftime_target)
  end

  @doc """
  Resolved score cap for `game`. Reads from `game.ruleset` when
  attached and returns its value (including `nil` for timed-only
  formats). Falls back to the USAU default only when the game has
  no ruleset attached.
  """
  def hard_cap_threshold(%Game{} = game) do
    fetch_ruleset_field(game, :score_cap)
  end

  @doc "Resolved line size (players per point) for `game`. Falls back to USAU default 7."
  def line_size_for(%Game{} = game), do: fetch_ruleset_field(game, :line_size)

  @doc "Resolved per-half timeout allowance for `game`. Falls back to 0."
  def timeouts_per_half(%Game{} = game),
    do: fetch_ruleset_field(game, :timeouts_per_half) || 0

  @doc """
  Returns nil when `line` has exactly `required` players, otherwise
  `%{actual: integer, required: integer}` for non-blocking display.
  """
  def line_size_violation(line, required) when is_integer(required) and is_list(line) do
    actual = length(line)
    if actual == required, do: nil, else: %{actual: actual, required: required}
  end

  @doc """
  Required gender ratio for a given point of a game, derived from the
  game's ruleset. Returns `%{m: integer, f: integer}` carrying the
  required male / female-matching counts, or `nil` (when the rule is
  `:none` or either starting count is missing).

  Accepts either a `%Point{}` (uses `point.sequence`) or a 1-based integer
  for the next-point sequence (callable from the line picker before a
  point exists).
  """
  def required_ratio_for_point(%Game{} = game, %Point{sequence: seq}),
    do: required_ratio_for_point(game, seq)

  def required_ratio_for_point(%Game{} = game, seq) when is_integer(seq) and seq >= 1 do
    rule = fetch_ruleset_field(game, :gender_ratio_rule)
    m = fetch_ruleset_field(game, :starting_male_count)
    f = fetch_ruleset_field(game, :starting_female_count)

    cond do
      rule == :none ->
        nil

      not is_integer(m) or not is_integer(f) ->
        nil

      rule == :fixed ->
        %{m: m, f: f}

      rule in [:endzone, :alternating] ->
        if rem(seq, 2) == 1, do: %{m: m, f: f}, else: %{m: f, f: m}

      true ->
        nil
    end
  end

  @doc """
  Counts gender roles in a list. Accepts either `%TeamMembership{}` (reads
  `member.user.gender_role`) or `%User{}` shapes (reads `user.gender_role`).
  Returns `%{male_matching: n, female_matching: n}`.
  """
  def line_ratio_summary(line) when is_list(line) do
    Enum.reduce(line, %{male_matching: 0, female_matching: 0}, fn entry, acc ->
      role = gender_role_of(entry)

      case role do
        :male_matching -> %{acc | male_matching: acc.male_matching + 1}
        :female_matching -> %{acc | female_matching: acc.female_matching + 1}
        _ -> acc
      end
    end)
  end

  defp gender_role_of(%{user: %{gender_role: role}}), do: role
  defp gender_role_of(%{gender_role: role}), do: role
  defp gender_role_of(_), do: nil

  @doc """
  Returns `nil` when `line` matches the required ratio (or no ratio is
  required), otherwise `%{actual: %{m:, f:}, required: %{m:, f:}}` for the
  caller to render a non-blocking warning.
  """
  def line_ratio_violation(_line, nil), do: nil

  def line_ratio_violation(line, %{m: rm, f: rf} = required)
      when is_integer(rm) and is_integer(rf) do
    %{male_matching: m, female_matching: f} = line_ratio_summary(line)

    if m == rm and f == rf do
      nil
    else
      %{actual: %{m: m, f: f}, required: required}
    end
  end

  @doc "Human label for a required ratio (or 'Any composition' when nil)."
  def ratio_label(nil), do: "Any composition"
  def ratio_label(%{m: m, f: f}) when is_integer(m) and is_integer(f), do: "#{m}M / #{f}F"

  @doc """
  The `:ours`/`:theirs` possession the *next* point will start with,
  computed without needing a `%Point{}` to exist yet. Mirrors
  `starting_possession/2`: point 1 derives from `game.first_pull`; later
  points invert the most recently scored point's `scoring_team`.
  """
  def starting_possession_for_next_point(%Game{} = game) do
    cond do
      next_point_is_first_second_half?(game) ->
        game.first_pull

      true ->
        last =
          Point
          |> where([p], p.game_id == ^game.id and not is_nil(p.scoring_team))
          |> order_by([p], desc: p.sequence)
          |> limit(1)
          |> Repo.one()

        case last do
          nil -> receiving_side(game.first_pull)
          %Point{scoring_team: :ours} -> :theirs
          %Point{scoring_team: :theirs} -> :ours
          _ -> :ours
        end
    end
  end

  # Halftime occurred_at, or nil when no halftime event has been recorded.
  defp halftime_at(%Game{id: game_id}) do
    Event
    |> where([e], e.game_id == ^game_id and e.type == :halftime and is_nil(e.deleted_at))
    |> select([e], e.occurred_at)
    |> Repo.one()
  end

  # True when no point has started after halftime — i.e., the next point
  # to begin will be the first of the second half.
  defp next_point_is_first_second_half?(%Game{id: game_id} = game) do
    case halftime_at(game) do
      nil ->
        false

      ts ->
        not Repo.exists?(
          from(p in Point,
            where:
              p.game_id == ^game_id and not is_nil(p.started_at) and
                p.started_at > ^ts
          )
        )
    end
  end

  # True when `point` is the first one whose `started_at` is after the
  # halftime event — i.e., the first second-half point.
  defp first_second_half_point?(%Game{id: game_id} = game, %Point{} = point) do
    case halftime_at(game) do
      nil ->
        false

      ts ->
        cond do
          is_nil(point.started_at) ->
            false

          DateTime.compare(point.started_at, ts) != :gt ->
            false

          true ->
            not Repo.exists?(
              from(p in Point,
                where:
                  p.game_id == ^game_id and not is_nil(p.started_at) and
                    p.started_at > ^ts and p.sequence < ^point.sequence
              )
            )
        end
    end
  end

  defp fetch_ruleset_field(%Game{ruleset_id: nil}, key) do
    Map.get(usau_standard_attrs(), key)
  end

  defp fetch_ruleset_field(%Game{} = game, key) do
    game = ensure_ruleset_loaded(game)

    case game.ruleset do
      %Ruleset{} = r -> Map.get(r, key)
      _ -> Map.get(usau_standard_attrs(), key)
    end
  end

  defp ensure_ruleset_loaded(%Game{ruleset: %Ecto.Association.NotLoaded{}} = game),
    do: Repo.preload(game, :ruleset)

  defp ensure_ruleset_loaded(%Game{} = game), do: game

  # ===========================================================================
  # Game summary
  # ===========================================================================

  @doc """
  Returns the per-user summary for `game`. Soft-deleted events are
  excluded (`deleted_at IS NULL`).

  Shape:

      %{
        score: %{ours: integer, theirs: integer},
        players: [
          %{
            membership: %Ultistats.Teams.TeamMembership{user: %User{}},
            user: %Ultistats.Accounts.User{},
            goals: integer,
            assists: integer,
            catches: integer,
            drops: integer,
            throwaways: integer,
            blocks: integer,
            points_played: integer
          }
        ]
      }

  The `:players` list is the team's roster (memberships where
  `is_player == true`) so untracked players still appear with all-zero
  rows. Order: by `jersey_number` ascending — numeric jerseys sort
  numerically; non-numeric or missing jerseys sort to the end.

  Per-stat tallies count `e.type` matches on non-deleted events tied
  to `game`'s points. `:points_played` counts points where the user's id
  appears in the point's `our_line_snapshot["user_ids"]`. User ids
  that aren't on the team are ignored (defensive — they shouldn't be
  there per `start_point/2`).
  """
  def summary_for_game(%Game{} = game) do
    roster = Teams.list_players_for_team(game.team_id)
    roster_user_ids = MapSet.new(roster, & &1.user_id)

    points =
      Repo.all(
        from p in Point,
          where: p.game_id == ^game.id,
          select: %{
            id: p.id,
            our_line_snapshot: p.our_line_snapshot,
            scoring_team: p.scoring_team
          }
      )

    events =
      Repo.all(
        from e in Event,
          join: p in Point,
          on: p.id == e.point_id,
          where: p.game_id == ^game.id and is_nil(e.deleted_at),
          select: %{
            type: e.type,
            passer_user_id: e.passer_user_id,
            receiver_user_id: e.receiver_user_id
          }
      )

    # Per-user tallies. The same event contributes to up to two users:
    # the passer (assister / blocker / thrower / etc.) and the receiver
    # (catcher / scorer / dropper). `:goal` events count as a goal for
    # the receiver and an assist for the passer (assists are derived,
    # not their own event type).
    empty_tally = %{goals: 0, assists: 0, catches: 0, drops: 0, throwaways: 0, blocks: 0}

    tallies =
      Enum.reduce(events, %{}, fn ev, acc ->
        acc
        |> bump_passer(ev, roster_user_ids, empty_tally)
        |> bump_receiver(ev, roster_user_ids, empty_tally)
      end)

    # Per-user points-played tallies.
    points_played_by_user =
      Enum.reduce(points, %{}, fn point, acc ->
        ids = snapshot_user_ids(point.our_line_snapshot)

        Enum.reduce(ids, acc, fn uid, acc2 ->
          if MapSet.member?(roster_user_ids, uid) do
            Map.update(acc2, uid, 1, &(&1 + 1))
          else
            acc2
          end
        end)
      end)

    rows =
      roster
      |> Enum.sort_by(&jersey_sort_key/1)
      |> Enum.map(fn membership ->
        counts = Map.get(tallies, membership.user_id, empty_tally)

        Map.merge(counts, %{
          membership: membership,
          user: membership.user,
          points_played: Map.get(points_played_by_user, membership.user_id, 0)
        })
      end)

    %{score: score(game), players: rows}
  end

  @doc """
  Returns aggregate per-user tallies across every game on `team`.
  Soft-deleted events are excluded (`deleted_at IS NULL`).

  Same shape as `summary_for_game/1` minus the `:score` key — just the
  list of player rows:

      [
        %{
          membership: %Ultistats.Teams.TeamMembership{user: %User{}},
          user: %Ultistats.Accounts.User{},
          goals: integer,
          assists: integer,
          catches: integer,
          drops: integer,
          throwaways: integer,
          blocks: integer,
          points_played: integer
        }
      ]

  The roster (memberships where `is_player == true`) is the basis of
  the result, so untracked players still appear with all-zero rows.
  Order: by `jersey_number` ascending — numeric jerseys sort
  numerically; non-numeric or missing jerseys sort to the end.
  Accepts a `%Team{}` or a binary team id.
  """
  def leaderboard_for_team(%Team{id: team_id}), do: leaderboard_for_team(team_id)

  def leaderboard_for_team(team_id) when is_binary(team_id) do
    roster = Teams.list_players_for_team(team_id)
    roster_user_ids = MapSet.new(roster, & &1.user_id)

    points =
      Repo.all(
        from p in Point,
          join: g in Game,
          on: g.id == p.game_id,
          where: g.team_id == ^team_id,
          select: %{our_line_snapshot: p.our_line_snapshot}
      )

    events =
      Repo.all(
        from e in Event,
          join: p in Point,
          on: p.id == e.point_id,
          join: g in Game,
          on: g.id == p.game_id,
          where: g.team_id == ^team_id and is_nil(e.deleted_at),
          select: %{
            type: e.type,
            passer_user_id: e.passer_user_id,
            receiver_user_id: e.receiver_user_id
          }
      )

    empty_tally = %{goals: 0, assists: 0, catches: 0, drops: 0, throwaways: 0, blocks: 0}

    tallies =
      Enum.reduce(events, %{}, fn ev, acc ->
        acc
        |> bump_passer(ev, roster_user_ids, empty_tally)
        |> bump_receiver(ev, roster_user_ids, empty_tally)
      end)

    points_played_by_user =
      Enum.reduce(points, %{}, fn point, acc ->
        ids = snapshot_user_ids(point.our_line_snapshot)

        Enum.reduce(ids, acc, fn uid, acc2 ->
          if MapSet.member?(roster_user_ids, uid) do
            Map.update(acc2, uid, 1, &(&1 + 1))
          else
            acc2
          end
        end)
      end)

    roster
    |> Enum.sort_by(&jersey_sort_key/1)
    |> Enum.map(fn membership ->
      counts = Map.get(tallies, membership.user_id, empty_tally)

      Map.merge(counts, %{
        membership: membership,
        user: membership.user,
        points_played: Map.get(points_played_by_user, membership.user_id, 0)
      })
    end)
  end

  def leaderboard_for_team(_), do: []

  @doc """
  Returns a `%{user_id => count}` map of points played per user in `game`.

  A user "played" a point if their id appears in
  `our_line_snapshot["user_ids"]`. Includes the in-progress point so the
  between-points line picker reflects points-played in real time.
  """
  def points_played_by_user(%Game{id: game_id}) do
    Repo.all(
      from p in Point,
        where: p.game_id == ^game_id,
        select: p.our_line_snapshot
    )
    |> Enum.reduce(%{}, fn snap, acc ->
      snap
      |> snapshot_user_ids()
      |> Enum.reduce(acc, fn uid, acc2 -> Map.update(acc2, uid, 1, &(&1 + 1)) end)
    end)
  end

  defp snapshot_user_ids(%{"user_ids" => ids}) when is_list(ids), do: ids
  defp snapshot_user_ids(_), do: []

  defp bump_passer(acc, %{passer_user_id: nil}, _roster, _empty), do: acc

  defp bump_passer(acc, %{type: type, passer_user_id: uid}, roster, empty) do
    if MapSet.member?(roster, uid) do
      Map.update(acc, uid, bump(empty, passer_stat(type)), &bump(&1, passer_stat(type)))
    else
      acc
    end
  end

  defp bump_receiver(acc, %{receiver_user_id: nil}, _roster, _empty), do: acc

  defp bump_receiver(acc, %{type: type, receiver_user_id: uid}, roster, empty) do
    if MapSet.member?(roster, uid) do
      Map.update(acc, uid, bump(empty, receiver_stat(type)), &bump(&1, receiver_stat(type)))
    else
      acc
    end
  end

  defp passer_stat(:catch), do: nil
  defp passer_stat(:goal), do: :assists
  defp passer_stat(:throwaway), do: :throwaways
  defp passer_stat(:drop), do: :throwaways
  defp passer_stat(:block), do: :blocks
  defp passer_stat(_), do: nil

  defp receiver_stat(:catch), do: :catches
  defp receiver_stat(:goal), do: :goals
  defp receiver_stat(:drop), do: :drops
  defp receiver_stat(_), do: nil

  defp bump(tally, nil), do: tally
  defp bump(tally, stat), do: Map.update!(tally, stat, &(&1 + 1))

  # Sort key: {0, n} for numeric jerseys (so they come first in number
  # order), {1, raw} for non-numeric strings (alphabetic among themselves
  # but after all numbers), {2, ""} for missing. Keeps the comparator
  # total even when the roster mixes numeric and non-numeric entries.
  # Uses the resolved jersey (per-team override beats user default).
  defp jersey_sort_key(%TeamMembership{} = membership) do
    case Teams.resolved_jersey_number(membership) do
      nil ->
        {2, ""}

      "" ->
        {2, ""}

      n when is_binary(n) ->
        case Integer.parse(n) do
          {int, ""} -> {0, int}
          _ -> {1, n}
        end
    end
  end

  # ===========================================================================
  # Internal helpers
  # ===========================================================================

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  # Accept either atom or string keys on attrs; we standardize to atoms
  # for the Map.put_new defaults inside `start_game/1`.
  defp normalize_keys(attrs) when is_map(attrs) do
    Enum.into(attrs, %{}, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
  rescue
    ArgumentError -> attrs
  end

  defp scope_user_ids_to_team([], _team_id), do: []
  defp scope_user_ids_to_team(_ids, nil), do: []

  defp scope_user_ids_to_team(user_ids, team_id) when is_list(user_ids) do
    valid =
      from(m in TeamMembership,
        where: m.team_id == ^team_id and m.user_id in ^user_ids,
        select: m.user_id
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.filter(user_ids, &MapSet.member?(valid, &1))
  end

  defp validate_non_empty_line(changeset, []) do
    Ecto.Changeset.add_error(
      changeset,
      :our_line_snapshot,
      "must include at least one user from the team's roster"
    )
  end

  defp validate_non_empty_line(changeset, _ids), do: changeset

  defp validate_user_on_team(_point, nil), do: :ok

  defp validate_user_on_team(%Point{game_id: game_id}, user_id) when is_binary(user_id) do
    query =
      from g in Game,
        join: m in TeamMembership,
        on: m.team_id == g.team_id,
        where: g.id == ^game_id and m.user_id == ^user_id,
        select: m.user_id

    case Repo.one(query) do
      nil -> {:error, :user_not_on_team}
      _ -> :ok
    end
  end

  # ===========================================================================
  # Ruleset CRUD
  # ===========================================================================

  @ruleset_overridable_fields [
    :score_cap,
    :halftime_target,
    :halftime_cap_minutes,
    :soft_cap_minutes,
    :hard_cap_minutes,
    :timeouts_per_half,
    :line_size,
    :gender_ratio_rule,
    :starting_male_count,
    :starting_female_count
  ]

  @doc """
  Returns the ruleset templates for a given team — `kind == :template`,
  not archived, ordered by name asc. Per-game `:game_instance` rows
  are excluded (they're anonymous clones, never shown in the library).
  """
  def list_rulesets_for_team(%Team{id: team_id}), do: list_rulesets_for_team(team_id)

  def list_rulesets_for_team(team_id) when is_binary(team_id) do
    list_rulesets_for_team(team_id, nil)
  end

  @doc """
  Same as `list_rulesets_for_team/1` but filtered to rulesets matching
  `division` (atom). Pass `nil` to skip the division filter.
  """
  def list_rulesets_for_team(%Team{id: team_id}, division),
    do: list_rulesets_for_team(team_id, division)

  def list_rulesets_for_team(team_id, nil) when is_binary(team_id) do
    Ruleset
    |> where([r], r.team_id == ^team_id)
    |> where([r], r.kind == :template and is_nil(r.archived_at))
    |> order_by([r], asc: r.name)
    |> Repo.all()
  end

  def list_rulesets_for_team(team_id, division)
      when is_binary(team_id) and division in [:open, :womens, :mixed] do
    Ruleset
    |> where([r], r.team_id == ^team_id and r.division == ^division)
    |> where([r], r.kind == :template and is_nil(r.archived_at))
    |> order_by([r], asc: r.name)
    |> Repo.all()
  end

  @doc """
  Returns all `:template` rulesets across teams — not archived,
  ordered by name asc, with `:team` preloaded. Used by the global
  Rulesets tab on the games index.
  """
  def list_rulesets_across_teams do
    Ruleset
    |> where([r], r.kind == :template and is_nil(r.archived_at))
    |> order_by([r], asc: r.name)
    |> preload(:team)
    |> Repo.all()
  end

  @doc """
  Returns `:template` rulesets for the teams `user` is a member of —
  not archived, ordered by name asc, with `:team` preloaded. Replaces
  `list_rulesets_across_teams/0` in user-scoped contexts.
  """
  def list_rulesets_for_user(%User{id: user_id}), do: list_rulesets_for_user(user_id)

  def list_rulesets_for_user(user_id) when is_binary(user_id) do
    from(r in Ruleset,
      join: m in TeamMembership,
      on: m.team_id == r.team_id,
      where: m.user_id == ^user_id and r.kind == :template and is_nil(r.archived_at),
      order_by: [asc: r.name],
      distinct: true,
      preload: :team
    )
    |> Repo.all()
  end

  def list_rulesets_for_user(_), do: []

  @doc """
  Gets a single ruleset by id, regardless of `:kind` or archival
  status. Used by Games when reading the rule snapshot for a game.
  """
  def get_ruleset!(id), do: Repo.get!(Ruleset, id)

  @doc """
  Creates a ruleset. Defaults `:kind` to `:template` if not supplied.
  """
  def create_ruleset(attrs) do
    attrs = put_default_kind(attrs)

    %Ruleset{}
    |> Ruleset.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a ruleset with clone-on-write semantics.

  If the ruleset has any games referencing it, the existing row is
  archived (`archived_at: now()`) and a brand-new `:template` row is
  inserted carrying the user's edits and the same name. In-flight and
  finished games keep pointing at the old (now-archived) row, so their
  rules don't change retroactively.

  If the ruleset has no referencing games, the row is updated in
  place — no archival churn.

  The whole operation runs in a transaction.
  """
  def update_ruleset(%Ruleset{} = ruleset, attrs) do
    if referenced_by_any_game?(ruleset.id) do
      Repo.transaction(fn ->
        {:ok, _archived} =
          ruleset
          |> Ruleset.changeset(%{archived_at: now()})
          |> Repo.update()

        merged =
          ruleset
          |> ruleset_attrs_for_clone()
          |> Map.merge(normalize_ruleset_attrs(attrs))
          |> Map.put(:team_id, ruleset.team_id)
          |> Map.put(:kind, :template)
          |> Map.put(:name, get_attr(attrs, :name) || ruleset.name)
          |> Map.put(:archived_at, nil)

        case create_ruleset(merged) do
          {:ok, new_ruleset} -> new_ruleset
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    else
      ruleset
      |> Ruleset.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes a ruleset. Refuses with `{:error, :referenced_by_games}`
  if any game references it — the UI should archive instead.
  """
  def delete_ruleset(%Ruleset{} = ruleset) do
    if referenced_by_any_game?(ruleset.id) do
      {:error, :referenced_by_games}
    else
      Repo.delete(ruleset)
    end
  end

  @doc """
  Soft-removes a ruleset from the team's library by setting
  `archived_at` to now. The row stays in the database so existing
  games keep resolving their rules.
  """
  def archive_ruleset(%Ruleset{} = ruleset) do
    ruleset
    |> Ruleset.changeset(%{archived_at: now()})
    |> Repo.update()
  end

  @doc "Returns an `%Ecto.Changeset{}` for tracking ruleset changes."
  def change_ruleset(%Ruleset{} = ruleset, attrs \\ %{}) do
    Ruleset.changeset(ruleset, attrs)
  end

  @doc """
  Resolve a ruleset id for a game given a `:template` ruleset and a
  map of per-game overrides.

  Returns `{:ok, ruleset_id}`:

    * If `overrides` is empty or every override key matches the
      template's current value, returns the template's own id (no
      insert — game references the template directly).
    * Otherwise inserts a `:game_instance` row carrying the template's
      values merged with the overrides and returns its id.

  The instance row has no name and is owned by the same team as the
  template.
  """
  def clone_ruleset_for_game(%Ruleset{} = template, overrides) when is_map(overrides) do
    overrides = normalize_ruleset_attrs(overrides)
    base = ruleset_attrs_for_clone(template)

    if overrides_match_template?(template, overrides) do
      {:ok, template.id}
    else
      attrs =
        base
        |> Map.merge(overrides)
        |> Map.put(:team_id, template.team_id)
        |> Map.put(:kind, :game_instance)
        |> Map.put(:name, nil)
        |> Map.put(:archived_at, nil)

      case create_ruleset(attrs) do
        {:ok, instance} -> {:ok, instance.id}
        {:error, _changeset} = err -> err
      end
    end
  end

  # ----- private helpers for ruleset CRUD -----

  defp put_default_kind(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :kind) -> attrs
      Map.has_key?(attrs, "kind") -> attrs
      true -> Map.put(attrs, :kind, :template)
    end
  end

  defp ruleset_attrs_for_clone(%Ruleset{} = ruleset) do
    Map.new(@ruleset_overridable_fields, fn key -> {key, Map.get(ruleset, key)} end)
  end

  defp normalize_ruleset_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn {k, v}, acc ->
      key =
        cond do
          is_atom(k) -> k
          is_binary(k) -> safe_to_existing_atom(k)
          true -> nil
        end

      if is_atom(key) and key in @ruleset_overridable_fields do
        Map.put(acc, key, v)
      else
        acc
      end
    end)
  end

  defp safe_to_existing_atom(s) when is_binary(s) do
    String.to_existing_atom(s)
  rescue
    ArgumentError -> nil
  end

  defp get_attr(attrs, key) when is_atom(key) and is_map(attrs) do
    case Map.fetch(attrs, key) do
      {:ok, v} -> v
      :error -> Map.get(attrs, Atom.to_string(key))
    end
  end

  defp overrides_match_template?(%Ruleset{} = template, overrides) when is_map(overrides) do
    Enum.all?(overrides, fn {key, value} ->
      Map.get(template, key) == value
    end)
  end

  defp referenced_by_any_game?(ruleset_id) when is_binary(ruleset_id) do
    Game
    |> where([g], g.ruleset_id == ^ruleset_id)
    |> select([g], 1)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> false
      _ -> true
    end
  end
end
