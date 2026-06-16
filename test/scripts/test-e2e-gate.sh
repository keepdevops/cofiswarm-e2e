#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ -f "${ROOT}/test/gates/SCALE-GATES.md" ]] || exit 1
[[ -f "${ROOT}/test/ui-chaos/chaos.test.js" ]] || exit 1
n=$(find "${ROOT}/test/cpp-legacy" -name '*.cpp' | wc -l | tr -d ' ')
[[ "$n" -ge 10 ]] || { echo "expected cpp-legacy tests, got $n"; exit 1; }
for s in "${ROOT}/test/scripts/"*.sh; do bash -n "$s"; done
"${ROOT}/test/scripts/run-stack-smoke.sh"
echo "ok: e2e gate"
