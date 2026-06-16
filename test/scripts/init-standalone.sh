#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

mkdir -p \
  "${COFISWARM_ETC_ROOT}/config/agents" \
  "${COFISWARM_VAR_LIB}/dispatch/sessions" \
  "${COFISWARM_VAR_LIB}/dispatch/history" \
  "${COFISWARM_VAR_LOG}/agent_logs"

# Config fixtures from repo (when present)
if [[ -f "${REPO_ROOT}/swarm-config.json" ]]; then
  cp "${REPO_ROOT}/swarm-config.json" "${COFISWARM_ETC_ROOT}/config/"
fi
if [[ -d "${REPO_ROOT}/config/agents" ]]; then
  cp -R "${REPO_ROOT}/config/agents/." "${COFISWARM_ETC_ROOT}/config/agents/"
fi
if [[ -f "${REPO_ROOT}/config/coordinator.json" ]]; then
  cp "${REPO_ROOT}/config/coordinator.json" "${COFISWARM_ETC_ROOT}/config/"
fi

# State fixtures (optional seed)
if [[ -f "${REPO_ROOT}/sessions.json" ]]; then
  cp "${REPO_ROOT}/sessions.json" "${COFISWARM_VAR_LIB}/dispatch/sessions/"
fi
if [[ -f "${REPO_ROOT}/history.json" ]]; then
  cp "${REPO_ROOT}/history.json" "${COFISWARM_VAR_LIB}/dispatch/history/"
fi

"${SCRIPT_DIR}/assert-layout.sh"
echo "init-standalone: ${COFISWARM_TEST_ROOT}"
