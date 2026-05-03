defmodule UltistatsWeb.GameLive.Summary do
  @moduledoc """
  Post-game (and mid-game) summary view — final score plus per-player
  tallies for *this game only* (`docs/MVP_SPEC.md` step 6).

  No cross-game aggregation in MVP. The summary recomputes off the
  same soft-deleted-events read path as the timeline, so editing the
  timeline immediately changes what shows up here on the next mount.
  """
  use UltistatsWeb, :live_view

  alias Ultistats.Accounts.User
  alias Ultistats.{Games, Teams}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game = Games.get_game!(id)
    user = socket.assigns.current_scope.user

    if not Teams.user_member_of?(user, game.team_id) do
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to view that game.")
       |> push_navigate(to: ~p"/games")}
    else
      summary = Games.summary_for_game(game)

      {:ok,
       socket
       |> assign(:page_title, "Summary · vs #{game.opponent_name}")
       |> assign(:game, game)
       |> assign(:summary, summary)}
    end
  end

  ## ---------------------------------------------------------------------
  ## render
  ## ---------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex flex-col gap-6 pb-safe">
        <.summary_header game={@game} score={@summary.score} />

        <section aria-label="Per-player tallies" class="space-y-2">
          <div class="flex items-baseline justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Per-player tallies
            </h2>
            <span class="text-xs text-base-content/60 tabular-nums">
              {length(@summary.players)} players
            </span>
          </div>

          <%= if @summary.players == [] do %>
            <.empty_state game={@game} />
          <% else %>
            <.tally_table players={@summary.players} />
          <% end %>
        </section>

        <.summary_footer game={@game} />
      </div>
    </Layouts.app>
    """
  end

  ## ---------------------------------------------------------------------
  ## sub-renderers
  ## ---------------------------------------------------------------------

  attr :game, :map, required: true
  attr :score, :map, required: true

  defp summary_header(assigns) do
    ~H"""
    <div class="sticky top-0 z-20 -mx-4 px-4 pt-safe bg-base-100/95 backdrop-blur border-b border-base-200">
      <div class="py-3 space-y-3">
        <.link
          navigate={~p"/games/#{@game.id}"}
          class="inline-flex items-center gap-1 min-h-11 text-sm font-medium text-base-content/80 active:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary rounded-md"
        >
          <.icon name="hero-arrow-left" class="size-4" />
          <span>Back to game</span>
        </.link>

        <div class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1 min-w-0">
            <h1 class="text-lg font-semibold truncate">
              Summary <span class="text-base-content/70 font-normal">· vs {@game.opponent_name}</span>
            </h1>
            <p class="text-xs text-base-content/70">
              {format_subtitle(@game)}
            </p>
          </div>
          <.status_pill status={@game.status} />
        </div>

        <.score_readout our_score={@score.ours} their_score={@score.theirs} />
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_pill(assigns) do
    assigns = assign(assigns, :meta, status_pill_meta(assigns.status))

    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 shrink-0 rounded-full px-2 py-1",
        "text-xs font-semibold uppercase tracking-wide",
        @meta.classes
      ]}
      role="status"
      aria-label={"Game status: #{@meta.label}"}
    >
      <.icon name={@meta.icon} class="size-3.5" />
      {@meta.label}
    </span>
    """
  end

  defp status_pill_meta(:finished),
    do: %{
      label: "Final",
      icon: "hero-check-circle",
      classes: "bg-success/15 text-success"
    }

  defp status_pill_meta(:in_progress),
    do: %{
      label: "In progress",
      icon: "hero-clock",
      classes: "bg-info/15 text-info"
    }

  defp status_pill_meta(:abandoned),
    do: %{
      label: "Abandoned",
      icon: "hero-x-circle",
      classes: "bg-base-200 text-base-content/70"
    }

  defp status_pill_meta(_),
    do: %{
      label: "Unknown",
      icon: "hero-question-mark-circle",
      classes: "bg-base-200 text-base-content/70"
    }

  attr :players, :list, required: true

  defp tally_table(assigns) do
    ~H"""
    <%!--
      375px viewport: the table can horizontal-scroll if the names get
      long. We don't sticky any columns — the score and stats are the
      important data, and the chip-style player labels remain readable
      at narrow widths.
    --%>
    <div class="overflow-x-auto rounded-lg border border-base-200">
      <table class="w-full border-collapse text-left text-sm">
        <thead class="border-b border-base-200 bg-base-200/50 text-base-content/70 font-semibold">
          <tr>
            <th scope="col" class="p-3 w-12 text-right tabular-nums">#</th>
            <th scope="col" class="p-3">Player</th>
            <th scope="col" class="p-3 text-right tabular-nums" title="Goals">
              <abbr title="Goals" class="no-underline">G</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums" title="Assists">
              <abbr title="Assists" class="no-underline">A</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums" title="Catches">
              <abbr title="Catches" class="no-underline">C</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums" title="Drops">
              <abbr title="Drops" class="no-underline">D</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums" title="Throwaways">
              <abbr title="Throwaways" class="no-underline">TA</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums" title="Blocks">
              <abbr title="Blocks" class="no-underline">B</abbr>
            </th>
            <th scope="col" class="p-3 text-right tabular-nums whitespace-nowrap">
              Pts played
            </th>
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
            <td class="p-3 text-right tabular-nums">{row.goals}</td>
            <td class="p-3 text-right tabular-nums">{row.assists}</td>
            <td class="p-3 text-right tabular-nums">{row.catches}</td>
            <td class="p-3 text-right tabular-nums">{row.drops}</td>
            <td class="p-3 text-right tabular-nums">{row.throwaways}</td>
            <td class="p-3 text-right tabular-nums">{row.blocks}</td>
            <td class="p-3 text-right tabular-nums">{row.points_played}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :game, :map, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="rounded-lg border-2 border-dashed border-base-300 p-6 text-center">
      <.icon name="hero-users" class="size-8 text-base-content/40 mx-auto mb-2" />
      <p class="text-base font-medium">No players on this team yet</p>
      <p class="text-sm text-base-content/70 mt-1">
        Add players to the team's roster to see per-player tallies here.
      </p>
      <div class="mt-4">
        <.link
          navigate={~p"/teams/#{@game.team_id}"}
          class="inline-flex items-center gap-2 min-h-11 px-4 rounded-lg bg-primary text-primary-content font-semibold active:bg-primary/80 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-arrow-right" class="size-4" /> Manage team
        </.link>
      </div>
    </div>
    """
  end

  attr :game, :map, required: true

  defp summary_footer(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3">
      <.link
        navigate={~p"/games/#{@game.id}"}
        class="inline-flex items-center gap-2 min-h-11 px-4 rounded-lg border-2 border-base-300 text-base font-semibold bg-base-100 text-base-content active:bg-base-200 transition-colors motion-reduce:transition-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Back to game
      </.link>
      <.link
        :if={@game.status == :in_progress}
        navigate={~p"/games/#{@game.id}"}
        class="inline-flex items-center gap-2 min-h-11 px-4 rounded-lg bg-primary text-primary-content text-base font-semibold active:bg-primary/80 transition-colors motion-reduce:transition-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <.icon name="hero-play" class="size-4" /> Continue tracking
      </.link>
    </div>
    """
  end

  ## ---------------------------------------------------------------------
  ## helpers
  ## ---------------------------------------------------------------------

  defp row_zero?(row) do
    row.goals == 0 and row.assists == 0 and row.catches == 0 and row.drops == 0 and
      row.throwaways == 0 and row.blocks == 0 and row.points_played == 0
  end

  defp jersey_label(nil), do: "—"
  defp jersey_label(""), do: "—"
  defp jersey_label(n) when is_binary(n), do: n

  defp format_subtitle(%{format: format} = game) do
    base = humanize_format(format)

    case {game.status, game.ended_at} do
      {:in_progress, _} -> "#{base} · In progress"
      {_, %DateTime{} = dt} -> "#{base} · Ended #{Calendar.strftime(dt, "%b %-d, %H:%M")}"
      _ -> base
    end
  end

  defp humanize_format(:usau_standard), do: "USAU standard"
  defp humanize_format(other), do: to_string(other)
end
