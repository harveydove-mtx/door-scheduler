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
| Web app | [app/](app): sign-in, MAT codes & rates, Products (Vite + React) |
| Firebase Data Connect | [dataconnect/](dataconnect): operations generated from `db/queries` |
| Firebase setup (one-off) | [docs/v2-firebase-setup.md](docs/v2-firebase-setup.md) |
| CI / deploy | [.github/workflows/](.github/workflows): `V2 checks` on every push; `V2 deploy` to the **V2** project only |

Tests (nothing here touches Firebase):

```bash
db/test.sh                      # database: needs PostgreSQL 15+ installed locally
dataconnect/test/run.sh         # Data Connect operations on the emulator (Cloud SQL-style roles)
node dataconnect/build-connector.mjs   # after changing db/queries
cd app && npm ci && npm test && npm run build
```

Run the app locally against the emulators (no real data):

```bash
# 1. a local Postgres built with db/migrate.sh (see dataconnect/test/run.sh for the role setup)
# 2. firebase emulators:start --only auth   and the Data Connect emulator pointed at that database
# 3. cd app && npm run dev   ->  http://127.0.0.1:5173
```
