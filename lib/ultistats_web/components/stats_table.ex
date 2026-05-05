defmodule UltistatsWeb.Components.StatsTable do
  @moduledoc """
  Sortable, responsive per-player stats table — shared by the in-game
  summary and the dashboard leaderboard.

  Mobile (<sm): only `#`, Player, and the active stat column render. A
  chip strip above the table picks which stat is active and drives sort.
  Desktop (sm+): all stat columns render, and clicking a header sorts.

  The component is rendering-only — the consumer LiveView owns the
  `sort_by` / `sort_dir` assigns and the `phx-click="sort"` handler.
  Use `sort_players/3` and `next_sort/3` to keep the handler small.
  """
  use Phoenix.Component
  import UltistatsWeb.CoreComponents, only: [icon: 1]

  alias Ultistats.Accounts.User
  alias Ultistats.Teams

  @stat_headers [
    {:goals, "G", "Goals"},
    {:assists, "A", "Assists"},
    {:catches, "C", "Catches"},
    {:drops, "D", "Drops"},
    {:throwaways, "TA", "Throwaways"},
    {:blocks, "B", "Blocks"},
    {:points_played, "Pts", "Points played"}
  ]

  @mobile_chips [:goals, :assists, :blocks, :points_played]
  @stat_keys Enum.map(@stat_headers, &elem(&1, 0))
  @sortable_keys [:jersey, :name | @stat_keys]

  def stat_headers, do: @stat_headers
  def stat_keys, do: @stat_keys
  def sortable_keys, do: @sortable_keys

  attr :players, :list, required: true
  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true
  attr :id, :string, default: nil

  def stats_table(assigns) do
    assigns =
      assigns
      |> assign(:active_stat_key, active_stat_key(assigns.sort_by))
      |> assign(:stat_headers, @stat_headers)
      |> assign(:mobile_chips, @mobile_chips)

    ~H"""
    <div class="flex flex-col gap-3">
      <div
        class="sm:hidden flex flex-wrap gap-2"
        role="group"
        aria-label="Sort by stat"
      >
        <button
          :for={key <- @mobile_chips}
          type="button"
          phx-click="sort"
          phx-value-key={key}
          aria-pressed={to_string(@sort_by == key)}
          class={chip_classes(@sort_by == key)}
        >
          {chip_label(key)}
          <.icon
            :if={@sort_by == key}
            name={sort_arrow_icon(@sort_dir)}
            class="size-3"
          />
        </button>
      </div>

      <div class="overflow-x-auto rounded-lg border border-base-200">
        <table id={@id} class="w-full border-collapse text-left text-sm">
          <thead class="border-b border-base-200 bg-base-200/50 text-base-content/70 font-semibold">
            <tr>
              <.sort_th
                key={:jersey}
                label="#"
                sort_by={@sort_by}
                sort_dir={@sort_dir}
                class="w-12 text-right tabular-nums"
              />
              <.sort_th
                key={:name}
                label="Player"
                sort_by={@sort_by}
                sort_dir={@sort_dir}
              />
              <th
                scope="col"
                class="sm:hidden p-3 text-right tabular-nums whitespace-nowrap"
                aria-sort={aria_sort(@active_stat_key, @sort_by, @sort_dir)}
              >
                {stat_label(@active_stat_key)}
              </th>
              <.sort_th
                :for={{key, label, title} <- @stat_headers}
                key={key}
                label={label}
                title={title}
                sort_by={@sort_by}
                sort_dir={@sort_dir}
                class="hidden sm:table-cell text-right tabular-nums"
              />
            </tr>
          </thead>
          <tbody class="text-base-content">
            <tr
              :for={row <- @players}
              class={[
                "border-b border-base-200 last:border-b-0",
                row_zero?(row) && "text-base-content/60"
              ]}
            >
              <td class="p-3 text-right tabular-nums font-semibold">
                {jersey_label(Teams.resolved_jersey_number(row.membership))}
              </td>
              <td class="p-3">
                <span class="font-medium">{User.display_name(row.user)}</span>
              </td>
              <td class="sm:hidden p-3 text-right tabular-nums">
                {Map.get(row, @active_stat_key)}
              </td>
              <td
                :for={{key, _label, _title} <- @stat_headers}
                class="hidden sm:table-cell p-3 text-right tabular-nums"
              >
                {Map.get(row, key)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <dl
        class="flex flex-wrap gap-x-3 gap-y-1 text-xs text-base-content/60 px-1"
        aria-label="Column key"
      >
        <div :for={{_key, abbr, title} <- @stat_headers} class="inline-flex items-baseline gap-1">
          <dt class="font-semibold text-base-content/80">{abbr}</dt>
          <dd>{title}</dd>
        </div>
      </dl>
    </div>
    """
  end

  attr :key, :atom, required: true
  attr :label, :string, required: true
  attr :title, :string, default: nil
  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true
  attr :class, :string, default: nil

  def sort_th(assigns) do
    ~H"""
    <th
      scope="col"
      class={["p-3", @class]}
      aria-sort={aria_sort(@key, @sort_by, @sort_dir)}
    >
      <button
        type="button"
        phx-click="sort"
        phx-value-key={@key}
        class="inline-flex items-center gap-1 hover:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary rounded"
      >
        <abbr :if={@title} title={@title} class="no-underline">{@label}</abbr>
        <span :if={is_nil(@title)}>{@label}</span>
        <.icon
          :if={@sort_by == @key}
          name={sort_arrow_icon(@sort_dir)}
          class="size-3"
        />
      </button>
    </th>
    """
  end

  attr :path, :string, required: true
  attr :label, :string, default: "Download CSV"

  def csv_link(assigns) do
    ~H"""
    <.link
      href={@path}
      class="inline-flex items-center gap-1 min-h-11 px-2 text-sm font-medium text-base-content/80 active:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary rounded-md"
    >
      <.icon name="hero-arrow-down-tray" class="size-4" />
      <span>{@label}</span>
    </.link>
    """
  end

  ## --- public sort helpers ---

  @doc "Apply sort_by/dir to player rows. Name is the stable tiebreaker."
  def sort_players(players, sort_by, sort_dir) do
    players
    |> Enum.sort_by(&(&1.user |> User.display_name() |> String.downcase()), :asc)
    |> Enum.sort_by(&sort_key(&1, sort_by), sort_dir)
  end

  @doc """
  Compute the next `{sort_by, sort_dir}` given a click on `key`.

  Same key toggles direction; new key resets to that key's default direction
  (`:desc` for stats, `:asc` for jersey/name).
  """
  def next_sort(key, current_by, current_dir) do
    if key == current_by do
      {key, toggle_dir(current_dir)}
    else
      {key, default_dir(key)}
    end
  end

  ## --- private ---

  defp sort_key(row, :name), do: row.user |> User.display_name() |> String.downcase()

  defp sort_key(row, :jersey) do
    case Teams.resolved_jersey_number(row.membership) do
      nil ->
        -1

      "" ->
        -1

      n ->
        case Integer.parse(n) do
          {i, _} -> i
          :error -> -1
        end
    end
  end

  defp sort_key(row, key) when key in @stat_keys, do: Map.get(row, key)

  defp default_dir(:name), do: :asc
  defp default_dir(:jersey), do: :asc
  defp default_dir(_), do: :desc

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp sort_arrow_icon(:asc), do: "hero-arrow-up-mini"
  defp sort_arrow_icon(:desc), do: "hero-arrow-down-mini"

  defp aria_sort(key, sort_by, dir) when key == sort_by do
    case dir do
      :asc -> "ascending"
      :desc -> "descending"
    end
  end

  defp aria_sort(_, _, _), do: "none"

  defp active_stat_key(key) when key in @stat_keys, do: key
  defp active_stat_key(_), do: :goals

  defp stat_label(key) do
    {_, label, _} = Enum.find(@stat_headers, fn {k, _, _} -> k == key end)
    label
  end

  defp chip_label(key), do: stat_label(key)

  defp chip_classes(true) do
    [
      "inline-flex items-center gap-1 min-h-11 px-3 rounded-full text-sm font-semibold",
      "bg-primary text-primary-content",
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    ]
  end

  defp chip_classes(false) do
    [
      "inline-flex items-center gap-1 min-h-11 px-3 rounded-full text-sm font-medium",
      "bg-base-200 text-base-content/80 active:bg-base-300",
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    ]
  end

  defp jersey_label(nil), do: "—"
  defp jersey_label(""), do: "—"
  defp jersey_label(n) when is_binary(n), do: n

  defp row_zero?(row) do
    row.goals == 0 and row.assists == 0 and row.catches == 0 and row.drops == 0 and
      row.throwaways == 0 and row.blocks == 0 and row.points_played == 0
  end
end
