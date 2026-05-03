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

  alias Ultistats.Games.{Event, Game, Point}
  alias Ultistats.Teams
  alias Ultistats.Teams.{Player, Team}

  # ---- USAU rule constants (single-format MVP) ----
  @usau_halftime_score 8
  @usau_hard_cap_score 15

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
  """
  def start_game(attrs) do
    attrs
    |> normalize_keys()
    |> Map.put_new(:status, :in_progress)
    |> Map.put_new_lazy(:started_at, &now/0)
    |> create_game()
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
  Records a new event on `point`. `player_id` may be `nil` for events
  not pinned to a player; when given, it must belong to the game's team
  or the call returns `{:error, :player_not_on_team}`.
  """
  def record_event(%Point{} = point, type, player_id)
      when type in [:goal, :assist, :block, :turn] do
    with :ok <- validate_player_on_team(point, player_id) do
      attrs = %{
        point_id: point.id,
        sequence: next_event_sequence(point),
        type: type,
        player_id: player_id,
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
  Updates an event's `type` and/or `player_id`. Used by the timeline
  edit flow. Other fields are not editable from the timeline (sequence
  and occurred_at are stable; deleted_at is set via
  `soft_delete_event/1`).

  When `:player_id` is provided (non-nil), it must belong to the same
  team as the event's point's game; otherwise `{:error,
  :player_not_on_team}` is returned without touching the row.
  """
  def update_event(%Event{} = event, attrs) do
    attrs = normalize_keys(attrs)
    player_id = Map.get(attrs, :player_id, :unset)

    with :ok <- validate_event_player(event, player_id) do
      event
      |> Event.update_changeset(attrs)
      |> Repo.update()
    end
  end

  defp validate_event_player(_event, :unset), do: :ok
  defp validate_event_player(_event, nil), do: :ok

  defp validate_event_player(%Event{point_id: point_id}, player_id) when is_binary(player_id) do
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
  True when the game has reached the halftime score for its format
  (`:usau_standard` → 8 by either team).
  """
  def halftime?(%Game{} = game) do
    s = score(game)
    max(s.ours, s.theirs) >= halftime_threshold(game)
  end

  @doc """
  True when the game has reached the hard cap for its format
  (`:usau_standard` → 15 by either team).
  """
  def hard_cap_reached?(%Game{} = game) do
    s = score(game)
    max(s.ours, s.theirs) >= hard_cap_threshold(game)
  end

  defp halftime_threshold(%Game{format: :usau_standard}), do: @usau_halftime_score
  defp hard_cap_threshold(%Game{format: :usau_standard}), do: @usau_hard_cap_score

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
            blocks: integer,
            turns: integer,
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
          select: %{type: e.type, player_id: e.player_id}
      )

    # Per-player event tallies. Map of player_id => %{goal: n, assist: n, ...}.
    event_tallies =
      events
      |> Enum.filter(&(not is_nil(&1.player_id) and MapSet.member?(roster_ids, &1.player_id)))
      |> Enum.group_by(& &1.player_id)
      |> Map.new(fn {pid, evs} ->
        counts = Enum.frequencies_by(evs, & &1.type)
        {pid, counts}
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
        counts = Map.get(event_tallies, player.id, %{})

        %{
          player: player,
          goals: Map.get(counts, :goal, 0),
          assists: Map.get(counts, :assist, 0),
          blocks: Map.get(counts, :block, 0),
          turns: Map.get(counts, :turn, 0),
          points_played: Map.get(points_played_by_player, player.id, 0)
        }
      end)

    %{score: score(game), players: rows}
  end

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
end
