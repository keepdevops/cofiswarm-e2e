#!/usr/bin/env bash
# Ready-to-run example of the --go driver: validate the real mode-cascade relay binary
# end-to-end (announce alongside HTTP + goodbye) against the live observer pipeline.
#
# Doubles as the template for validating any other Go service: copy this, swap the repo,
# cmd package, component_id, and run args.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
exec "$HERE/observer-presence-smoke.sh" \
  --go cofiswarm-mode-cascade cmd/cofiswarm-mode-cascade mode-cascade \
  -- -config "$HERE/fixtures/mode-cascade.yaml"
