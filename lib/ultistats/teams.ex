defmodule Ultistats.Teams do
  @moduledoc """
  The Teams context.
  """

  import Ecto.Query, warn: false
  alias Ultistats.Repo

  alias Ultistats.Teams.Team

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

  alias Ultistats.Teams.Player

  @doc """
  Returns the list of players.

  ## Examples

      iex> list_players()
      [%Player{}, ...]

  """
  def list_players do
    Player
    |> order_by([p], asc: p.jersey_number)
    |> preload(:team)
    |> Repo.all()
  end

  @doc """
  Returns the list of players for a given team, ordered by jersey number.

  ## Examples

      iex> list_players_for_team(team)
      [%Player{}, ...]

  """
  def list_players_for_team(%Team{id: team_id}), do: list_players_for_team(team_id)

  def list_players_for_team(team_id) when is_binary(team_id) do
    Player
    |> where([p], p.team_id == ^team_id)
    |> order_by([p], asc: p.jersey_number)
    |> Repo.all()
  end

  @doc """
  Gets a single player.

  Raises `Ecto.NoResultsError` if the Player does not exist.

  ## Examples

      iex> get_player!(123)
      %Player{}

      iex> get_player!(456)
      ** (Ecto.NoResultsError)

  """
  def get_player!(id), do: Repo.get!(Player, id)

  @doc """
  Creates a player.

  ## Examples

      iex> create_player(%{field: value})
      {:ok, %Player{}}

      iex> create_player(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_player(attrs) do
    %Player{}
    |> Player.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a player.

  ## Examples

      iex> update_player(player, %{field: new_value})
      {:ok, %Player{}}

      iex> update_player(player, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_player(%Player{} = player, attrs) do
    player
    |> Player.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a player.

  ## Examples

      iex> delete_player(player)
      {:ok, %Player{}}

      iex> delete_player(player)
      {:error, %Ecto.Changeset{}}

  """
  def delete_player(%Player{} = player) do
    Repo.delete(player)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking player changes.

  ## Examples

      iex> change_player(player)
      %Ecto.Changeset{data: %Player{}}

  """
  def change_player(%Player{} = player, attrs \\ %{}) do
    Player.changeset(player, attrs)
  end

  @doc """
  Inserts many players for a team in a single transaction.

  Rows whose `:first_name` (or `"first_name"`) is blank or missing are
  dropped before insert — the caller can pass over-allocated row buffers
  (e.g. three blank starter rows in the bulk-add form). Any `team_id` in
  the row map is ignored; the FK is always set from the `team` argument
  so the form can't smuggle a player onto another team.

  Returns:

    * `{:ok, [%Player{}, ...]}` — all rows inserted.
    * `{:error, {row_index, %Ecto.Changeset{}}}` — index is into the
      *post-filter* (non-blank) row list, so the LiveView can attach
      the error back to the right row. The whole transaction is rolled
      back; nothing is persisted on failure.
  """
  @spec bulk_create_players(Team.t(), [map()]) ::
          {:ok, [Player.t()]} | {:error, {non_neg_integer(), Ecto.Changeset.t()}}
  def bulk_create_players(%Team{} = team, rows) when is_list(rows) do
    non_blank =
      rows
      |> Enum.map(&normalize_row/1)
      |> Enum.reject(&blank_row?/1)

    multi =
      non_blank
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {attrs, idx}, multi ->
        attrs = attrs |> Map.delete(:team_id) |> Map.put(:team_id, team.id)
        Ecto.Multi.insert(multi, {:player, idx}, Player.changeset(%Player{}, attrs))
      end)

    case Repo.transaction(multi) do
      {:ok, results} ->
        players =
          results
          |> Enum.filter(fn
            {{:player, _}, _} -> true
            _ -> false
          end)
          |> Enum.sort_by(fn {{:player, idx}, _} -> idx end)
          |> Enum.map(fn {_, player} -> player end)

        {:ok, players}

      {:error, {:player, idx}, changeset, _changes} ->
        {:error, {idx, changeset}}
    end
  end

  defp normalize_row(row) when is_map(row) do
    %{
      first_name: fetch_row(row, :first_name) || "",
      last_name: fetch_row(row, :last_name) || "",
      jersey_number: fetch_row(row, :jersey_number),
      gender_role: fetch_row(row, :gender_role)
    }
  end

  defp fetch_row(row, key) when is_atom(key) do
    case Map.fetch(row, key) do
      {:ok, v} -> v
      :error -> Map.get(row, Atom.to_string(key))
    end
  end

  # A row is "blank" iff first AND last name are both empty/whitespace.
  # That way starter blanks are dropped, but a row with only one name
  # still tries to insert and surfaces a validation error.
  defp blank_row?(%{first_name: first, last_name: last}) do
    blank_string?(first) and blank_string?(last)
  end

  defp blank_string?(nil), do: true
  defp blank_string?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank_string?(_), do: true

  alias Ultistats.Teams.LinePreset

  @doc """
  Returns the list of line_presets (across all teams), with players preloaded.
  """
  def list_line_presets do
    LinePreset
    |> order_by([lp], asc: lp.name)
    |> preload(:players)
    |> Repo.all()
  end

  @doc """
  Returns the line presets for a given team, ordered by name, with
  players preloaded.
  """
  def list_line_presets_for_team(%Team{id: team_id}), do: list_line_presets_for_team(team_id)

  def list_line_presets_for_team(team_id) when is_binary(team_id) do
    LinePreset
    |> where([lp], lp.team_id == ^team_id)
    |> order_by([lp], asc: lp.name)
    |> preload(:players)
    |> Repo.all()
  end

  @doc """
  Gets a single line_preset, with `:players` preloaded so an edit form
  can populate selection state.

  Raises `Ecto.NoResultsError` if the Line preset does not exist.
  """
  def get_line_preset!(id) do
    LinePreset
    |> Repo.get!(id)
    |> Repo.preload(:players)
  end

  @doc """
  Creates a line_preset.

  Accepts a `:player_ids` (or `"player_ids"`) key alongside the usual
  attrs. Player ids are filtered to the same `team_id` defensively, so
  it's never possible to attach players from another team to a preset.
  """
  def create_line_preset(attrs) do
    {player_ids, attrs} = pop_player_ids(attrs)

    %LinePreset{}
    |> LinePreset.changeset(attrs)
    |> put_players_assoc(player_ids)
    |> Repo.insert()
  end

  @doc """
  Updates a line_preset, replacing its player set when `:player_ids`
  (or `"player_ids"`) is present in attrs. Replacement (not append) is
  guaranteed by the `on_replace: :delete` declaration on the schema's
  `many_to_many :players`.
  """
  def update_line_preset(%LinePreset{} = line_preset, attrs) do
    {player_ids, attrs} = pop_player_ids(attrs)

    line_preset = Repo.preload(line_preset, :players)

    line_preset
    |> LinePreset.changeset(attrs)
    |> put_players_assoc(player_ids, line_preset.team_id)
    |> Repo.update()
  end

  @doc """
  Deletes a line_preset. The join-table rows are removed by the
  `on_delete: :delete_all` constraint on `line_preset_players`.
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

  # ----- private helpers for line_preset player association -----

  defp pop_player_ids(attrs) when is_map(attrs) do
    case Map.pop(attrs, :player_ids, :__missing__) do
      {:__missing__, attrs} ->
        case Map.pop(attrs, "player_ids", :__missing__) do
          {:__missing__, attrs} -> {nil, attrs}
          {ids, attrs} -> {ids, attrs}
        end

      {ids, attrs} ->
        {ids, attrs}
    end
  end

  # No player_ids supplied — leave the changeset alone (creates with
  # no players for new records; preserves existing players on update).
  defp put_players_assoc(changeset, nil), do: changeset

  defp put_players_assoc(changeset, player_ids) when is_list(player_ids) do
    team_id = Ecto.Changeset.get_field(changeset, :team_id)
    put_players_assoc(changeset, player_ids, team_id)
  end

  defp put_players_assoc(changeset, nil, _team_id), do: changeset

  defp put_players_assoc(changeset, player_ids, team_id) when is_list(player_ids) do
    players = load_team_scoped_players(player_ids, team_id)
    Ecto.Changeset.put_assoc(changeset, :players, players)
  end

  defp load_team_scoped_players([], _team_id), do: []
  defp load_team_scoped_players(_ids, nil), do: []

  defp load_team_scoped_players(ids, team_id) do
    Player
    |> where([p], p.team_id == ^team_id and p.id in ^ids)
    |> Repo.all()
  end
end
