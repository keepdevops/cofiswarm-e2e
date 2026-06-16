# SCALE-0 — Baseline inventory

**Date:** _fill on first run_  
**Hardware:** M3 Max 36 GB (see `config/coordinator.json` memory note)  
**Roster:** 13 agents (full `swarm-config.json`)  
**Change:** None — establish baseline before SCALE-1 scale-up or load sprints.

## Gate reference

[SCALE-GATES.md](./SCALE-GATES.md) · [ML-BOTTLENECKS.md](../ML-BOTTLENECKS.md)

## Configure snapshot

- Default mode: `router` (`max_select: 2`)
- Cascade synthesizer: `synthesis`
- RAG: enabled (`top_k: 3`)
- KV cache types: q4_0 / q8_0 on llama agents (see `extra_args`)

## Idle pressure (fill after probe)

```bash
curl -s http://127.0.0.1:8000/api/pressure | jq '.[] | {port, names, usage}'
```

| endpoint / port | names | idle usage |
|-----------------|-------|------------|
| | | |

## Nominal workload results

_Complete per SCALE-GATES §2 before marking SCALE-0 done._

| Mode | Prompt | Pass | Wall s | kv_pressure | Notes |
|------|--------|------|--------|-------------|-------|
| flat | P1 | | | | |
| flat | P2 | | | | |
| pipeline | P1 | | | | |
| pipeline | P2 | | | | |
| cascade | P1 | | | | |
| cascade | P2 | | | | |
| router | P4 | | | | |

## Gate verdict

- [ ] Baseline pressure logged
- [ ] Nominal workload table complete
- [ ] **Advance to SCALE-1:** YES / NO

## Notes

_Slot math reminder: per-slot KV ≈ `ctx_cap ÷ parallel` per model server._
