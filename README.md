# Flex Salary Calculator

Flexible monthly salary/payroll calculation demo. Given a list of employees and
a `(year, month)` period, it computes each employee's **Liquidacion**
(haberes, descuentos, aportes, final_salary) from **CEL formulas stored in the
database** — including literal, reference, conditional, country-dependent, and
running-subtotal items — evaluates them in Ruby, persists results idempotently
with a per-item audit breakdown, and exposes them via a **REST API**, a **Vue 3
SPA**, and an importable **Postman collection**.

A payroll run is **prepared upstream** (an empty Liquidacion + one item per
applicable rule); the calculator evaluates the stored formulas, writes each
item's amount, and derives the totals from those rows.

- Money is always **integer cents** (`_cents`) — never floats.
- Each contract states its own **currency** (ISO 4217, like its base salary);
  amounts are minor units of it and the code is used for display only.
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
ruby bin/rails db:prepare   # creates SQLite db + schema + seeds
ruby bin/rails server       # http://localhost:3000

# Frontend (Vue SPA) — second terminal
cd frontend
npm install
npm run dev                 # http://localhost:5173
```

> **Windows:** always call binstubs through Ruby — `ruby bin/rails …`,
> `ruby bin/rake …`, `ruby bin/brakeman …`. Running a bare `bin/rails` makes
> Windows try to *open* the file (it's a Ruby shebang script, not an `.exe`) and
> pops up a "choose an app" dialog.
>
> **macOS/Linux:** the `ruby bin/rails …` form works too. You can also use
> `./bin/rails …` directly (the script is executable there).

`ruby bin/rails db:prepare` seeds 5 employees (three with multi-Job contract
histories), one country-aware item-formula catalog, and a **pending payroll run**
(empty Liquidacion + one item per applicable rule) for every employee for every
month in 2025-01..2026-12. The calculator then fills those runs — it never
creates the items itself. Seeding is idempotent — safe to rerun.

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

## Sample: inspect the core calculation (no server, no database)

`backend/scripts/sample_calculation.rb` is a small, self-contained program for
reading and understanding the salary core in action. It uses the **real**
`Employee` / `Job` / `AsignacionTemplate` / `Liquidacion` / `Asignacion` models
and the **real** `CalculateLiquidacion` service, driven by sample data defined
in the script itself.

- **No dev database, no `db:prepare`, no migrations, no seeds, no web server.**
  It spins up a throwaway **in-memory** SQLite just to back the ActiveRecord
  models; nothing is written to disk and it disappears when the script exits.
- **Minimal sample data** (edit it freely): one Argentina employee (Ana García,
  contract AR / ARS, base 120,000,000 cents = 1,200,000 ARS), one Uruguay
  employee (Camila Díaz, contract UY / UYU, 6,000,000 cents = 60,000 UYU), and
  one employee with a **contract history** (Elena Ríos: closed 2025-01..06 at
  80,000,000, closed 2025-07..12 at 90,000,000, open from 2026-01-01 at
  100,000,000) — approximate middle-class monthly gross salaries in the contract
  currency — plus the same 7-item country-aware formula catalog the app seeds
  (salario base, bono, aguinaldo, extra horas, descuento legal, descuento
  previsional, aporte empleador).
- The contract is **resolved by period** (`PeriodResolver`): a run for a past
  month uses the closed contract that covered it, so the printed job — and the
  totals — change with the requested period.
- It prepares the run first (an empty `Liquidacion` plus one `Asignacion` per
  catalog item — standing in for the upstream step that owns item creation), then
  calls `CalculateLiquidacion.call(employee_ids:, period:)`, and prints the
  persisted per-item audit breakdown and the totals for each employee.

### Usage

Run from the `backend/` directory, or just run the file from your IDE with the
working directory set to `backend/` (no other setup required):

```bash
cd backend
bundle exec ruby scripts/sample_calculation.rb            # period 2026-03
bundle exec ruby scripts/sample_calculation.rb 2026-06    # any YYYY-MM
```

The single argument is the period in `YYYY-MM` form; it defaults to `2026-03`.
Try `2026-06` (Extra horas activates) or `2026-12` (Aguinaldo activates) to see
the conditional formulas change the totals. Try `2025-09` to see Elena paid
under her **closed** 2025 contract (base 90,000,000, final 76,850,000) rather
than her open 2026 one.

### Sample output

```text
Salary calculation for period 2026-03
================================================================================================================
Ana García  (job: AR, currency ARS, base salary 120,000,000 cents, 2025-01-01..open)
----------------------------------------------------------------------------------------------------------------
  CATEGORY   ITEM                     FORMULA                                                        AMOUNT
  haber      Salario base             base_salary                                               120,000,000
  haber      Bono fijo                country == "AR" ? 5000000 : 250000                          5,000,000
  haber      Aguinaldo                period_month == 12 ? round(base_salary / 2) : 0                     0
  haber      Extra horas              period_month == 6 ? round(base_salary * 0.1) : 0                    0
  descuento  Descuento legal          round(base_salary * (country == "AR" ? 0.17 : 0.15))       20,400,000
  descuento  Descuento previsional    round(haberes_totales * 0.03)                               3,750,000
  aporte     Aporte empleador         round(base_salary * (country == "AR" ? 0.29 : 0.23))       34,800,000
----------------------------------------------------------------------------------------------------------------
  haberes_totales_cents                                       125,000,000
  descuentos_totales_cents                                     24,150,000
  aportes_totales_cents (employer-side)                        34,800,000
  final_salary_cents (haberes - descuentos)                   100,850,000

Camila Díaz  (job: UY, currency UYU, base salary 6,000,000 cents, 2025-01-01..open)
  ... (same breakdown; UY rates 15%/23% give final 5,162,500)

Elena Ríos  (job: AR, currency ARS, base salary 100,000,000 cents, 2026-01-01..open)
  ... (same breakdown; that open contract gives final 84,850,000)

All amounts are integer cents of the contract currency (ARS/UYU).
Data was in-memory only; nothing was persisted.
```

### Calling the core directly

The same entry point the API uses is a one-liner. In a console
(`cd backend && ruby bin/rails console`) against the seeded dev data:

```ruby
ids = Employee.pluck(:id)                              # or [1, 2, 3, 4]
results = CalculateLiquidacion.call(employee_ids: ids, period: "2026-03")

results[:results].each do |r|
  if r[:status] == "success"
    l = Liquidacion.find(r[:liquidacion][:id])
    puts "#{l.employee.name}: final #{l.final_salary_cents} cents"
  else
    puts "failed: #{r[:error][:code]} — #{r[:error][:detail]}"
  end
end
```

Inside `scripts/sample_calculation.rb` the in-memory sample handles
(`ana`, `camila`, `elena`) are available, so you can call
`CalculateLiquidacion.call(employee_ids: [ana.id, elena.id], period: "2025-09")`
directly.

Note: `CalculateLiquidacion` persists results, so the console call above writes
to the dev database. Use the sample script for an isolated, side-effect-free
run.

## Tests

```bash
# Backend — RSpec (golden values, services, models, request specs)
cd backend && bundle exec rspec

# Backend — static analysis
cd backend && bundle exec rubocop && ruby bin/brakeman -q

# Frontend — Vitest component flows
cd frontend && npm run test

# Full CI-equivalent check
cd backend && bundle exec rspec && bundle exec rubocop && ruby bin/brakeman -q && bundle exec bundler-audit check --update
cd frontend && npm run test
```

The backend suite asserts hand-computed golden values (never values derived
from the implementation). Coverage minimum is enforced by `.simplecov` during
`rspec`. For a high-level view of what each suite covers, see
[docs/TESTS.md](docs/TESTS.md).

## Postman

Import `postman/salary_calculator.collection.json`, set the `baseUrl` variable
(default `http://localhost:3000`), and use `period` to switch payroll months.
All 6 requests plus error examples are included.

## Documentation map

| Doc | Contents |
|-----|----------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, request flows, separation of concerns, seeds |
| [docs/API.md](docs/API.md) | Full REST contract: every endpoint, errors, failure codes |
| [docs/TESTS.md](docs/TESTS.md) | High-level test map (what each suite/area verifies) + how to regenerate |
| [docs/VALIDATION.md](docs/VALIDATION.md) | End-to-end quickstart outcomes vs SC-001..SC-007 |
| [backend/scripts/sample_calculation.rb](backend/scripts/sample_calculation.rb) | Runnable in-memory sample of the core calculation |
| [postman/salary_calculator.collection.json](postman/salary_calculator.collection.json) | Importable collection |
| `specs/001-monthly-salary-calculator/` | Spec, plan, data model, CEL contract, tasks |

## Status

Phase 1–6 complete: setup, models, domain services, REST API, Vue SPA,
documentation, CI, security/audit pass. Full test suites green (RSpec +
Vitest), RuboCop clean, Brakeman clean.