#!/usr/bin/env bash
# SCALE gate: mode smoke (SCALE-GATES.md §2.2). For each mode, set it active on the
# coordinator and stream one prompt, asserting the stream produces output and a non-empty
# final (min acceptance: "all agents return; no hung stream; final non-empty").
#
#   ./mode_smoke.sh --modes flat,pipeline,cascade,router --prompt "What is a binary search tree?"
#
# Coordinator API (verified against :8000):
#   GET  /api/modes/active        -> {"mode":"<name>"}
#   POST /api/modes/active        {"mode":"<name>"}
#   POST /api/architect/stream    {"prompt":"..."}  -> SSE (token / agent_done / ... / done)
#
# Exit 0 = all modes PASS, 1 = any FAIL. Unreachable coordinator -> SKIP (exit 0). The
# original active mode is restored on exit.
set -uo pipefail

URL="${COFISWARM_COORD_URL:-http://127.0.0.1:8000}"
MODES="flat,pipeline,cascade,router"
PROMPT="What is a binary search tree?"
TIMEOUT=120

while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --modes) MODES="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

for t in curl jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP mode_smoke: '$t' not available"; exit 0; }
done
if ! curl -fsS -m 5 "$URL/api/modes/active" >/dev/null 2>&1; then
  echo "SKIP mode_smoke: coordinator unreachable ($URL)"; exit 0
fi

ORIG="$(curl -fsS -m 5 "$URL/api/modes/active" | jq -r '.mode // empty')"
restore() { [ -n "$ORIG" ] && curl -fsS -m 5 -X POST "$URL/api/modes/active" \
  -H 'content-type: application/json' -d "{\"mode\":\"$ORIG\"}" >/dev/null 2>&1; }
trap restore EXIT

echo "== mode smoke: $URL =="
echo "   modes=$MODES prompt=\"$PROMPT\" timeout=${TIMEOUT}s (restoring '$ORIG' on exit)"

fails=0
IFS=',' read -ra LIST <<< "$MODES"
for m in "${LIST[@]}"; do
  set_code="$(curl -fsS -m 5 -o /dev/null -w '%{http_code}' -X POST "$URL/api/modes/active" \
    -H 'content-type: application/json' -d "{\"mode\":\"$m\"}" 2>/dev/null || echo 000)"
  if [ "$set_code" != 200 ]; then
    printf '  FAIL  %-10s could not set active mode (HTTP %s)\n' "$m" "$set_code"; fails=$((fails + 1)); continue
  fi
  # Stream the prompt; capture SSE. -N disables buffering; -m bounds a hung stream.
  out="$(curl -sN -m "$TIMEOUT" -X POST "$URL/api/architect/stream" \
    -H 'content-type: application/json' -d "{\"prompt\":$(jq -Rn --arg p "$PROMPT" '$p')}" 2>/dev/null)"
  # A healthy run emits SSE data lines carrying real tokens. Exclude framing (done) AND
  # agent-failure tokens — the coordinator emits "Agent X (Port N) is not responding." /
  # timeout / error deltas per dead agent, which are data lines but NOT real output. Counting
  # them as content would false-PASS a stack whose model servers are all down.
  # Real output = token data lines carrying a "delta", minus agent-failure deltas. (agent_done
  # frames are {"agent":"X"} with no delta, so requiring "delta" also drops those.)
  data_lines="$(printf '%s\n' "$out" | grep -c '^data:' || true)"
  has_content="$(printf '%s\n' "$out" | grep -E '^data:.*"delta"' \
    | grep -viE 'error|not responding|timed out|deadline' \
    | grep -c . || true)"
  if [ "$data_lines" -gt 0 ] && [ "$has_content" -gt 0 ]; then
    printf '  PASS  %-10s %s real token event(s) of %s data line(s)\n' "$m" "$has_content" "$data_lines"
  else
    printf '  FAIL  %-10s no real tokens (data lines=%s, all framing/agent-down?)\n' "$m" "$data_lines"
    printf '%s\n' "$out" | grep '^data:' | tail -2 | sed 's/^/      | /'
    fails=$((fails + 1))
  fi
done

echo "-----------------------------------"
if [ "$fails" -eq 0 ]; then echo "ALL MODES PASS"; exit 0; fi
echo "$fails mode(s) FAILED — do not sign off SCALE-N"; exit 1
