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

## Why (root cause — traced in source, then tested)

8 sessions × broadcast to the 9-agent `:8082` group (a **Qwen2.5-14B** server) = ~72
simultaneous connections against **9 continuous-batching slots**. Tracing the
"not responding" string to its source: `agent_stream_llama.h` fires it when `cli.Post`
returns `!res` (no HTTP response object — connect failed/refused/reset, not an error status).

**Hypothesis (tested):** the client's connection timeout. The coordinator's per-agent HTTP
client hardcoded `set_connection_timeout(5)` (`agent_stream_pool.cpp`). I made it env-driven
(`MATRIX_AGENT_CONNECT_TIMEOUT_SECS`), rebuilt + redeployed the coordinator, and retried at
**5 → 30 s**:

| connect timeout | sessions with real output | endpoint not-ok samples |
|-----------------|---------------------------|-------------------------|
| 5 s (baseline)  | 4 / 8 | 1 |
| 30 s            | 3 / 8 | 0 |

**Raising it did not help** (3–4/8 either way; within noise). So the connection is **not
timing out** — `endpoint not-ok = 0` means the servers stayed up the whole run. **llama-server
is refusing/resetting connections** under ~72 concurrent requests against 9 slots: the HTTP
accept layer / slot queue saturates and drops excess connections.

**Second test — llama-server `--threads-http`:** relaunched both llama-servers with
`--threads-http 128` (default is -1 ≈ cores−1 ≈ 13, far below ~72 concurrent streams) and
retried 8×: **also 3/8** — no improvement. So the HTTP accept-thread count isn't the limiter
either.

| change | sessions with real output |
|--------|---------------------------|
| baseline (connect 5 s, threads-http auto) | 4 / 8 |
| connect timeout 30 s | 3 / 8 |
| `--threads-http 128` | 3 / 8 |

**Ruled out (all tested):** client connect timeout, HTTP accept threads, per-agent read
timeout (510 s), "deadline" (no env), KV pressure (~0.16).

**Localization:** all 8 sessions *are* served by the coordinator (each gets a stream); the
excess concurrent **per-agent streams fail at TCP connect** to llama-server (`cli.Post`→`!res`)
beyond ~3–4 sessions' worth. This is a **connection-level limit on the llama-server side**
(listen backlog / internal task-queue rejection) that neither the client timeout nor the HTTP
thread count moves. Pinpointing it needs llama-server-side investigation (socket backlog,
request-queue behavior, `ulimit -n`), not coordinator black-box tuning.

**Remaining lever:** `--parallel` (more actual slots) — but OOM-bound on the 14B `:8082`
group at ~12 GB free. Otherwise the practical answer is **cap concurrency at ~4**.

## Gate verdict

- [x] KV peak 0.165 < 0.60 — **PASS** (KV gate)
- [ ] Stability (§3.2): **FAIL** — 50% of sessions had agents not responding (slot starvation)
- [ ] **Advance to SCALE-3:** **NO** at this concurrency — clean ceiling is **~4 sessions**
      (SCALE-1 passed clean; 8 degrades).

## Tuning playbook (to push past the ceiling)

Runtime-only (no rebuild):

1. **Cap concurrent sessions to ~4** — the proven clean ceiling at the current build.

Tested and **did not help** (kept for the record):

2. ~~Raise the connection timeout~~ — `set_connection_timeout` made env-driven
   (`MATRIX_AGENT_CONNECT_TIMEOUT_SECS`), coordinator rebuilt/redeployed, retried at 30 s:
   no change (3–4/8). The failure is connection *refusal*, not a timeout.
3. ~~llama-server `--threads-http`~~ — relaunched both servers with `--threads-http 128`
   (default ≈ 13), retried 8×: no change (3/8). HTTP accept-thread count isn't the limiter.

Remaining / next:

4. **Raise `--parallel`** (more real slots) in `proxy_configure_spawn_args.h` — the only lever
   left, but OOM-bound on the 14B `:8082` group at ~12 GB free.
5. **llama-server-side investigation** — socket listen backlog, internal request-queue
   rejection, `ulimit -n`. The `!res` is TCP-level, below the coordinator; needs profiling
   the llama-server, not more coordinator/proxy knobs.
6. **Pragmatic:** cap concurrency at ~4 (the proven clean ceiling).

### Build is reproducible

The proxy/coordinator build is `scripts/yyyyy/build_cpp_binaries.sh` (direct `c++`, not the
CMake module). Its `ROOT=$(dirname $0)/..` mis-resolves from its nested path; run a copy one
level under `yyyyy/` so `ROOT=…/yyyyy` (cpp_core lives there), outputs to `yyyyy/{coordinator,
proxy}`, then copy over the top-level binary. Verified: rebuild is byte-size-identical to the
deployed binary (default flags, no `MATRIX_MLX_NATIVE_COORD`/`INPROC`).

Then re-run `make scale-gate` + this load; target all sessions returning output.

## Notes

- vs SCALE-1 (4 sessions: clean, peak 0.43 on mlx): doubling to 8 sessions **lowered**
  observed mlx peak (it dropped to not-ok / starved) and broke half the sessions — a
  contention cliff, not a gradual KV climb.
- Headroom insight: KV at 0.16 means slots, not memory, gate concurrency here — so the
  productive next lever is `--parallel`, not reducing `ctx`/tokens.
