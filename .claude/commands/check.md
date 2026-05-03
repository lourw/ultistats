---
description: Run formatter check, compile with warnings-as-errors, and run the full test suite. Stops on the first failure.
---

Run the project quality gate. Execute these in order, stopping on the first failure and reporting which step failed and the offending output:

1. `mix format --check-formatted` — if this fails, list the files that need formatting and stop. Do **not** auto-format; the user runs `mix format` themselves.
2. `mix compile --warnings-as-errors` — if this fails, show the compile errors/warnings and stop.
3. Delegate to the `elixir-tester` sub-agent to run the test suite. Report its summary verbatim.

If all three pass, output: `check passed — formatted, compiled cleanly, all tests green`.

If any step fails, do **not** continue to the next. Report the failure crisply and stop.
