# SCALE-0 — Baseline inventory

**Date:** 2026-06-21
**Hardware:** M3 Max 36 GB (see `config/coordinator.json` memory note)
**Roster:** 13 agents (`swarm-config.json`) — 3 on `:8080` (foreman, reviewer, scout),
9 on `:8082` (architect, database, debugger, frontend, optimizer, programmer, security,
synthesis, tester), 1 MLX on `:8083` (mlx-scout).
**Change:** None — baseline before SCALE-1 scale-up.

## Gate reference

[SCALE-GATES.md](./SCALE-GATES.md) · run via `make scale-gate`

## Configure snapshot

- Active mode: `router`; swarm config: `swarm-config.json` (13 agents)
- Model servers spawned via proxy `/api/configure` with `--metrics` + `--slot-save-path`
  (KV pressure read from `/slots`, `/metrics` fallback). All endpoints `ok=true`.
- Control plane: coordinator `:8000`, proxy `:3002`, slot-manager `:8013` (parity probe).

## Idle pressure (coordinator `:8000/api/pressure`)

| endpoint / port | names | slots | idle usage |
|-----------------|-------|-------|------------|
| `:8080` (llama) | foreman, reviewer, scout | 3 | 0.0 |
| `:8082` (llama) | architect, database, debugger, frontend, optimizer, programmer, security, synthesis, tester | 9 | 0.0 |
| `:8083` (mlx) | mlx-scout | 1 | 0.0 |

## Nominal workload results (`make scale-gate` + per-prompt run)

| Mode | Prompt | Pass | Wall s | kv_pressure | Notes |
|------|--------|------|--------|-------------|-------|
| flat | P1 | yes | ≥120* | 0.065 | 209 real tokens |
| flat | P2 | yes | ≥120* | 0.074 | 225 real tokens |
| pipeline | P1 | yes | ≥120* | 0.001 | 3098 real tokens |
| pipeline | P2 | yes | ≥120* | 0.008 | 3070 real tokens |
| cascade | P1 | yes | ≥120* | 0.051 | 191 real tokens |
| cascade | P2 | yes | ≥120* | 0.089 | 228 real tokens |
| router | P4 | yes | 40.9 | 0.0 | 38 real tokens (≤ max_select) |

`*` Broadcast modes were capped at the 120 s probe timeout (stream stayed open after the
answer); these are **not** clean completion latencies — refine with a `[DONE]`-aware driver
before using them as a speed baseline. `router` (P4) closed naturally at 40.9 s.

## Pressure peaks

| endpoint / port | names | peak usage | PASS/WARN/FAIL |
|-----------------|-------|------------|----------------|
| `:8082` (llama, 9 slots) | architect … tester | 0.089 (cascade P2) | **PASS** (<0.60) |
| `:8080` (llama, 3 slots) | foreman, reviewer, scout | 0.074 (flat P2) | **PASS** |
| `:8083` (mlx) | mlx-scout | 0.0 | **PASS** |

## Gate verdict

- [x] Baseline pressure logged (idle + under load)
- [x] Nominal workload table complete — 7/7 produced real output across all four modes
- [x] **Advance to SCALE-1:** **YES** — peak KV 0.089 ≪ 0.60; all modes return; no OOM/hung stream

## Notes

- `make scale-gate`: KV gate **PASS** (peak <0.60), mode smoke **ALL MODES PASS**
  (flat 149 / pipeline 2374 / cascade 188 / router 55 real token events on P1).
- Servers spawned with `--metrics` (+ `--slot-save-path`); `/slots` populated `slots_total`
  3/9/1, so KV `usage` is readable without an explicit `--slots` rebuild.
- Follow-up before load sprints: a `[DONE]`-aware stream driver for true latency numbers
  (current wall times are timeout-capped for broadcast modes).
- Slot math reminder: per-slot KV ≈ `ctx_cap ÷ parallel` per model server.
