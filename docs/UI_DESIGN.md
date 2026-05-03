# UI_DESIGN — Ultistats UI design language

This is the contract. Every LiveView module, HEEx template, and Tailwind class added to this project must conform. The `liveview-ui-specialist` sub-agent reads this on every invocation and enforces it.

If a rule here conflicts with what's natural in code, **fix the code, not the rule** — open an issue or update this doc deliberately. Drift kills the design language.

## Principles

1. **Usability first.** A tracker on a sideline at midday with sun in their eyes and gloves on must be able to record a goal in two confident taps. Latency, polish, and aesthetic refinement come *after* basic usability.
2. **Mobile-first, real device first.** Design at 375px viewport (iPhone SE / 13 mini width). iPad (≥768px) gets the same column flow with extra breathing room until ≥1024px when a sidebar may appear.
3. **One-handed thumb-reach.** Primary in-game actions live in a sticky bottom bar. The top half of the screen is for *information* (score, who's on); the bottom half is for *action*.
4. **Sun-readable.** High contrast, no thin gray-on-white. WCAG AA contrast minimum on all text.
5. **Latency over polish.** Every tap must give feedback in <100ms. Skip animations that delay the response.

## Layout

- **Single column** on phone widths.
- **iPad (≥1024px)** may add a sidebar for the timeline view; the live game screen stays single-column.
- **Sticky top header** (~56px tall): score readout left, game-info right, connectivity banner overlays when disconnected.
- **Sticky bottom action bar** (~80px tall) on the live game screen: holds primary action buttons (Goal / Assist / Block / Turn).
- **Center scrolling area** for line picker, current event list, etc.
- **Safe areas:** respect iOS safe-area insets (notch, home indicator) — use `env(safe-area-inset-*)` in CSS.

## Tap targets

- **Minimum 56×56 px** for any in-game action (Goal, Assist, Block, Turn, line preset selection, player chip selection within a point).
- **Minimum 44×44 px** for non-game-flow controls (settings, timeline edit, navigation).
- **Minimum 8 px** spacing between adjacent tap targets. 12 px in the bottom action bar.
- **No double-tap** for primary actions — single-tap with confirmation modal for destructive operations only.

## Typography

- **Font stack:** `ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`. System font, no web-font load latency.
- **Base size:** 16px. Never go below 14px for readable text.
- **Numerals in stat displays** use `font-variant-numeric: tabular-nums` so digits don't reflow as the score changes.
- **Score readout:** 32–48px, weight 700 (bold).
- **Action button labels:** 18–20px, weight 600.
- **Body / list items:** 16px, weight 400–500.
- **Captions / timestamps:** 14px, weight 400, low contrast acceptable here.

## Color

- **Light theme + true-dark theme.** Both must be supported. System preference picks the default; user can override.
- **Accent color:** TBD — pick during the first UI ticket. Use a single accent across the app; do not introduce a second.
- **Functional colors:**
  - Success / goal: green family
  - Warning / ratio violation: amber family
  - Destructive / delete: red family
  - Info / banner: blue family
- **Contrast:** WCAG AA minimum (4.5:1 for body text, 3:1 for large text and UI components).
- **Color is never the only signal.** A ratio warning is amber *and* labeled "Ratio mismatch". A turn event is colored *and* iconed.

## Components

We standardize a small set of HEEx function components in `lib/ultistats_web/components/ui_components.ex`. Every UI piece composes these — do not hand-roll one-off styled `<div>`s when a component fits.

- **`<.action_button>`** — primary in-game action (Goal / Block / Turn / Assist). Props: `kind` (`:goal` | `:assist` | `:block` | `:turn`), `phx-click`, `disabled`. Renders at min 56×56, full-width-share in the bottom bar, with the kind's functional color and an icon.
- **`<.player_chip>`** — tappable player identity. Props: `player`, `selected?`, `phx-click`. Shows jersey number + name. Used in line picker and event-attribution flows. Min 44px height.
- **`<.score_readout>`** — score display. Props: `our_score`, `their_score`. Tabular-nums, large weight, accent on whichever team just scored most recently.
- **`<.line_preset_card>`** — selectable line preset before a point. Props: `preset`, `selected?`, `gender_warning?`. Shows preset name, player count, ratio warning badge if applicable.
- **`<.timeline_event>`** — a row in the timeline view. Props: `event`, `editable?`. Shows event type icon, player, timestamp; tap opens edit/delete actions.

When you reach for a sixth component type, first ask: can I compose existing ones, or does this genuinely need a new primitive? If new, add it here in a PR that updates this doc.

## State + feedback

- **Tap feedback within 100ms.** Use Tailwind's `active:` variants for immediate visual press feedback even before the LiveView round-trip completes.
- **Destructive confirmations.** Deleting an event from the timeline shows a confirm step (modal or inline confirm row). No silent destruction.
- **Loading state:** prefer skeletons (gray placeholder shapes) to spinners. Spinners only for actions <500ms expected.
- **Empty state:** every list view (no players yet, no games yet, no events yet) has a designed empty state with a clear next action.
- **Connectivity loss:** sticky red/amber banner at the top: "Reconnecting…" — and *all* in-game action buttons disable while disconnected. This is the most important state to get right; tracker must never tap-into-the-void.

## Accessibility

- **Semantic HEEx.** `<button>` for actions, `<a>` for navigation, headings in document order. Avoid clickable `<div>`s.
- **Labels.** Every interactive element has an accessible name (`aria-label` or visible text). Icon-only buttons require `aria-label`.
- **Focus rings preserved.** Don't `outline: none` without replacing it. Tailwind's `focus-visible:` variants are the default.
- **Color contrast** as above (WCAG AA minimum).
- **No information by color alone** (icons, labels, or shape supplement color).
- **Reduced motion:** respect `prefers-reduced-motion` — disable transitions for users who request it.

## Anti-patterns (do not do)

- Modals stacked on modals, or modals to confirm trivial actions.
- Swipe gestures as the *only* way to do a primary action (poor discoverability for new tracker users).
- Tap targets below 44×44 px anywhere user-tappable.
- Color-only state (e.g. red text with no label).
- Spinners for sub-second operations.
- Hand-rolled `<div class="bg-red-500 p-4 ...">` when an existing component fits.
- Importing a web font (latency, blocks rendering).
- `position: fixed` headers/footers without safe-area-inset awareness on iOS.
