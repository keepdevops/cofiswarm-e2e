#!/usr/bin/env bash
# End-to-end observer presence smoke test.
#
# Wires the full pipeline and drives a real Python ServiceComponent through it:
#
#   announce_py.py --NATS--> nats-server --swarm.>--> cofiswarm-zmq-bridge --SSE /v1/stream-->
#       cofiswarm-observer (announce->presence translator + roster) --/v1/observed--> assert
#
# Asserts the component shows ONLINE after announce, then OFFLINE after goodbye. Exercises the
# Python attach path (cofiswarm-observer-sdk) AND the Go observer's announce/goodbye translator.
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
COMPONENT="smoke-py"
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

# 1) NATS broker
command -v nats-server >/dev/null || fail "nats-server not installed"
nats-server -p "$NATS_PORT" >"$TMP/nats.log" 2>&1 & PIDS+=($!)

# 2) zmq-bridge (NATS backend, stream wildcard swarm.>)
log "building bridge + observer..."
( cd "$REPOS/cofiswarm-zmq-bridge" && go build -o "$TMP/bridge" ./cmd/cofiswarm-zmq-bridge ) || fail "bridge build"
COFISWARM_BUS=nats COFISWARM_NATS_URL="$NATS_URL" COFISWARM_BUS_WILDCARD='swarm.>' \
  "$TMP/bridge" -listen ":$BRIDGE_PORT" -topics "$REPOS/cofiswarm-zmq-bridge/spec/topics.yaml" \
  >"$TMP/bridge.log" 2>&1 & PIDS+=($!)

# 3) observer (tail the bridge SSE; fast hello/TTL so the test converges quickly)
( cd "$REPOS/cofiswarm-observer" && go build -o "$TMP/observer" ./cmd/cofiswarm-observer ) || fail "observer build"
COFISWARM_BRIDGE_URL="$BRIDGE_URL" COFISWARM_HELLO_INTERVAL=2s COFISWARM_PRESENCE_TTL=10s \
  "$TMP/observer" -listen ":$OBS_PORT" >"$TMP/observer.log" 2>&1 & PIDS+=($!)

wait_http "$BRIDGE_URL/healthz" "bridge" 15
wait_http "$OBS_URL/healthz" "observer" 15

# 4) Python ServiceComponent announces presence
command -v python3 >/dev/null || fail "python3 not installed"
PYTHONPATH="$REPOS/cofiswarm-observer-sdk/python" COFISWARM_NATS_URL="$NATS_URL" SMOKE_COMPONENT="$COMPONENT" \
  python3 "$HERE/announce_py.py" >"$TMP/py.log" 2>&1 & PY_PID=$!; PIDS+=($PY_PID)

# 5) assert ONLINE (allow a hello cycle in case the first announce raced the SSE subscribe)
assert_within "$COMPONENT appears ONLINE in /v1/observed" 0 20 "$COMPONENT"

# 6) goodbye -> assert OFFLINE
log "sending goodbye ($COMPONENT)..."
kill "$PY_PID" 2>/dev/null
assert_within "$COMPONENT removed (OFFLINE) after goodbye" 1 15 "$COMPONENT"

log "PASSED — full Python attach path + announce/goodbye translator verified."
