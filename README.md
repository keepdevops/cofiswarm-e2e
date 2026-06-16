# cofiswarm-e2e

Cross-repo gates, SCALE sprint checklists, UI chaos tests, and C++ legacy test corpus.

```bash
make test              # layout + artifact gate
make smoke             # live health probes (COFISWARM_E2E_LIVE=1)
```

Artifacts: `test/gates/SCALE-GATES.md`, `test/ui-chaos/`, `test/cpp-legacy/`.
