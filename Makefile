ROLE := e2e
.PHONY: test test-standalone-layout test-e2e-gate smoke smoke-presence
test: test-standalone-layout test-e2e-gate
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
