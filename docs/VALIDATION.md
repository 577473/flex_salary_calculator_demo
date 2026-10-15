# Validation — end-to-end quickstart outcomes

Executed against the running local stack:
backend Rails 8.1 on `http://localhost:3000` (SQLite dev DB,
`ruby bin/rails db:seed` idempotent baseline), frontend Vue 3/Vite on
`http://localhost:5173`. Each scenario below maps to the quickstart steps and
the success criteria from `specs/001-monthly-salary-calculator/spec.md`.

## Scenario results

| # | Scenario | Result | Evidence |
|---|----------|--------|----------|
| 1 | Health / API sanity | PASS | `GET /api/v1/health` → `{"status":"ok"}` |
| 2 | Pending runs (before calculating) | PASS | `GET /liquidaciones?period=2026-09` → rows with `"pending":true` and `null` totals; UI renders `—`, no `$0.00` |
| 3 | Calculate payroll (`2026-09`, ids 1–4) | PASS | Envelope: 4× `success`, URLs `/api/v1/liquidaciones/1..4` |
| 4 | Verifiable invariants | PASS | See below (golden values, idempotency, final = haberes − descuentos, AR≠UY) |
| 5 | Period binding | PASS | June vs July follow the 2026-07 raise; out-of-range year → `no_job_for_period` |
| 6 | Web interface | PASS | US2 validation: Employees → Calculate → Detail in ≤ 2 clicks (SC-006) |
| 7 | Tests | PASS | RSpec 137/0, Vitest 13/13 (SC-007); see “Suites” |

Runs are **prepared** by the upstream step (here: `db:seed`, which creates an
empty Liquidacion + one Asignacion per applicable item for every employee and
every month in 2025-01..2026-12). The calculator fills those rows; it never
creates items.

## SC-001 — seeded liquidaciones match hand-computed golden values

Hand-computed (integer cents, no derivation from the implementation) vs the
live API for the seeded employees, period `2026-09`:

| Employee | Country | Source | haberes | descuentos | aportes | final |
|----------|---------|--------|---------|------------|---------|-------|
| Ana García | AR | hand-computed | 125,000,000 | 24,150,000 | 34,800,000 | 100,850,000 |
| Ana García | AR | `GET /liquidaciones/1` | 125,000,000 | 24,150,000 | 34,800,000 | 100,850,000 |
| Camila Díaz | UY | hand-computed | 6,250,000 | 1,087,500 | 1,380,000 | 5,162,500 |
| Camila Díaz | UY | `GET /liquidaciones/3` | 6,250,000 | 1,087,500 | 1,380,000 | 5,162,500 |

AR vs UY discount/aporte rates differ (17%/29% vs 15%/23%) — country-dependent
formula verified. The golden reference for all fixtures also lives as a spec
(`backend/spec/golden/demo_calculation_spec.rb`).

Hand-computed detail (Ana AR): salario 120,000,000 + bono 5,000,000 → haberes
125,000,000; `round(120,000,000·0.17)` = 20,400,000 + `round(125,000,000·0.03)` =
3,750,000 → descuentos 24,150,000; aporte `round(120,000,000·0.29)` = 34,800,000;
final = 125,000,000 − 24,150,000 = **100,850,000**.

## SC-002 — repeat calculation → identical totals, no duplicates

- Repeat POST for `2026-09` → list returns exactly **4** rows (unique
  `[employee_id, period_year, period_month]`); Ana still
  haberes **125,000,000** / final **100,850,000** — byte-identical.

## SC-003 — period differences follow Job history

Bruno Sosa (AR), raise 100,000,000 → 110,000,000 effective
`2026-07-01`:

| Period | Job base | haberes | descuentos | aportes | final |
|--------|----------|---------|------------|---------|-------|
| 2026-06 | 100,000,000 (+ Extra horas) | 115,000,000 | 20,450,000 | 29,000,000 | **94,550,000** |
| 2026-07 | 110,000,000 | 115,000,000 | 22,150,000 | 31,900,000 | **92,850,000** |

Both match hand-computed values. Year binding: `period=2024-09` for Ana (job
effective from 2025-01-01) → **`no_job_for_period`** (SC-005), never wrong
zeros.

## SC-004 — 50-employee run < 10 s

Created 50 synthetic AR employees + jobs in the dev DB and measured the HTTP
`POST /liquidaciones/calculate` for all 50 (`2026-09`):

- **elapsed: 3,236 ms** (well under the 10 s budget), **50/50 success**,
  0 failures. Benchmark records removed afterwards (DB back to the 4 seeded
  employees).

## SC-005 — explicit errors, no incorrect persisted values

| Call | HTTP | Envelope body |
|------|------|---------------|
| POST no `employee_ids` | 400 | problem+json `{"errors":[...]}`, `employee_ids is required` |
| POST `period=2026-13` | 400 | problem+json, month outside 01–12 |
| POST ids `[9999,10000]` | 422 | problem+json, none of the requested employees exist |
| POST Ana `2024-09` | 200 | envelope failure `error.code=no_job_for_period` |
| GET `/liquidaciones/99999` | 404 | problem+json |

A failing employee writes **no** amounts or totals. For a period with no
prepared run (e.g. Ana `2024-09`) there are 0 Liquidacion rows and the failure
code is `no_job_for_period`; when a run was prepared but an item fails, the run
is rolled back and stays **pending** (`amount_cents` and totals `null`).
Partial-success batches leave the successful employees calculated and uniquely
re-calculable.

## SC-006 — detail within 2 clicks

SPA click path: **Employees page → “Calcular” (with period) → payroll list →
click result → detail** = 2 clicks. Detail shows totals + per-item breakdown
grouped haber → descuento → aporte and an explicit “pending” / “not calculated”
state (no fake zeros; null amounts render as `—`). Covered by
`frontend/tests/views/payroll_list.spec.js` and `liquidacion_detail.spec.js` plus
the US2 manual pass.

## SC-007 — formula + subtotal test coverage green pre-merge

Every formula type in the CEL contract is covered with golden values
(`cel_evaluator_spec.rb`, `demo_calculation_spec.rb`, service + request specs):
literal, reference, arithmetic, conditional/ternary, country-dependent, and
running-subtotal (`haberes_totales`) expressions; plus idempotency, partial
failure, and error codes. Full suites below.

## Suites (final verification run)

| Check | Result |
|-------|--------|
| `backend` `bundle exec rspec` | 137 examples, 0 failures |
| SimpleCov minimum coverage (line 90 / branch 78) | 95.83% / 85.50% → pass |
| `backend` `bundle exec rubocop` | no offenses |
| `backend` `bin/brakeman -q` | 0 warnings |
| `backend` `bundle exec bundler-audit check --update` | 0 vulnerabilities |
| `frontend` `npm run test` | 13/13 passed |
| `frontend` `npm run build` | builds successfully |

## Reproducing

See `README.md` (setup) and `specs/001-monthly-salary-calculator/quickstart.md`.
The Postman collection (`postman/salary_calculator.collection.json`) drives
scenarios 1–4 with the `baseUrl` variable set.