# Ultistats

Mobile-first Phoenix LiveView web app for **live in-game ultimate-frisbee stat tracking**. A sideline tracker (one human, one device — phone or iPad in a browser) taps through the events of a single game: pulls, lines, goals/assists/blocks/turns. Always-online assumption — no offline mode in MVP.

## Read these next

The depth lives in `docs/`. Read whichever is relevant before changing things in that area:

- **`docs/MVP_SPEC.md`** — what we're building (user flow, feature list, acceptance criteria, out-of-scope).
- **`docs/DESIGN.md`** — how we're building it (stack, data model, always-online strategy, folder layout, testing).
- **`docs/UI_DESIGN.md`** — UI design language (mobile-first principles, layout, tap targets, typography, components, accessibility). The `liveview-ui-specialist` sub-agent enforces this doc.

## Current state

This is currently a plain `mix new` project. **Phoenix has not been added yet.** When you see no `lib/ultistats_web/`, no `Phoenix` deps in `mix.exs`, and no `priv/repo/migrations/`, that's expected — not broken. Converting to Phoenix is a follow-up task.

## Tech stack (target)

- Elixir ~> 1.18
- Phoenix LiveView (server-driven; no offline / no PWA in MVP)
- Ecto — `Ecto.Adapters.Postgres` for dev/test/prod. Run dev/test Postgres via `bin/db up` (per-worktree container on a path-derived port; see `docker-compose.yml`).
- Tailwind + ESBuild (Phoenix defaults)

## Common commands

Already usable:
- `mix deps.get`
- `mix compile` / `mix compile --warnings-as-errors`
- `mix test` / `mix test path/to/file_test.exs:LINE`
- `mix format` / `mix format --check-formatted`

Phoenix-bound (work after `mix phx.new`):
- `mix phx.server`
- `mix ecto.create`, `mix ecto.migrate`, `mix ecto.gen.migration NAME`
- `mix phx.gen.live`, `mix phx.gen.context`, `mix phx.gen.schema`
- `mix phx.routes`

Run `/check` before commits — formats, compiles with warnings-as-errors, runs tests.

## Domain glossary

- **point** — a single sequence ending when one team scores; resets line.
- **possession** — which team currently has the disc.
- **pull** — opening throw of a point from defending team to receiving team.
- **hold** — receiving team scores the point.
- **break** — defending team scores the point (turnover then conversion).
- **O-line / D-line** — offense/defense lines; rosters specialized per situation.
- **gender ratio rule** — in mixed division, each point sets prevailing-gender ratio (e.g. 4M/3F or 3M/4F).
- **callahan** — interception caught in the opposing endzone, scoring directly.
- **soft cap / hard cap** — time-based caps that change/end the game; complement the score cap.
- **halftime** — at half the score cap (8 in a game-to-15).

## Sub-agents to prefer

Three project sub-agents live in `.claude/agents/`. Delegate to them rather than doing the work in the main session:

- **`elixir-tester`** — runs and parses tests. Use whenever you need test status; do not run `mix test` directly from the main agent.
- **`phoenix-fullstack-dev`** — schemas, migrations, contexts, LiveViews, end-to-end feature implementation. Prefers Phoenix generators (`mix phx.gen.*`) over hand-rolled scaffolding.
- **`liveview-ui-specialist`** — LiveView modules, HEEx templates, Tailwind. Enforces `docs/UI_DESIGN.md`.

Conventions:
- Always run `mix format` before committing.
- Tests hit a real Ecto sandbox — do not mock the database.

## Commits

- Use [Conventional Commits](https://www.conventionalcommits.org/) format: `<type>(<optional scope>): <subject>`.
- Common types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `build`, `ci`, `perf`, `style`.
- Scope is optional but useful: e.g. `feat(games): add point lifecycle`, `fix(ui): correct tap target on action button`.
- Subject is imperative, lowercase, no trailing period: `add team CRUD`, not `Added team CRUD.`.
- **Descriptions (commit body / PR description): one or two sentences, max.** Concise, to the point. State the *why* if non-obvious; skip the *what* (the diff already shows it). No bullet lists, no headers, no test plans in the body for ordinary commits.
