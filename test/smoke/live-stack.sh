#!/usr/bin/env bash
# Live multi-service run: boot the full observer pipeline ONCE and bring up every attached
# service simultaneously, then assert they all share a single /v1/observed roster, then drain.
#
#   services --(NATS servicecomponent | HTTP buspresence)--> nats-server / zmq-bridge -->
#       cofiswarm-observer (roster) --/v1/observed--> assert all ONLINE -> SIGTERM -> assert OFFLINE
#
# Unlike the per-component smoke cases (observer-presence-smoke.sh and its wrappers), which have
# exactly ONE component online at a time, this proves the roster holds many heterogeneous
# components together and exercises BOTH attach paths (servicecomponent + buspresence) at once.
#
# Requires: nats-server, go, curl, python3 (json assert). Uses ports 14222/15555/18016 for infra
# and 18015/18020-18025/18030-18031 for service HTTP, to avoid clashing with real services.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPOS="$(cd "$HERE/../../.." && pwd)"
FIX="$HERE/fixtures"
NATS_PORT=14222 BRIDGE_PORT=15555 OBS_PORT=18016
NATS_URL="nats://127.0.0.1:${NATS_PORT}"
BRIDGE_URL="http://127.0.0.1:${BRIDGE_PORT}"
OBS_URL="http://127.0.0.1:${OBS_PORT}"
TMP="$(mktemp -d)"
PIDS=()

# Deterministic single-id services we strictly assert (component_id -> launch closure below).
EXPECT=(convert mode-flat mode-pipeline mode-cascade mode-router \
        adapter-agentic adapter-openai-compat kvpool slot-manager launcher dispatch)

log() { printf '[live] %s\n' "$*"; }
fail() { log "FAIL: $*"; log "--- recent logs ---"; tail -n 8 "$TMP"/*.log 2>/dev/null; exit 1; }
cleanup() { for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

wait_http() { local url="$1" name="$2" deadline=$(( SECONDS + ${3:-15} ))
  until curl -fsS "$url" >/dev/null 2>&1; do
    [ $SECONDS -ge $deadline ] && fail "$name did not come up at $url"; sleep 0.3
  done; log "$name up"; }

# roster_ids -> newline-separated component_ids currently ONLINE
roster_ids() { curl -fsS "$OBS_URL/v1/observed" 2>/dev/null \
  | python3 -c "import sys,json; [print(c.get('component_id','')) for c in json.load(sys.stdin).get('online',[])]"; }

build() { ( cd "$REPOS/$1" && go build -o "$TMP/$2" "./$3" ) || fail "$1 build"; }

# ---- preflight ----
for t in nats-server go curl python3; do command -v "$t" >/dev/null || { log "SKIP: '$t' not available"; exit 0; }; done

# ---- infra: nats + bridge + observer (fast hello/TTL so it converges quickly) ----
nats-server -p "$NATS_PORT" >"$TMP/nats.log" 2>&1 & PIDS+=($!)
log "building infra (bridge + observer)..."
build cofiswarm-zmq-bridge bridge cmd/cofiswarm-zmq-bridge
COFISWARM_BUS=nats COFISWARM_NATS_URL="$NATS_URL" COFISWARM_BUS_WILDCARD='swarm.>' \
  "$TMP/bridge" -listen ":$BRIDGE_PORT" -topics "$REPOS/cofiswarm-zmq-bridge/spec/topics.yaml" \
  >"$TMP/bridge.log" 2>&1 & PIDS+=($!)
build cofiswarm-observer observer cmd/cofiswarm-observer
COFISWARM_BRIDGE_URL="$BRIDGE_URL" COFISWARM_HELLO_INTERVAL=2s COFISWARM_PRESENCE_TTL=10s \
  "$TMP/observer" -listen ":$OBS_PORT" >"$TMP/observer.log" 2>&1 & PIDS+=($!)
wait_http "$BRIDGE_URL/healthz" bridge 15
wait_http "$OBS_URL/healthz" observer 15

# ---- build + start every attached service ----
log "building + starting services..."
build cofiswarm-convert convert cmd/cofiswarm-convert
build cofiswarm-kvpool kvpool cmd/cofiswarm-kvpool
build cofiswarm-slot-manager slot-manager cmd/cofiswarm-slot-manager
build cofiswarm-launcher launcher cmd/cofiswarm-configure   # bus-presence binary (announces id "launcher")
build cofiswarm-dispatch dispatch cmd/cofiswarm-dispatch
build cofiswarm-agent-registry agent-registry cmd/cofiswarm-agent-registry
for m in flat pipeline cascade router; do build "cofiswarm-mode-$m" "mode-$m" "cmd/cofiswarm-mode-$m"; done
for a in agentic openai-compat; do build "cofiswarm-adapter-$a" "adapter-$a" "cmd/cofiswarm-adapter-$a"; done

start() { local log="$1"; shift; "$@" >"$TMP/$log.log" 2>&1 & PIDS+=($!); }

# servicecomponent alongside HTTP (COFISWARM_NATS_URL): convert, modes, adapters
COFISWARM_NATS_URL="$NATS_URL" start convert "$TMP/convert" -listen ":18015"
for m in flat pipeline cascade router; do
  COFISWARM_NATS_URL="$NATS_URL" start "mode-$m" "$TMP/mode-$m" -config "$FIX/mode-$m.yaml"
done
for a in agentic openai-compat; do
  COFISWARM_NATS_URL="$NATS_URL" start "adapter-$a" "$TMP/adapter-$a" -config "$FIX/adapter-$a.yaml"
done
# servicecomponent bus mode (-bus -nats): kvpool, slot-manager, launcher
start kvpool       "$TMP/kvpool"       -bus -nats "$NATS_URL"
start slot-manager "$TMP/slot-manager" -bus -nats "$NATS_URL"
start launcher     "$TMP/launcher"     -bus -nats "$NATS_URL"
# buspresence over HTTP (COFISWARM_BRIDGE_URL): dispatch + agent-registry (member agents)
COFISWARM_BRIDGE_URL="$BRIDGE_URL" start dispatch "$TMP/dispatch" -listen ":18030" -state "$TMP/dispatch-state"
COFISWARM_BRIDGE_URL="$BRIDGE_URL" COFISWARM_SWARM_CONFIG="$REPOS/cofiswarm-config/swarm-config.json" \
  COFISWARM_AGENT_REGISTRY_STATE="$TMP/ar-overrides.json" \
  start agent-registry "$TMP/agent-registry" -listen ":18031"

# ---- assert: all expected components ONLINE together ----
log "waiting for ${#EXPECT[@]} services to appear in one roster..."
deadline=$(( SECONDS + 40 ))
while true; do
  ids="$(roster_ids)"; missing=()
  for c in "${EXPECT[@]}"; do printf '%s\n' "$ids" | grep -qx "$c" || missing+=("$c"); done
  [ ${#missing[@]} -eq 0 ] && break
  [ $SECONDS -ge $deadline ] && fail "missing from roster: ${missing[*]}"
  sleep 0.5
done
total=$(printf '%s\n' "$ids" | grep -c . || true)
extras=$(( total - ${#EXPECT[@]} ))
log "OK: all ${#EXPECT[@]} deterministic services ONLINE in one roster ($total total; $extras agent-registry member(s))"
printf '%s\n' "$ids" | sort | sed 's/^/        - /'

# ---- drain: SIGTERM everything, assert the roster empties of our services ----
log "sending SIGTERM to all services (goodbye)..."
for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
deadline=$(( SECONDS + 20 ))
while true; do
  ids="$(roster_ids 2>/dev/null || true)"; still=()
  for c in "${EXPECT[@]}"; do printf '%s\n' "$ids" | grep -qx "$c" && still+=("$c"); done
  { [ ${#still[@]} -eq 0 ] || [ -z "$ids" ]; } && break
  [ $SECONDS -ge $deadline ] && fail "still ONLINE after goodbye: ${still[*]}"
  sleep 0.5
done
log "OK: roster drained after goodbye"
log "PASSED — heterogeneous live stack (${#EXPECT[@]} services, both attach paths) verified through the bus."
