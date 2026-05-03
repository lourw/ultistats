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

  alias Ultistats.Games.{Event, Game, Point, Ruleset}
  alias Ultistats.Teams
  alias Ultistats.Teams.{Player, Team}

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
      gender_ratio_rule: :endzone,
      default_starting_ratio: :four_men_three_women
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
  Starts a new point on `game` with the given line of `player_ids`.

  Player ids are filtered defensively to the game's team — ids belonging
  to another team are silently dropped (same pattern as line presets).
  Returns `{:error, changeset}` if the resulting filtered list is empty.
  """
  def start_point(%Game{} = game, player_ids) when is_list(player_ids) do
    scoped_ids = scope_player_ids_to_team(player_ids, game.team_id)

    attrs = %{
      game_id: game.id,
      sequence: next_point_sequence(game),
      our_line_snapshot: %{"player_ids" => scoped_ids},
      scoring_team: nil
    }

    %Point{}
    |> Point.changeset(attrs)
    |> validate_non_empty_line(scoped_ids)
    |> Repo.insert()
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
        |> Point.changeset(%{scoring_team: scoring_team})
        |> Repo.update()
    end
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
  Returns who starts the point with possession (`:ours` or `:theirs`).

  For point 1, the receiving team is the one that did **not** pull
  (`game.first_pull`). For later points, the team that scored the
  previous point pulls and the other team receives.
  """
  def starting_possession(%Game{} = game, %Point{sequence: 1}) do
    receiving_side(game.first_pull)
  end

  def starting_possession(%Game{id: game_id}, %Point{sequence: seq}) when seq > 1 do
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
  Records a per-throw event on `point`. `passer_id` and `receiver_id`
  are both nullable — `nil` means "Unknown" (the tracker missed who
  threw or caught it). Per-type field shape is enforced in
  `Event.changeset/2`. Any non-nil id must belong to the game's team
  or the call returns `{:error, :player_not_on_team}`.
  """
  def record_throw(%Point{} = point, type, passer_id, receiver_id \\ nil) do
    with :ok <- validate_player_on_team(point, passer_id),
         :ok <- validate_player_on_team(point, receiver_id) do
      attrs = %{
        point_id: point.id,
        sequence: next_event_sequence(point),
        type: type,
        passer_id: passer_id,
        receiver_id: receiver_id,
        occurred_at: now()
      }

      %Event{}
      |> Event.changeset(attrs)
      |> Repo.insert()
    end
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
  Updates an event's `type`, `passer_id`, and/or `receiver_id`. Used by
  the timeline edit flow. Other fields are not editable from the
  timeline (sequence and occurred_at are stable; deleted_at is set via
  `soft_delete_event/1`).

  When `:passer_id` or `:receiver_id` is provided (non-nil), it must
  belong to the same team as the event's point's game; otherwise
  `{:error, :player_not_on_team}` is returned without touching the row.
  """
  def update_event(%Event{} = event, attrs) do
    attrs = normalize_keys(attrs)

    with :ok <- validate_update_player(event, Map.get(attrs, :passer_id, :unset)),
         :ok <- validate_update_player(event, Map.get(attrs, :receiver_id, :unset)) do
      event
      |> Event.update_changeset(attrs)
      |> Repo.update()
    end
  end

  defp validate_update_player(_event, :unset), do: :ok
  defp validate_update_player(_event, nil), do: :ok

  defp validate_update_player(%Event{point_id: point_id}, player_id) when is_binary(player_id) do
    point = Repo.get!(Point, point_id)
    validate_player_on_team(point, player_id)
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
    # goals don't have player-attributed events.
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
  def hard_cap_reached?(%Game{} = game) do
    case hard_cap_threshold(game) do
      nil ->
        false

      cap when is_integer(cap) ->
        s = score(game)
        max(s.ours, s.theirs) >= cap
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
  Returns the per-player summary for `game`. Soft-deleted events are
  excluded (`deleted_at IS NULL`).

  Shape:

      %{
        score: %{ours: integer, theirs: integer},
        players: [
          %{
            player: %Ultistats.Teams.Player{},
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

  The `:players` list is the team's roster (so untracked players still
  appear with all-zero rows). Order: by `jersey_number` ascending —
  numeric jerseys sort numerically; non-numeric or missing jerseys sort
  to the end.

  Per-stat tallies count `e.type` matches on non-deleted events tied to
  `game`'s points. `:points_played` counts points where the player's id
  appears in the point's `our_line_snapshot["player_ids"]`. Player ids
  that aren't on the team are ignored (defensive — they shouldn't be
  there per `start_point/2`).
  """
  def summary_for_game(%Game{} = game) do
    roster = Teams.list_players_for_team(game.team_id)
    roster_ids = MapSet.new(roster, & &1.id)

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
          select: %{type: e.type, passer_id: e.passer_id, receiver_id: e.receiver_id}
      )

    # Per-player tallies. The same event contributes to up to two
    # players: the passer (assister / blocker / thrower / etc.) and the
    # receiver (catcher / scorer / dropper). `:goal` events count as a
    # goal for the receiver and an assist for the passer (assists are
    # derived, not their own event type).
    empty_tally = %{goals: 0, assists: 0, catches: 0, drops: 0, throwaways: 0, blocks: 0}

    tallies =
      Enum.reduce(events, %{}, fn ev, acc ->
        acc
        |> bump_passer(ev, roster_ids, empty_tally)
        |> bump_receiver(ev, roster_ids, empty_tally)
      end)

    # Per-player points-played tallies.
    points_played_by_player =
      Enum.reduce(points, %{}, fn point, acc ->
        ids = snapshot_player_ids(point.our_line_snapshot)

        Enum.reduce(ids, acc, fn pid, acc2 ->
          if MapSet.member?(roster_ids, pid) do
            Map.update(acc2, pid, 1, &(&1 + 1))
          else
            acc2
          end
        end)
      end)

    rows =
      roster
      |> Enum.sort_by(&jersey_sort_key/1)
      |> Enum.map(fn player ->
        counts = Map.get(tallies, player.id, empty_tally)

        Map.merge(counts, %{
          player: player,
          points_played: Map.get(points_played_by_player, player.id, 0)
        })
      end)

    %{score: score(game), players: rows}
  end

  defp bump_passer(acc, %{passer_id: nil}, _roster, _empty), do: acc

  defp bump_passer(acc, %{type: type, passer_id: pid}, roster, empty) do
    if MapSet.member?(roster, pid) do
      Map.update(acc, pid, bump(empty, passer_stat(type)), &bump(&1, passer_stat(type)))
    else
      acc
    end
  end

  defp bump_receiver(acc, %{receiver_id: nil}, _roster, _empty), do: acc

  defp bump_receiver(acc, %{type: type, receiver_id: rid}, roster, empty) do
    if MapSet.member?(roster, rid) do
      Map.update(acc, rid, bump(empty, receiver_stat(type)), &bump(&1, receiver_stat(type)))
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

  defp snapshot_player_ids(%{"player_ids" => ids}) when is_list(ids), do: ids
  defp snapshot_player_ids(_), do: []

  # Sort key: {0, n} for numeric jerseys (so they come first in number
  # order), {1, raw} for non-numeric strings (alphabetic among themselves
  # but after all numbers), {2, ""} for missing. Keeps the comparator
  # total even when the roster mixes numeric and non-numeric entries.
  defp jersey_sort_key(%Player{jersey_number: nil}), do: {2, ""}
  defp jersey_sort_key(%Player{jersey_number: ""}), do: {2, ""}

  defp jersey_sort_key(%Player{jersey_number: n}) when is_binary(n) do
    case Integer.parse(n) do
      {int, ""} -> {0, int}
      _ -> {1, n}
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

  defp scope_player_ids_to_team([], _team_id), do: []
  defp scope_player_ids_to_team(_ids, nil), do: []

  defp scope_player_ids_to_team(player_ids, team_id) when is_list(player_ids) do
    valid =
      Player
      |> where([p], p.team_id == ^team_id and p.id in ^player_ids)
      |> select([p], p.id)
      |> Repo.all()
      |> MapSet.new()

    Enum.filter(player_ids, &MapSet.member?(valid, &1))
  end

  defp validate_non_empty_line(changeset, []) do
    Ecto.Changeset.add_error(
      changeset,
      :our_line_snapshot,
      "must include at least one player from the team's roster"
    )
  end

  defp validate_non_empty_line(changeset, _ids), do: changeset

  defp validate_player_on_team(_point, nil), do: :ok

  defp validate_player_on_team(%Point{game_id: game_id}, player_id) when is_binary(player_id) do
    query =
      from p in Player,
        join: g in Game,
        on: g.team_id == p.team_id,
        where: g.id == ^game_id and p.id == ^player_id,
        select: p.id

    case Repo.one(query) do
      nil -> {:error, :player_not_on_team}
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
    :gender_ratio_rule,
    :default_starting_ratio
  ]

  @doc """
  Returns the ruleset templates for a given team — `kind == :template`,
  not archived, ordered by name asc. Per-game `:game_instance` rows
  are excluded (they're anonymous clones, never shown in the library).
  """
  def list_rulesets_for_team(%Team{id: team_id}), do: list_rulesets_for_team(team_id)

  def list_rulesets_for_team(team_id) when is_binary(team_id) do
    Ruleset
    |> where([r], r.team_id == ^team_id)
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
