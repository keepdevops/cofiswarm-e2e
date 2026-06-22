ROLE := e2e
.PHONY: test test-standalone-layout test-e2e-gate smoke smoke-presence live-stack scale-gate
test: test-standalone-layout test-e2e-gate smoke-presence
test-standalone-layout:
	./test/scripts/assert-layout.sh
test-e2e-gate:
	./test/scripts/test-e2e-gate.sh
smoke:
	COFISWARM_E2E_LIVE=1 ./test/scripts/run-stack-smoke.sh
# Full observer presence smoke suite: Python path + all 6 Go binaries against live NATS.
# Requires nats-server, go, and python3 with nats-py.
smoke-presence:
	./test/smoke/run-all.sh
# Live multi-service run: bring up every attached service at once (both attach paths) and assert
# they share one observer roster, then drain. Requires nats-server, go, curl, python3.
live-stack:
	./test/smoke/live-stack.sh
# SCALE sprint gates (test/gates/SCALE-GATES.md §3.1 + §2.2) against a LIVE stack. Each script
# skips cleanly if its endpoint is down, so this is safe to run anywhere. KV gate WARN (exit 2)
# / FAIL (exit 1) and mode-smoke FAIL (exit 1) abort the target so a regression is visible.
# Override the pressure source: COFISWARM_PRESSURE_URL=http://127.0.0.1:8013/api/pressure make scale-gate
scale-gate:
	./test/gates/scripts/kv_pressure_gate.sh
	./test/gates/scripts/mode_smoke.sh
