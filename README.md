# Flex Salary Calculator

Flexible monthly salary/payroll calculation demo. Given a list of employees and
a `(year, month)` period, it computes each employee's **Liquidacion**
(haberes, descuentos, aportes, final_salary) from **CEL formulas stored in the
database** — including literal, reference, conditional, country-dependent, and
running-subtotal items — evaluates them in Ruby, persists results idempotently
with a per-item audit breakdown, and exposes them via a **REST API**, a **Vue 3
SPA**, and an importable **Postman collection**.

- Money is always **integer cents** (`_cents`) — never floats.
- Recalculation is deterministic and idempotent per employee + period.
- Explicit errors, never silent/wrong zeros.

## Architecture

- **Backend**: Rails 8.1 API-only (`backend/`) — controllers/serializers, a
  small domain core of service objects, and a CEL evaluator wrapper (`cel` gem
  + `round`/`min`/`max` helpers).
- **Frontend**: Vue 3 + Vite + Pinia + vue-router + axios SPA (`frontend/`).
- **Storage**: local SQLite.
- See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component/flow details.

## Prerequisites

- Ruby 3.3+ with Bundler (this repo is developed/verified on Ruby 4.0.7)
- Node.js 18+ with npm
- (optional) Postman to import the collection

## Setup

```bash
# Backend (Rails API)
cd backend
bundle install
bin/rails db:prepare        # creates SQLite db + schema + seeds
bin/rails server            # http://localhost:3000

# Frontend (Vue SPA) — second terminal
cd frontend
npm install
npm run dev                 # http://localhost:5173
```

`bin/rails db:prepare` seeds 4 employees (2 with mid-year salary changes) and
AR/UY formula templates. Seeding is idempotent — safe to rerun.

### Alternative: run both with the Procfile

```bash
foreman start               # or: overmind start / honcho start
```

`Procfile`: `web` = Rails on `:3000`, `vite` = Vite on `:5173`.

## Run

1. Open `http://localhost:5173` → Employees page.
2. Pick a period (e.g. `2026-09`), click **Calculate**.
3. Click a result to see totals + per-item breakdown (haber/descuento/aporte),
   grouped and in evaluation order. Missing results show an explicit state.

Or drive the API directly — see [docs/API.md](docs/API.md) and the quickstart
scenarios in [docs/VALIDATION.md](docs/VALIDATION.md):

```bash
curl http://localhost:3000/api/v1/health
curl -X POST http://localhost:3000/api/v1/liquidaciones/calculate \
  -H "Content-Type: application/json" \
  -d '{"employee_ids":[1,2,3,4],"period":"2026-09"}'
curl "http://localhost:3000/api/v1/liquidaciones?period=2026-09"
```

## Tests

```bash
# Backend — RSpec (golden values, services, models, request specs)
cd backend && bundle exec rspec

# Backend — static analysis
cd backend && bundle exec rubocop && bin/brakeman -q

# Frontend — Vitest component flows
cd frontend && npm run test

# Full CI-equivalent check
cd backend && bundle exec rspec && bundle exec rubocop && bin/brakeman -q && bundle exec bundler-audit check --update
cd frontend && npm run test
```

The backend suite asserts hand-computed golden values (never values derived
from the implementation). Coverage minimum is enforced by `.simplecov` during
`rspec`.

## Postman

Import `postman/salary_calculator.collection.json`, set the `baseUrl` variable
(default `http://localhost:3000`), and use `period` to switch payroll months.
All 6 requests plus error examples are included.

## Documentation map

| Doc | Contents |
|-----|----------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, request flows, separation of concerns, seeds |
| [docs/API.md](docs/API.md) | Full REST contract: every endpoint, errors, failure codes |
| [docs/VALIDATION.md](docs/VALIDATION.md) | End-to-end quickstart outcomes vs SC-001..SC-007 |
| [postman/salary_calculator.collection.json](postman/salary_calculator.collection.json) | Importable collection |
| `specs/001-monthly-salary-calculator/` | Spec, plan, data model, CEL contract, tasks |

## Status

Phase 1–6 complete: setup, models, domain services, REST API, Vue SPA,
documentation, CI, security/audit pass. Full test suites green (RSpec +
Vitest), RuboCop clean, Brakeman clean.