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

## Why

8 sessions × broadcast to the 9-agent `:8082` group = ~72 simultaneous agent requests
against **9 continuous-batching slots**. Requests that can't get a slot within the per-agent
deadline (`MATRIX_CASCADE_AGENT_DEADLINE_SECS`) return "Agent … is not responding". So the
ceiling is **slot concurrency**, hit long before KV pressure.

## Gate verdict

- [x] KV peak 0.165 < 0.60 — **PASS** (KV gate)
- [ ] Stability (§3.2): **FAIL** — 50% of sessions had agents not responding (slot starvation)
- [ ] **Advance to SCALE-3:** **NO** at this concurrency — clean ceiling is **~4 sessions**
      (SCALE-1 passed clean; 8 degrades).

## Tuning playbook (to push past the ceiling)

Apply, then re-run `make scale-gate` + this load:

1. **Cap concurrent sessions to ~4** for clean operation at the current slot count.
2. **Raise `--parallel`** (more slots) on the `:8082` group — trades per-slot KV
   (`ctx_cap ÷ parallel`) for concurrency; KV has huge headroom (0.16) to spend.
3. **Raise the per-agent deadline** so queued requests wait for a slot instead of failing.
4. Re-measure: target all sessions returning output before advancing to SCALE-3.

## Notes

- vs SCALE-1 (4 sessions: clean, peak 0.43 on mlx): doubling to 8 sessions **lowered**
  observed mlx peak (it dropped to not-ok / starved) and broke half the sessions — a
  contention cliff, not a gradual KV climb.
- Headroom insight: KV at 0.16 means slots, not memory, gate concurrency here — so the
  productive next lever is `--parallel`, not reducing `ctx`/tokens.
