# MVP_SPEC — Ultistats MVP 1

Single-game live stat tracking for ultimate frisbee. The whole MVP is one tracker, one device, one game at a time, always online.

## User personas

**Sideline tracker** — one human, on a sideline or bench, tapping events on their phone or an iPad in a mobile browser. Conditions: outdoor sun, possibly wearing gloves, possibly distracted by the game itself. Optimizes for speed and minimum cognitive load per tap.

(No coach view, no player self-tracking, no spectator view in MVP 1.)

## End-to-end happy-path flow

1. **Team & roster setup** (one-time per team)
   - Create a team (name).
   - Add players: name, jersey number, gender role (`:female_matching` / `:male_matching` — USAU FMP/MMP).
   - Edit/remove players as the roster changes.

2. **Line presets** (one-time per team, editable any time)
   - Create named line presets (e.g. "O-line A", "D-line zone", "Mixed sub").
   - Each preset selects a subset of the team's roster.

3. **Start a game**
   - Pick our team, type opponent name (free-text — opposing team is not tracked as an entity in MVP).
   - Pick who pulls first.
   - Game format defaults to USAU standard (hard cap 15, soft cap by time, halftime at 8). Configurability is post-MVP — defaults are not editable in the start-game flow.

4. **Per-point loop**
   - Tracker picks a line preset (or overrides by selecting players ad-hoc for this point).
   - If next-line gender ratio violates the prevailing-gender rule for the upcoming point, show a non-blocking warning before committing the line.
   - During the point, tap one of:
     - **Goal** → pick scorer → point ends, score increments.
     - **Assist** → pick assister (recorded against the goal that just happened or about to happen — UX detail in `docs/DESIGN.md`).
     - **Block** → pick blocker (optional event, does not end the point).
     - **Turn** → pick turner (optional event, does not end the point unless followed by goal).
   - Confirm point-end on goal so accidental taps don't advance the game.

5. **Game lifecycle markers**
   - At score 8 (halftime in a game-to-15), show a halftime banner.
   - At hard cap 15 by either team, end the game automatically.
   - Soft cap (time-based) is a TODO — see open questions; not blocking MVP shipping.

6. **Game summary**
   - Final score.
   - Per-player tallies for *this game only*: goals, assists, blocks, turns, points played.
   - No cross-game aggregation.

7. **Mistake handling — timeline edit**
   - At any time during the game, the tracker can open a timeline view of all events for the current game (in chronological order, grouped by point).
   - Tap any event to edit (change player, change type, etc.) or delete it (soft-delete; ordering and score recalculate).
   - This is the primary mistake-recovery UX. There's no separate "undo last action" — the timeline *is* the history.

## Feature list (in scope)

- Team CRUD.
- Player CRUD (within a team).
- Line preset CRUD.
- Single-game lifecycle (create → play → summary).
- Event capture: goal, assist, block, turn.
- Gender ratio rule: enforce/warn on next-line composition.
- USAU cap/halftime markers (halftime banner, hard cap auto-end).
- Timeline view with edit and soft-delete of events.
- Connectivity-loss UX: header banner + disabled in-game action buttons when the LiveView socket disconnects.

## Out of scope (MVP 1)

- Multi-tracker / multi-device sync on the same game.
- Season / league / tournament management.
- Cross-game stats and aggregation views.
- Charts and visualizations.
- Opposing-team player tracking (opponent is just a name in MVP).
- Advanced throw types, throw-by-throw tracking, possessions count.
- Native mobile apps.
- **Offline support / PWA install / service worker** — explicitly deferred. MVP assumes connectivity.
- Auth, multi-user accounts (single local-trusted user assumed for MVP).

## Acceptance criteria

The MVP ships when all of the following are true:

1. A new user can create a team, add 14 players, and define two line presets in under three minutes on a phone.
2. From game-start to game-summary, the tracker can record a complete 15–0 game without leaving the live game screen and without page reloads.
3. Recording a goal increments the displayed score within 100 ms of tapping confirm.
4. Deleting any event from the timeline immediately recomputes the displayed score and per-player tallies.
5. A line whose gender composition violates the prevailing-gender rule produces a visible warning before the point begins (but does not block — this is informational).
6. At score 8, a halftime banner appears; it can be dismissed and does not interfere with continued play.
7. When the LiveView socket disconnects, all in-game action buttons disable and a "reconnecting…" banner appears at the top of the screen; on reconnect, buttons re-enable and no events are duplicated or lost.
8. The full happy-path flow has integration test coverage (LiveView tests using `Phoenix.LiveViewTest`) hitting a real Ecto sandbox — no mocked DB.
