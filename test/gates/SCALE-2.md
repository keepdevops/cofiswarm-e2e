# SCALE-2 — Load sprint (concurrency ceiling found)

**Date:** 2026-06-21
**Hardware:** M3 Max 36 GB
**Roster:** 13 agents (unchanged — load sprint per [SCALE-GATES §4](./SCALE-GATES.md))
**Change:** **8 concurrent `flat` sessions** (2× SCALE-1's 4), codegen P2.

## Results — the limiter is slots, not KV

| endpoint / port | slots | peak usage | PASS/WARN/FAIL |
|-----------------|-------|------------|----------------|
| `:8080` (llama) | 3 | 0.165 | KV PASS (<0.60) |
| `:8082` (llama) | 9 | 0.163 | KV PASS |
| `:8083` (mlx) | 1 | n/a (1 not-ok sample) | — |

**KV pressure stayed low (~0.16)** — memory is *not* the constraint. But output degraded:

| Sessions with real output | not-responding sessions |
|---------------------------|-------------------------|
| **4 / 8** | 4 / 8 returned all-"not responding" |

Per-session: 6 / 0 / 97 / 0 / 54 / 0 / 0 / 212 real tokens (four sessions got **zero**).

## Why (root cause — traced in source)

8 sessions × broadcast to the 9-agent `:8082` group (a **Qwen2.5-14B** server) = ~72
simultaneous connections against **9 continuous-batching slots**. Tracing the
"not responding" string to its source (`agent_stream_llama.h` → `cli.Post` returns `!res`):

- The failure is at **connect**, not read. The coordinator's per-agent HTTP client sets a
  **hardcoded 5 s connection timeout** (`agent_stream_pool.cpp`: `set_connection_timeout(5)`).
  When the 14B server is saturated, new connections aren't accepted within 5 s → `!res` →
  "Agent … is not responding".
- It is **not** a deadline: there is no `MATRIX_CASCADE_AGENT_DEADLINE_SECS` in this build
  (stale doc reference). The per-agent `read_timeout_secs` is already **510 s** (config) and
  governs reads *after* connect, so raising it does not help.
- `--parallel` is fixed at the group's agent count (9) — compile-time, no override.

So the ceiling is **connection acceptance under slot saturation**, hit far below KV pressure.
Both levers that would raise it (the 5 s connection timeout; more `--parallel` slots) are
**compile-time constants** in the proxy/coordinator — no runtime/env knob exists.

## Gate verdict

- [x] KV peak 0.165 < 0.60 — **PASS** (KV gate)
- [ ] Stability (§3.2): **FAIL** — 50% of sessions had agents not responding (slot starvation)
- [ ] **Advance to SCALE-3:** **NO** at this concurrency — clean ceiling is **~4 sessions**
      (SCALE-1 passed clean; 8 degrades).

## Tuning playbook (to push past the ceiling)

Runtime-only (no rebuild):

1. **Cap concurrent sessions to ~4** — the proven clean ceiling at the current build.

Require a proxy/coordinator rebuild (both are compile-time constants; attempted and
deferred — the proxy build mechanism is not discoverable in the workspace, and only ~12 GB
is free vs a 14B model, so doubling slots risks OOM):

2. **Raise the connection timeout** `set_connection_timeout(5)` in `agent_stream_pool.cpp`
   (and/or make it env-driven) so connects to a busy server wait instead of failing in 5 s.
3. **Raise `--parallel`** in `proxy_configure_spawn_args.h` (currently `g.names.size()`) for
   more slots — trades per-slot KV for concurrency; KV has headroom (~0.16), but the 14B
   group's extra KV must fit in RAM.

Then re-run `make scale-gate` + this load; target all sessions returning output.

## Notes

- vs SCALE-1 (4 sessions: clean, peak 0.43 on mlx): doubling to 8 sessions **lowered**
  observed mlx peak (it dropped to not-ok / starved) and broke half the sessions — a
  contention cliff, not a gradual KV climb.
- Headroom insight: KV at 0.16 means slots, not memory, gate concurrency here — so the
  productive next lever is `--parallel`, not reducing `ctx`/tokens.
