# cofiswarm-e2e

Cofiswarm component: `e2e`.

- Layout: [REPO-STANDARD-LAYOUT](https://github.com/keepdevops/cofiswarmdev/blob/main/docs/REPO-STANDARD-LAYOUT.md)
- Migration: [MIGRATION-SPRINTS](https://github.com/keepdevops/cofiswarmdev/blob/main/docs/MIGRATION-SPRINTS.md)

## FHS paths

| Path | Purpose |
|------|---------|
| `/etc/cofiswarm/e2e/` | config |
| `/var/lib/cofiswarm/e2e/` | state |
| `/var/log/cofiswarm/e2e/` | logs |

## Test

```bash
./test/scripts/assert-layout.sh e2e
```
