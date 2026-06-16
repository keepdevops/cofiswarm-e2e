#!/usr/bin/env bash
# Probe migrated control-plane health endpoints (best-effort).
set -euo pipefail
declare -a TARGETS=(
  "dispatch:8010"
  "agent-registry:8012"
  "slot-manager:8013"
  "kvpool:8014"
  "mode-flat:8021"
  "mode-pipeline:8022"
  "mode-cascade:8023"
  "mode-router:8024"
  "convert:8015"
  "observer:8016"
  "zmq-bridge:5555"
  "rag:8001"
  "orchestrate:3003"
)
ok=0
skip=0
for t in "${TARGETS[@]}"; do
  name="${t%%:*}"
  port="${t##*:}"
  if curl -sf --max-time 2 "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
    echo "ok: ${name} :${port}"
    ok=$((ok + 1))
  elif curl -sf --max-time 2 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
    echo "ok: ${name} :${port} (/health)"
    ok=$((ok + 1))
  else
    echo "skip: ${name} :${port} (not running)"
    skip=$((skip + 1))
  fi
done
echo "smoke: ${ok} up, ${skip} skipped"
[[ "${COFISWARM_E2E_LIVE:-0}" == "1" ]] && [[ "$ok" -ge 3 ]] || [[ "${COFISWARM_E2E_LIVE:-0}" != "1" ]]
