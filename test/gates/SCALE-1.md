# SCALE-1 — Load sprint (concurrent sessions)

**Date:** 2026-06-21
**Hardware:** M3 Max 36 GB
**Roster:** 13 agents (unchanged — already full at SCALE-0, so per
[SCALE-GATES §4](./SCALE-GATES.md) this is a **load sprint**, not +1 agent)
**Change:** **4 concurrent `flat` sessions** vs SCALE-0's single session (codegen P2:
"Write a Python LRU cache class with get/put and unit tests.").

## Configure snapshot

- Same serving topology as SCALE-0: `:8080` (3 slots), `:8082` (9 slots), `:8083` mlx (1).
- Load driver: 4 simultaneous `/api/architect/stream` flat broadcasts; KV `/api/pressure`
  sampled every 2 s for the duration; peak per endpoint recorded.

## Results

All 4 concurrent sessions returned real output (no hung/empty stream):

| Session | Real tokens |
|---------|-------------|
| 1 | 56 |
| 2 | 114 |
| 3 | 26 |
| 4 | 96 |

## Pressure peaks (under 4× concurrency)

| endpoint / port | slots | peak usage | PASS/WARN/FAIL |
|-----------------|-------|------------|----------------|
| `:8080` (llama) | 3 | 0.125 | **PASS** (<0.60) |
| `:8082` (llama) | 9 | 0.118 | **PASS** |
| `:8083` (mlx) | 1 | **0.429** | **PASS** (approaching WARN) |

Peak overall **0.429** on the single-slot MLX endpoint — concurrency serializes through its
one slot, so its KV fills fastest. The 3- and 9-slot llama servers absorbed the same
concurrency at ~0.12. **MLX is the scaling limiter.**

## Gate verdict

- [x] All modes/sessions return real output; no OOM, no hung stream
- [x] KV peak 0.429 < 0.60 (WARN at 0.60) — within budget
- [x] **Advance to SCALE-2:** **YES** — raise load further (more concurrency or P3 long
      context); watch the MLX `:8083` slot first.

## Notes

- vs SCALE-0 (single session, peak 0.089): 4× concurrency raised peak to 0.429, almost
  entirely on the 1-slot MLX lane; llama lanes barely moved (0.07 → 0.12).
- Tuning lever if MLX hits WARN at higher concurrency: it is serialized by design (1 slot);
  cap concurrent mlx-scout requests or exclude it from high-concurrency load modes.
- Re-validate with `make scale-gate` after each load increase.
