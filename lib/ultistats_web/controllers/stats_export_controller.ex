defmodule UltistatsWeb.StatsExportController do
  @moduledoc """
  CSV exports for the per-game summary and the team leaderboard. The
  rows mirror what the on-screen tables produce — the `?sort=` and
  `?dir=` params let a download reflect the user's current view.
  """
  use UltistatsWeb, :controller

  alias Ultistats.Accounts.User
  alias Ultistats.{Games, Teams}
  alias UltistatsWeb.Components.StatsTable

  @csv_columns [
    {:jersey, "#"},
    {:name, "Player"} | StatsTable.stat_headers() |> Enum.map(fn {k, _, title} -> {k, title} end)
  ]

  def game_summary(conn, %{"id" => game_id} = params) do
    game = Games.get_game!(game_id)
    user = conn.assigns.current_scope.user

    if Teams.user_member_of?(user, game.team_id) do
      summary = Games.summary_for_game(game)
      {sort_by, sort_dir} = parse_sort(params)
      sorted = StatsTable.sort_players(summary.players, sort_by, sort_dir)

      filename = "summary-vs-#{slugify(game.opponent_name)}-#{Date.utc_today()}.csv"
      send_csv(conn, filename, sorted)
    else
      conn
      |> put_flash(:error, "You don't have permission to view that game.")
      |> redirect(to: ~p"/games")
    end
  end

  def team_leaderboard(conn, %{"id" => team_id} = params) do
    user = conn.assigns.current_scope.user
    team = Teams.get_team!(team_id)

    if Teams.user_member_of?(user, team) do
      leaderboard = Games.leaderboard_for_team(team)
      {sort_by, sort_dir} = parse_sort(params)
      sorted = StatsTable.sort_players(leaderboard, sort_by, sort_dir)

      filename = "leaderboard-#{slugify(team.name)}-#{Date.utc_today()}.csv"
      send_csv(conn, filename, sorted)
    else
      conn
      |> put_flash(:error, "You don't have permission to view that team.")
      |> redirect(to: ~p"/dashboard")
    end
  end

  defp send_csv(conn, filename, rows) do
    body = build_csv(rows)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, body)
  end

  defp build_csv(rows) do
    header_row = @csv_columns |> Enum.map(fn {_k, title} -> title end) |> csv_line()

    body_rows =
      rows
      |> Enum.map(fn row ->
        @csv_columns
        |> Enum.map(fn {key, _} -> cell(row, key) end)
        |> csv_line()
      end)

    IO.iodata_to_binary([header_row | body_rows])
  end

  defp cell(row, :jersey), do: Teams.resolved_jersey_number(row.membership) || ""
  defp cell(row, :name), do: User.display_name(row.user)
  defp cell(row, key), do: Map.get(row, key) |> to_string()

  defp csv_line(values) do
    [Enum.map_join(values, ",", &escape/1), "\r\n"]
  end

  # RFC 4180: wrap in quotes when the value contains comma, quote, CR, or LF;
  # double-up internal quotes.
  defp escape(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\r", "\n"]) do
      ["\"", String.replace(value, "\"", "\"\""), "\""]
    else
      value
    end
  end

  defp escape(value), do: escape(to_string(value))

  defp parse_sort(params) do
    sort_by =
      with raw when is_binary(raw) <- params["sort"],
           {:ok, atom} <- safe_atom(raw),
           true <- atom in StatsTable.sortable_keys() do
        atom
      else
        _ -> :goals
      end

    sort_dir =
      case params["dir"] do
        "asc" -> :asc
        "desc" -> :desc
        _ -> default_dir_for(sort_by)
      end

    {sort_by, sort_dir}
  end

  defp default_dir_for(:name), do: :asc
  defp default_dir_for(:jersey), do: :asc
  defp default_dir_for(_), do: :desc

  defp safe_atom(str) do
    {:ok, String.to_existing_atom(str)}
  rescue
    ArgumentError -> :error
  end

  defp slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "untitled"
      s -> s
    end
  end

  defp slugify(_), do: "untitled"
end
