#!/usr/bin/env bash
# Run the full observer presence smoke suite: the Python ServiceComponent path plus every Go
# presence-attaching binary (4 mode relays + 2 adapters), each end-to-end against live NATS
# (announce -> online -> goodbye -> offline). Exits non-zero if any case fails.
#
# Each case boots its own nats-server + zmq-bridge + observer and tears them down, so they run
# sequentially. Invoked by `make smoke-presence`.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

declare -a RESULTS
run() { # label, command...
  local label="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    printf '  PASS  %-26s %s\n' "$label" "$(printf '%s' "$out" | tail -1)"
    RESULTS+=("PASS  $label")
  else
    printf '  FAIL  %-26s\n' "$label"
    printf '%s\n' "$out" | sed 's/^/      | /'
    RESULTS+=("FAIL  $label")
  fi
}

echo "== observer presence smoke suite =="
run "python ServiceComponent" bash "$HERE/observer-presence-smoke.sh"
for m in cascade flat pipeline router; do
  run "mode-$m" bash "$HERE/mode-relay-smoke.sh" "$m"
done
for a in agentic openai-compat; do
  run "adapter-$a" bash "$HERE/adapter-smoke.sh" "$a"
done

echo "-----------------------------------"
fails=$(printf '%s\n' "${RESULTS[@]}" | grep -c '^FAIL' || true)
echo "Total: ${#RESULTS[@]}  |  Failures: $fails"
if [ "$fails" = 0 ]; then echo "ALL GREEN"; exit 0; else echo "SOME FAILED"; exit 1; fi
