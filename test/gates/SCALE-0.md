# SCALE-0 — Baseline inventory

**Date:** 2026-06-21 (partial — see verdict)
**Hardware:** M3 Max 36 GB (see `config/coordinator.json` memory note)
**Roster:** 13 agents configured (`swarm-config.json`); **0 serving** at run time
**Change:** None — establish baseline before SCALE-1 scale-up or load sprints.

## Gate reference

[SCALE-GATES.md](./SCALE-GATES.md) · run via `make scale-gate`

## Configure snapshot

- Active mode: `router`
- Control plane up: coordinator `:8000`, proxy `:3002`, slot-manager `:8013`
- Observer/bus up: zmq-bridge + observer + observer-gateway (Docker)

## Idle pressure (coordinator `:8000/api/pressure`, parity `:8013`)

| endpoint / port | names | idle usage | state |
|-----------------|-------|------------|-------|
| `:8080` (llama) | foreman, reviewer, scout | n/a | **down** — `ok=false` (no `/slots` `/metrics`) |
| `:8082` (llama) | architect, database, debugger, frontend, optimizer, programmer, security, synthesis, tester | n/a | **down** — `ok=false` |
| `:8083` (mlx) | mlx-scout | 0.0 | pressure API `ok=true`, but inference not responding (see below) |

slot-manager `:8013` parity probe agrees: `mlx1b ok=true usage=0`; `coder7b/llama8b/gemma9b/gemma2b` down.

## Nominal workload results (`make scale-gate` → mode_smoke)

Every agent returned `"Agent <name> (Port <p>) is not responding."` — **0 real tokens** in
all modes. The model servers (llama-server processes) are not running, and the MLX endpoint
does not answer inference despite reporting pressure-OK.

| Mode | Prompt | Pass | Wall s | kv_pressure | Notes |
|------|--------|------|--------|-------------|-------|
| flat | P1 | NO | ~0.0 | 0.0 | all 13 agents "not responding" |
| flat | P2 | NO | ~0.0 | 0.0 | all agents "not responding" |
| pipeline | P1 | NO | ~0.0 | 0.0 | all agents "not responding" |
| pipeline | P2 | NO | ~0.0 | 0.0 | all agents "not responding" |
| cascade | P1 | NO | ~0.0 | 0.0 | no proposers; no synthesis |
| cascade | P2 | NO | ~0.0 | 0.0 | no proposers; no synthesis |
| router | P4 | NO | ~0.3 | 0.0 | classifier ran; selected agent(s) not responding |

`~0.0s` wall + identical per-mode event counts confirm no generation occurred — the streams
return agent-down frames immediately, not tokens.

## Gate verdict

- [x] Baseline pressure logged (idle) — **but no live KV** (llama down, mlx usage 0)
- [ ] Nominal workload table complete — **failed: 0/7 produced real output**
- [ ] **Advance to SCALE-1:** **NO** — baseline not established; inference layer down

## Blocker / next

The 13-agent baseline cannot be established until the model servers are actually serving:

1. Launch the llama-servers **with `--metrics --slots`** (proxy spawn args / `scripts/matrix-env.sh`)
   so KV `usage` is readable — otherwise `/api/pressure` stays `null` even when up.
2. Confirm the MLX endpoint answers inference (it reports pressure-OK but returned
   "not responding").
3. Re-run `make scale-gate` (KV pressure + mode smoke). When the KV gate is PASS (`<0.60`)
   and all four modes produce real tokens, fill this table and set the verdict to YES.

## Notes

- Gate automation landed (`test/gates/scripts/`, `make scale-gate`); this run also surfaced
  and fixed a `mode_smoke` false-positive (agent "not responding" tokens were counted as output).
- Slot math reminder: per-slot KV ≈ `ctx_cap ÷ parallel` per model server.
