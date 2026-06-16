#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

rm -rf \
  "${COFISWARM_VAR_LIB}/dispatch/sessions/"* \
  "${COFISWARM_VAR_LIB}/dispatch/history/"* \
  "${COFISWARM_VAR_LOG}/"* \
  "${COFISWARM_RUN_ROOT}/"* 2>/dev/null || true

mkdir -p \
  "${COFISWARM_VAR_LIB}/dispatch/sessions" \
  "${COFISWARM_VAR_LIB}/dispatch/history" \
  "${COFISWARM_VAR_LOG}/agent_logs" \
  "${COFISWARM_RUN_ROOT}"

echo "reset-standalone: ${COFISWARM_TEST_ROOT}"
