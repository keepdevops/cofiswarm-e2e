#!/usr/bin/env bash
# Validate a real mode-relay binary end-to-end (announce alongside HTTP + goodbye) against the
# live observer pipeline, via the generalized presence harness (--go driver).
#
# Usage: mode-relay-smoke.sh [mode-name]      # default: cascade. e.g. flat, pipeline, router
#   Resolves repo cofiswarm-mode-<name>, cmd cmd/cofiswarm-mode-<name>, component mode-<name>,
#   and config test/smoke/fixtures/mode-<name>.yaml.
#
# Doubles as the template for validating any other Go service: see also adapter-smoke.sh, or
# call observer-presence-smoke.sh --go <repo> <cmd> <component_id> -- <args> directly.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:-cascade}"
FIXTURE="$HERE/fixtures/mode-${NAME}.yaml"
[ -f "$FIXTURE" ] || { echo "no fixture for mode '$NAME' at $FIXTURE" >&2; exit 1; }
exec "$HERE/observer-presence-smoke.sh" \
  --go "cofiswarm-mode-${NAME}" "cmd/cofiswarm-mode-${NAME}" "mode-${NAME}" \
  -- -config "$FIXTURE"
