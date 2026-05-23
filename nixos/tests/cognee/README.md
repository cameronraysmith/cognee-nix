# cognee module eval-tier fixtures

This directory holds table-driven fixtures consumed by the eval-tier checks
defined in `dev/checks.nix`.
Each `.nix` file under `eval-fixtures/` is a partial NixOS configuration that
drives `services.cognee` into a specific code path.
A header comment on every fixture records its verdict — either `EVAL_OK`
(the module evaluates cleanly with no failing assertions) or
`EVAL_FAIL contains "<substring>"` (the module must surface a failed
assertion whose message contains the named substring).

The `cognee-module-assertions` check composes each fixture with the cognee
overlay inside a stripped-down NixOS evaluation, collects
`config.assertions`, and tabulates results against the expected verdicts.
The `cognee-module-systemd-shape` check uses the `full-stack-ok` fixture to
materialise `systemd.units."cognee.service".text` and the rendered
`ExecStart` shell script, then asserts on structural hardening properties
(state directory, capability restrictions, credential loading, gunicorn
entry point).
Both checks stay at the evaluation tier — they never build the cognee
package or boot a VM.
