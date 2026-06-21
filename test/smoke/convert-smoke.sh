#!/usr/bin/env bash
# Validate the real convert binary end-to-end (announce alongside HTTP + goodbye) against the
# live observer pipeline, via the generalized presence harness (--go driver).
#
# Usage: convert-smoke.sh
#   convert needs no config fixture: the driver exports COFISWARM_NATS_URL to enable presence,
#   and we pass -listen to keep the HTTP API off the default port during the test.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
exec "$HERE/observer-presence-smoke.sh" \
  --go "cofiswarm-convert" "cmd/cofiswarm-convert" "convert" \
  -- -listen ":18015"
