# SCALE Sprint Gates

Gate criteria for **SCALE-1 … SCALE-7** agent scale-up sprints. Each sprint adds
one agent (or one parallel slot group) and re-validates **all four modes** before
proceeding.

**Bottleneck reference:** [../ML-BOTTLENECKS.md](../ML-BOTTLENECKS.md)

---

## 1. Purpose

| Goal | Measure |
|------|---------|
| **Memory** | KV `usage` stays below eviction thresholds under nominal load |
| **Speed** | p95 latency within sprint budget; cascade deadlines not dominating |
| **Cost** | Token counts logged per mode; router baseline documented |
| **Quality** | Subjective pass + no synthesizer collapse in cascade |

---

## 2. Nominal workload (every sprint)

Run this suite after deploy/configure and before signing off SCALE-N.

### 2.1 Prompts (fixed set — copy into sprint log)

| ID | Prompt | Exercises |
|----|--------|-----------|
| P1 | Short: “What is a binary search tree?” (≤ 50 tok) | Decode, many agents |
| P2 | Medium code: “Write a Python LRU cache class.” (~200 tok) | Prefill + codegen |
| P3 | Long context: paste ~2k tok architecture doc snippet | KV / prefill pressure |
| P4 | Debug: “This function returns None on empty input — fix it.” + 30-line snippet | Router classifier |

### 2.2 Modes (all four, each with P1 and P2 minimum)

| Mode | Config reminder | Min acceptance |
|------|-----------------|----------------|
| `flat` | Full deployed swarm | All agents return; no hung stream |
| `pipeline` | Default roster order | Stages complete; `final` non-empty |
| `cascade` | `synthesizer` set | `final` non-empty; note `meta.excluded` |
| `router` | `max_select` from coordinator | ≤ max_select agents; sensible picks on P4 |

### 2.3 Endpoints to watch

Map from current `swarm-config.json` `server_group` / model path:

| endpoint_id | Typical agents | Notes |
|-------------|------------------|-------|
| `llama8b` | database, foreman, frontend, synthesis, tester | Highest slot count (5) |
| `coder7b` | architect, debugger, optimizer, programmer | ctx_cap 6144 ÷ 4 slots |
| `gemma9b` | reviewer, security | 2 slots |
| `gemma2b` | scout | 1 slot |
| `mlx1b` | mlx-scout | Serialized; watch Metal OOM |

---

## 3. Gate thresholds

### 3.1 KV pressure (primary gate)

Aligned with `kv_auto_clear.h` defaults:

| Status | Endpoint `usage` | Sprint action |
|--------|------------------|---------------|
| **PASS** | &lt; 0.60 peak during nominal workload | Eligible to advance |
| **WARN** | 0.60 – 0.74 peak | Tune tokens / quant; re-run; document in SCALE-N.md |
| **FAIL** | ≥ 0.75 sustained (≥ 3 consecutive probes) | **Do not advance**; reduce agents, slots, or ctx |

Probe:

```bash
curl -s http://127.0.0.1:8000/api/pressure | jq '.[] | {port, names, usage}'
```

### 3.2 Stability gates

| Check | FAIL if |
|-------|---------|
| OOM | Any llama/MLX process exit or coordinator OOM log |
| MLX lane | Concurrent mlx-scout requests (should be serialized) |
| Hung SSE | Stream open &gt; 2× `MATRIX_CASCADE_AGENT_DEADLINE_SECS` |
| Cascade exclude rate | &gt; 50% agents in `meta.excluded` on P1/P2 |
| Synthesis empty | `final` null in cascade on P1 or P2 |

### 3.3 Speed budgets (M3 Max 36 GB — adjust per hardware profile)

| Metric | SCALE-1–3 | SCALE-4–7 |
|--------|-----------|-----------|
| p95 TTFT flat (P1) | ≤ 8s | ≤ 12s |
| p95 full flat (P1) | ≤ 90s | ≤ 120s |
| p95 cascade `final` (P2) | ≤ 120s | ≤ 150s |
| Router (P4) agent count | ≤ `max_select` | ≤ `max_select` |

Log actuals in sprint file even when PASS.

### 3.4 Cost logging (required fields)

Per run, record in SCALE-N.md:

- `mode`, `prompt_id`
- `meta.kv_pressure` (if present)
- Approx input tokens (chars ÷ 4)
- Sum of output tokens per agent (or `wc` on JSON export)
- Wall clock total

---

## 4. Sprint progression

Baseline assumption: start from a **reduced profile** (e.g. 7 agents) and add
one agent per sprint until full 13-agent roster (or hardware limit).

| Sprint | Target | Example addition |
|--------|--------|------------------|
| SCALE-0 | Baseline inventory | Document current roster + pressure at idle |
| SCALE-1 | +1 agent | e.g. add `security` |
| SCALE-2 | +1 agent | e.g. add `optimizer` |
| SCALE-3 | +1 agent | |
| SCALE-4 | +1 agent | Mid-point tune: KV quant audit |
| SCALE-5 | +1 agent | |
| SCALE-6 | +1 agent | TurboQuant mlx pilot (if enabled) |
| SCALE-7 | Full roster | All 13 agents; all modes; sign-off |

If already at 13 agents, SCALE-N = **load sprint** (raise `ctx_cap`, parallel,
or concurrent sessions) instead of adding agents. State which in SCALE-N.md.

---

## 5. Tuning playbook (on WARN/FAIL)

Apply in order; re-run nominal workload after each:

1. **Router default** — ensure not testing flat-only; use router for daily ops.
2. **Reduce `max_tokens`** on chatty agents.
3. **Lower `ctx_cap`** on shared server groups (increases per-slot KV if slots fixed — verify `ctx_cap ÷ slots`).
4. **Tighten `--cache-type-k`** (already q4_0/q8_0 in many agents).
5. **Enable / tune `auto_clear_kv`** — proactive at 0.60.
6. **Reduce `--parallel`** only if willing to trade throughput (fewer concurrent agents per model).
7. **Remove last-added agent** — rollback sprint.

---

## 6. Sprint log template

Create `docs/sprints/SCALE-N.md` per sprint:

```markdown
# SCALE-N — <title>

**Date:** YYYY-MM-DD  
**Hardware:** M3 Max 36 GB (or profile)  
**Roster:** N agents — <list>  
**Change:** +1 agent `<name>` | load increase: <desc>

## Configure snapshot

- swarm-config profile: default | 16gb | 32gb
- `MATRIX_CASCADE_AGENT_DEADLINE_SECS`:
- KV quant notes:

## Nominal workload results

| Mode | Prompt | Pass | Wall s | kv_pressure | Notes |
|------|--------|------|--------|-------------|-------|
| flat | P1 | | | | |
| … | | | | | |

## Pressure peaks

| endpoint / port | names | peak usage | PASS/WARN/FAIL |
|-----------------|-------|------------|----------------|

## Gate verdict

- [ ] All modes PASS
- [ ] KV peak &lt; 0.60 (or WARN documented with tune plan)
- [ ] No OOM / hung streams
- [ ] **Advance to SCALE-(N+1):** YES / NO

## Tuning applied

- …

## Token / cost notes

- …
```

---

## 7. Future: kvpool + slot-manager gates

When control plane splits:

| Today | Future probe |
|-------|--------------|
| `GET /api/pressure` | `GET http://slot-manager:PORT/v1/endpoints/pressure` |
| `kv_auto_clear` | `kvpool` policy events on ZMQ `swarm.kvpool.*` |
| Per-port semaphores | `slot-manager` acquire/release metrics |

Gate thresholds (**0.60 / 0.75**) remain unchanged; only probe URLs change.
Update this doc when `cofiswarm-slot-manager` lands.

---

## 8. CI hook (future `cofiswarm-e2e`)

```bash
# Pseudocode — integrate into cofiswarm-e2e
./tests/kv_pressure_gate.sh --max-usage 0.60 --probes 5 --interval 10
./tests/mode_smoke.sh --modes flat,pipeline,cascade,router --prompt P1
```

SCALE sprint **human sign-off** stays required until e2e covers full nominal workload.
