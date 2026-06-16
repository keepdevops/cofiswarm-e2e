#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../standalone" && pwd)"
ROLE="${1:-}"

required_dirs=(
  "${ROOT}/opt/cofiswarm"
  "${ROOT}/etc/cofiswarm/config"
  "${ROOT}/var/lib/cofiswarm/dispatch"
  "${ROOT}/var/lib/cofiswarm/slot-manager"
  "${ROOT}/var/lib/cofiswarm/kvpool"
  "${ROOT}/var/lib/cofiswarm/models/llama"
  "${ROOT}/var/lib/cofiswarm/models/mlx"
  "${ROOT}/var/log/cofiswarm"
  "${ROOT}/run/cofiswarm"
)

if [[ -n "$ROLE" ]]; then
  required_dirs+=(
    "${ROOT}/etc/cofiswarm/${ROLE}"
    "${ROOT}/var/lib/cofiswarm/${ROLE}"
    "${ROOT}/var/log/cofiswarm/${ROLE}"
  )
fi

for dir in "${required_dirs[@]}"; do
  [[ -d "$dir" ]] || { echo "missing: $dir"; exit 1; }
done

echo "ok: standalone layout${ROLE:+ for ${ROLE}}"
