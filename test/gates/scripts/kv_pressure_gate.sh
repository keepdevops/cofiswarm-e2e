#!/usr/bin/env bash
# SCALE gate: KV pressure (SCALE-GATES.md §3.1). Probes a pressure endpoint N times and
# applies the gate thresholds:
#
#   PASS  peak usage  < --max-usage (default 0.60)
#   WARN  peak usage in [--max-usage, --fail-usage)            -> exit 2
#   FAIL  usage >= --fail-usage (default 0.75) for >= --fail-streak consecutive probes -> exit 1
#
# Endpoint defaults to the coordinator; post control-plane split point it at slot-manager
# (see SCALE-GATES.md §7), e.g. --url http://127.0.0.1:8013/api/pressure. Both expose the
# same response shape: a JSON array of {ok, usage, names, port, ...}.
#
# Exit 0 = PASS, 2 = WARN, 1 = FAIL. Unreachable endpoint or no readable pressure (all
# endpoints down / usage null) -> SKIP (exit 0) with an INCONCLUSIVE message, so this can be
# wired into CI without a live inference stack breaking the build.
set -uo pipefail

URL="${COFISWARM_PRESSURE_URL:-http://127.0.0.1:8000/api/pressure}"
MAX_USAGE=0.60 FAIL_USAGE=0.75 PROBES=5 INTERVAL=10 FAIL_STREAK=3

while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --max-usage) MAX_USAGE="$2"; shift 2 ;;
    --fail-usage) FAIL_USAGE="$2"; shift 2 ;;
    --probes) PROBES="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --fail-streak) FAIL_STREAK="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

for t in curl jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP kv_pressure_gate: '$t' not available"; exit 0; }
done
if ! curl -fsS -m 5 "$URL" >/dev/null 2>&1; then
  echo "SKIP kv_pressure_gate: pressure endpoint unreachable ($URL)"; exit 0
fi

echo "== KV pressure gate: $URL =="
echo "   max-usage=$MAX_USAGE fail-usage=$FAIL_USAGE probes=$PROBES interval=${INTERVAL}s fail-streak=$FAIL_STREAK"

peak=0 streak=0 max_streak=0 readable=0
for i in $(seq 1 "$PROBES"); do
  body="$(curl -fsS -m 5 "$URL" 2>/dev/null || echo '[]')"
  # Highest usage among endpoints that are up and report a numeric usage this probe.
  u="$(printf '%s' "$body" | jq -r '[.[] | select(.ok == true and .usage != null) | .usage] | max // empty')"
  if [ -z "$u" ]; then
    echo "   probe $i/$PROBES: no readable usage (endpoints down or usage null)"
    streak=0
    continue
  fi
  readable=1
  awk "BEGIN{exit !($u > $peak)}" && peak="$u"
  if awk "BEGIN{exit !($u >= $FAIL_USAGE)}"; then
    streak=$((streak + 1)); [ "$streak" -gt "$max_streak" ] && max_streak="$streak"
  else
    streak=0
  fi
  printf '   probe %d/%d: peak-usage=%s (this=%s, fail-streak=%d)\n' "$i" "$PROBES" "$peak" "$u" "$streak"
  [ "$i" -lt "$PROBES" ] && sleep "$INTERVAL"
done

if [ "$readable" -eq 0 ]; then
  echo "INCONCLUSIVE: no endpoint reported readable KV pressure — is the inference layer up with --metrics --slots?"
  exit 0
fi
echo "-----------------------------------"
echo "peak usage = $peak (over $PROBES probes); longest >=$FAIL_USAGE streak = $max_streak"
if [ "$max_streak" -ge "$FAIL_STREAK" ]; then
  echo "FAIL: usage >= $FAIL_USAGE for $max_streak consecutive probes (>= $FAIL_STREAK) — do not advance"; exit 1
elif awk "BEGIN{exit !($peak >= $MAX_USAGE)}"; then
  echo "WARN: peak >= $MAX_USAGE — tune tokens/quant and re-run; document in SCALE-N.md"; exit 2
fi
echo "PASS: peak < $MAX_USAGE — eligible to advance"; exit 0
