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

Run the database tests (needs PostgreSQL 15+ installed locally; no Firebase involved):

```bash
db/test.sh
```
