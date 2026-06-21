#!/usr/bin/env bash
# Validate a real adapter binary end-to-end (announce alongside HTTP + goodbye) against the live
# observer pipeline, via the generalized presence harness (--go driver).
#
# Usage: adapter-smoke.sh [adapter-name]      # default: agentic. e.g. openai-compat
#   Resolves repo cofiswarm-adapter-<name>, cmd cmd/cofiswarm-adapter-<name>, component
#   adapter-<name>, and config test/smoke/fixtures/adapter-<name>.yaml.
#
# Doubles as the template for validating any other Go service: see also mode-relay-smoke.sh, or
# call observer-presence-smoke.sh --go <repo> <cmd> <component_id> -- <args> directly.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:-agentic}"
FIXTURE="$HERE/fixtures/adapter-${NAME}.yaml"
[ -f "$FIXTURE" ] || { echo "no fixture for adapter '$NAME' at $FIXTURE" >&2; exit 1; }
exec "$HERE/observer-presence-smoke.sh" \
  --go "cofiswarm-adapter-${NAME}" "cmd/cofiswarm-adapter-${NAME}" "adapter-${NAME}" \
  -- -config "$FIXTURE"
