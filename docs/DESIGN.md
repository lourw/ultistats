# DESIGN — Architecture & approach

How we build what `MVP_SPEC.md` describes.

## Stack decisions

- **Phoenix LiveView** for the entire UI. Server-driven; no JS-driven SPA. Components are colocated `Phoenix.Component`s where reuse is meaningful (per `docs/UI_DESIGN.md`).
- **Ecto + Postgres** for every environment (dev, test, prod). Dev/test run a containerized Postgres via `docker-compose.yml` and `bin/db`; prod runs against Supabase.
  - Configured in `config/dev.exs`, `config/test.exs`, `config/runtime.exs`.
  - Each git worktree gets its own Postgres container on a port derived from the worktree path (written to `.env` by `bin/db`), so multiple worktrees coexist without 5432 collisions.
- **Tailwind + ESBuild** via Phoenix's standard installer.
- **No PWA, no service worker, no IndexedDB.** Always-online assumption (see below).

## Always-online assumption

MVP assumes the device has connectivity to the server for the entire game. There is no offline mode, no client-authoritative event log, no client-side IDs.

**Connectivity-loss UX (must implement):**
- Detect LiveView socket disconnect on the client (Phoenix LiveView fires `phx:page-loading-start` / connection events).
- When disconnected: show a sticky banner at the top of the screen ("Reconnecting…"), and disable all in-game action buttons (Catch, Drop, Goal, Throwaway, Stall, Block, line-preset selection). This prevents the tracker from tapping into the void and assuming events were recorded.
- When reconnected: clear the banner, re-enable buttons. LiveView's normal reconnect flow re-fetches state from the server, so no duplication concerns.

**Future enhancement (post-MVP):** offline-capable mode would require a service worker, local event store, and reconciliation. Explicitly out of scope.

## Data model sketch

Names tentative — confirm during the first feature ticket. All tables have `inserted_at` / `updated_at`.

```
teams
  id (pk)
  name (string, not null)

players
  id (pk)
  team_id (fk → teams)
  name (string, not null)
  jersey_number (string, nullable — string not int because some leagues allow "00")
  gender_role (enum: :female_matching | :male_matching — USAU FMP/MMP)

line_presets
  id (pk)
  team_id (fk → teams)
  name (string, not null)

line_preset_players
  line_preset_id (fk → line_presets)
  player_id (fk → players)
  -- composite primary key (line_preset_id, player_id)

games
  id (pk)
  team_id (fk → teams)               -- our team
  opponent_name (string)             -- free text; no opposing-team entity in MVP
  format (enum: "usau_standard")     -- single value in MVP, enum so we can extend
  status (enum: "in_progress" | "finished" | "abandoned")
  started_at (utc_datetime)
  ended_at (utc_datetime, nullable)
  first_pull (enum: "ours" | "theirs")

points
  id (pk)
  game_id (fk → games)
  sequence (integer, not null)       -- 1, 2, 3 …; unique per game
  scoring_team (enum: "ours" | "theirs", nullable until point ends)
  our_line_snapshot (jsonb→:map)     -- frozen list of player_ids on the line for this point
                                     -- snapshotted because a player removed mid-game must
                                     -- still appear in earlier point histories

events
  id (pk)
  point_id (fk → points)
  sequence (integer, not null)       -- ordering within point
  type (enum: pull | catch | throwaway | drop | stall | goal
              | block | opponent_turnover | opponent_goal
              | pick | foul)
  passer_id (fk → players, nullable)   -- thrower / puller / blocker; nil = "Unknown"
  receiver_id (fk → players, nullable) -- catcher / intended catcher / scorer; nil = "Unknown"
  occurred_at (utc_datetime)
  deleted_at (utc_datetime, nullable) -- soft delete; aggregates filter NULL
```

**Per-type field shape** (enforced in `Event.changeset/2`; both ids always nullable, where `nil` means "Unknown"):

| type | passer_id | receiver_id | possession after |
|---|---|---|---|
| `:pull` | allowed | must be nil | opponent |
| `:catch` | allowed | allowed | us |
| `:throwaway` | allowed | must be nil | opponent |
| `:drop` | allowed | allowed | opponent |
| `:stall` | allowed | must be nil | opponent |
| `:goal` | allowed (assister) | allowed (scorer) | (point ends) |
| `:block` | allowed (blocker) | must be nil | us |
| `:opponent_turnover` | must be nil | must be nil | us |
| `:opponent_goal` | must be nil | must be nil | (point ends) |
| `:pick` | must be nil | must be nil | unchanged |
| `:foul` | must be nil | must be nil | unchanged |

`:assist` is **derived** from a goal's `passer_id` — there is no `:assist` event type. Earlier `:turn` is replaced by the more specific `:throwaway` / `:drop` / `:stall`.

**Key design choices in the data model:**

- **Events are normalized rows, never blobs.** Every per-throw event is one row with `(point_id, type, passer_id, receiver_id)`. Throw completion %, drop counts per receiver, passing chains, etc. are all just SQL aggregates on this table.
- **Possession is event-driven.** `Games.starting_possession/2` gives the start-of-point side; `Enum.reduce` over each point's events flips per the table above. No separate possession state on the DB.
- **`nil` = Unknown** for `passer_id` / `receiver_id` — the tracker can record an event even when they missed who threw or caught it.
- **Soft delete on events** (`deleted_at`) — the timeline edit feature deletes events, but we want an audit trail. All read paths filter `deleted_at IS NULL`.
- **`our_line_snapshot` is denormalized on `points`** — captures who was on the field for that point even if rosters/line-presets change later.
- **No client-side UUIDs.** Server-generated integer ids (or `:binary_id` if Phoenix gen defaults that way).
- **`scoring_team` on `points`** is nullable until the point ends — a point in progress is still a point row.

## Folder layout (target — confirm after Phoenix install)

```
lib/
  ultistats/                  # contexts (business logic)
    teams/                    # Teams context
    games/                    # Games context (game lifecycle, points, events)
    repo.ex
  ultistats_web/              # web layer
    live/
      team_live/              # LiveViews for team management
      game_live/              # LiveViews for game tracking
      timeline_live.ex        # event timeline view
    components/
      core_components.ex      # Phoenix-generated
      ui_components.ex        # our project components per UI_DESIGN.md
priv/
  repo/migrations/
test/
  ultistats/                  # context tests
  ultistats_web/live/         # LiveView integration tests
assets/
  css/, js/, vendor/
```

## Testing strategy

- **ExUnit + Ecto sandbox.** Every test runs in a transaction that's rolled back. No mocked DB — see CLAUDE.md.
- **Context-level tests** for business logic (game state transitions, gender-ratio checks, score recalculation after delete).
- **LiveView integration tests** using `Phoenix.LiveViewTest` for the happy-path user flow (create team → start game → record a goal → delete it → see score change).
- **One fast `mix test`** for the whole suite. Keep tests fast — avoid `async: false` unless required.
- `/check` runs `mix format --check-formatted` → `mix compile --warnings-as-errors` → `mix test`.

## Open questions

- ~~**Gender role values**~~ — resolved: `:female_matching` and `:male_matching` (USAU FMP/MMP terminology), enforced via `Ecto.Enum` at the application layer.
- **Soft-cap timer source** — whose clock drives soft cap? Server time? Tracker-tapped "soft cap reached" button? MVP can ship with a manual button. Resolve before implementing the cap UX.
- **Assist UX detail** — is assist captured *before* tapping goal, or as a follow-up after? Both are common in stat apps. Default: tap goal, then prompted "who threw it?" with a skip option. Confirm during first game-flow ticket.
- **Game ID for URLs** — integer ids are leaky for sharing; consider `:binary_id` from the start to future-proof. Decide before first migration.
- **Phoenix version** — pin during install. Latest stable at time of install.
