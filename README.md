# door-scheduler
Matrix Hardware Door Scheduler

## V1 (live)
`index.html`: the current single-file app (v25.5). Unchanged until V2 cutover.

## V2 (in development)
| | |
|---|---|
| What it must do | [docs/v2-functional-spec.md](docs/v2-functional-spec.md) |
| Database design | [docs/v2-data-model.md](docs/v2-data-model.md) |
| SQL (Postgres) | [db/](db): migrations, seed, queries, tests |
| Pricing engine | [app/src/domain/](app/src/domain): pure TypeScript, tested against the V1 code in `index.html` |

Tests (nothing here touches Firebase):

```bash
db/test.sh                      # database: needs PostgreSQL 15+ installed locally
cd app && npm ci && npm test    # pricing engine
npm run typecheck
```
