#!/usr/bin/env bash
# End-to-end observer presence smoke test.
#
# Boots the full pipeline and drives a component through it:
#
#   component --NATS--> nats-server --swarm.>--> cofiswarm-zmq-bridge --SSE /v1/stream-->
#       cofiswarm-observer (announce->presence translator + roster) --/v1/observed--> assert
#
# Asserts the component shows ONLINE after announce, then OFFLINE after goodbye. Exercises the
# Go observer's announce/goodbye translator AND the chosen component's attach path.
#
# Usage:
#   observer-presence-smoke.sh
#       Default: drive a Python ServiceComponent (announce_py.py), assert component "smoke-py".
#
#   observer-presence-smoke.sh --go <repo> <cmd-pkg> <component_id> [-- <run arg> ...]
#       Build <repo>/<cmd-pkg> (a Go main package), run the binary with COFISWARM_NATS_URL
#       exported plus any run args (config paths must be ABSOLUTE), and assert <component_id>.
#       Works for any Go service with the alongside-HTTP servicecomponent (adapters, mode relays)
#       or -bus mode (inference engines), as long as run args make it connect + announce.
#       See mode-relay-smoke.sh for a ready-to-run mode-cascade example.
#
# Requires: nats-server, go, python3 with nats-py + the observer-sdk python client importable.
# Uses non-standard ports (14222/15555/18016) to avoid clashing with running services.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPOS="$(cd "$HERE/../../.." && pwd)"   # .../repos
NATS_PORT=14222
BRIDGE_PORT=15555
OBS_PORT=18016
NATS_URL="nats://127.0.0.1:${NATS_PORT}"
BRIDGE_URL="http://127.0.0.1:${BRIDGE_PORT}"
OBS_URL="http://127.0.0.1:${OBS_PORT}"
TMP="$(mktemp -d)"
PIDS=()

log() { printf '[smoke] %s\n' "$*"; }
fail() { log "FAIL: $*"; log "--- logs ---"; tail -n 20 "$TMP"/*.log 2>/dev/null; exit 1; }

cleanup() {
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null; done
  wait 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

wait_http() { # url, name, timeout_s
  local url="$1" name="$2" deadline=$(( SECONDS + ${3:-15} ))
  until curl -fsS "$url" >/dev/null 2>&1; do
    [ $SECONDS -ge $deadline ] && fail "$name did not come up at $url"
    sleep 0.3
  done
  log "$name up"
}

online_has() { # component_id -> 0 if present in /v1/observed online[]
  curl -fsS "$OBS_URL/v1/observed" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if any(c.get('component_id')=='$1' for c in d.get('online',[])) else 1)"
}

assert_within() { # description, expect(0=online present /1=absent), timeout_s, component
  local desc="$1" want="$2" deadline=$(( SECONDS + $3 )) cid="$4"
  while true; do
    if online_has "$cid"; then present=0; else present=1; fi
    [ "$present" = "$want" ] && { log "OK: $desc"; return 0; }
    [ $SECONDS -ge $deadline ] && fail "$desc (timed out)"
    sleep 0.3
  done
}

# ---- driver selection ----
DRIVER=python
COMPONENT="smoke-py"
GO_REPO="" GO_CMD=""
RUN_ARGS=()
if [ "${1:-}" = "--go" ]; then
  DRIVER=go; shift
  GO_REPO="${1:?--go needs <repo>}"; GO_CMD="${2:?--go needs <cmd-pkg>}"; COMPONENT="${3:?--go needs <component_id>}"
  shift 3
  [ "${1:-}" = "--" ] && shift
  RUN_ARGS=("$@")
fi

# ---- boot infra: nats + bridge + observer (fast hello/TTL so the test converges quickly) ----
command -v nats-server >/dev/null || fail "nats-server not installed"
nats-server -p "$NATS_PORT" >"$TMP/nats.log" 2>&1 & PIDS+=($!)

log "building bridge + observer..."
( cd "$REPOS/cofiswarm-zmq-bridge" && go build -o "$TMP/bridge" ./cmd/cofiswarm-zmq-bridge ) || fail "bridge build"
COFISWARM_BUS=nats COFISWARM_NATS_URL="$NATS_URL" COFISWARM_BUS_WILDCARD='swarm.>' \
  "$TMP/bridge" -listen ":$BRIDGE_PORT" -topics "$REPOS/cofiswarm-zmq-bridge/spec/topics.yaml" \
  >"$TMP/bridge.log" 2>&1 & PIDS+=($!)

( cd "$REPOS/cofiswarm-observer" && go build -o "$TMP/observer" ./cmd/cofiswarm-observer ) || fail "observer build"
COFISWARM_BRIDGE_URL="$BRIDGE_URL" COFISWARM_HELLO_INTERVAL=2s COFISWARM_PRESENCE_TTL=10s \
  "$TMP/observer" -listen ":$OBS_PORT" >"$TMP/observer.log" 2>&1 & PIDS+=($!)

wait_http "$BRIDGE_URL/healthz" "bridge" 15
wait_http "$OBS_URL/healthz" "observer" 15

# ---- start the component driver ----
if [ "$DRIVER" = python ]; then
  command -v python3 >/dev/null || fail "python3 not installed"
  log "driver: python ServiceComponent ($COMPONENT)"
  PYTHONPATH="$REPOS/cofiswarm-observer-sdk/python" COFISWARM_NATS_URL="$NATS_URL" SMOKE_COMPONENT="$COMPONENT" \
    python3 "$HERE/announce_py.py" >"$TMP/comp.log" 2>&1 & COMP_PID=$!; PIDS+=($COMP_PID)
else
  log "driver: go binary $GO_REPO/$GO_CMD ($COMPONENT)"
  ( cd "$REPOS/$GO_REPO" && go build -o "$TMP/comp" "./$GO_CMD" ) || fail "$GO_REPO build"
  # Run the built binary from a neutral cwd; pass config via run args with an ABSOLUTE path.
  if [ ${#RUN_ARGS[@]} -gt 0 ]; then
    COFISWARM_NATS_URL="$NATS_URL" "$TMP/comp" "${RUN_ARGS[@]}" >"$TMP/comp.log" 2>&1 & COMP_PID=$!; PIDS+=($COMP_PID)
  else
    COFISWARM_NATS_URL="$NATS_URL" "$TMP/comp" >"$TMP/comp.log" 2>&1 & COMP_PID=$!; PIDS+=($COMP_PID)
  fi
fi

# ---- assert online -> goodbye -> offline ----
# Allow a hello cycle in case the first announce raced the observer's SSE subscribe.
assert_within "$COMPONENT appears ONLINE in /v1/observed" 0 20 "$COMPONENT"
log "sending goodbye ($COMPONENT)..."
kill "$COMP_PID" 2>/dev/null
assert_within "$COMPONENT removed (OFFLINE) after goodbye" 1 15 "$COMPONENT"

log "PASSED ($DRIVER driver) — announce + goodbye verified through the live bus."
