# Validation — end-to-end quickstart outcomes

Executed against the running local stack:
backend Rails 8.1 on `http://localhost:3000` (SQLite dev DB,
`bin/rails db:seed` idempotent baseline), frontend Vue 3/Vite on
`http://localhost:5173`. Each scenario below maps to the quickstart steps and
the success criteria from `specs/001-monthly-salary-calculator/spec.md`.

## Scenario results

| # | Scenario | Result | Evidence |
|---|----------|--------|----------|
| 1 | Health / API sanity | PASS | `GET /api/v1/health` → `{"status":"ok"}` |
| 2 | Calculate payroll (`2026-09`, ids 1–4) | PASS | Envelope: 4× `success`, URLs `/api/v1/liquidaciones/1..4` |
| 3 | Verifiable invariants | PASS | See below (golden values, idempotency, final = haberes − descuentos, AR≠UY) |
| 4 | Period binding | PASS | June vs July follow the 2026-07 raise; out-of-range year → `no_job_for_period` |
| 5 | Web interface | PASS | US2 validation: Employees → Calculate → Detail in ≤ 2 clicks (SC-006) |
| 6 | Tests | PASS | RSpec 125/0, Vitest 7/7 (SC-007); see “Suites” |

## SC-001 — seeded liquidaciones match hand-computed golden values

Hand-computed (integer cents, no derivation from the implementation) vs the
live API for the seeded employees, period `2026-09`:

| Employee | Country | Source | haberes | descuentos | aportes | final |
|----------|---------|--------|---------|------------|---------|-------|
| Ana García | AR | hand-computed | 1,225,000 | 240,750 | 348,000 | 984,250 |
| Ana García | AR | `GET /liquidaciones/1` | 1,225,000 | 240,750 | 348,000 | 984,250 |
| Camila Díaz | UY | hand-computed | 925,000 | 162,750 | 207,000 | 762,250 |
| Camila Díaz | UY | `GET /liquidaciones/3` | 925,000 | 162,750 | 207,000 | 762,250 |

AR vs UY discount/aporte rates differ (17%/29% vs 15%/23%) — country-dependent
formula verified. The golden reference for all fixtures also lives as a spec
(`backend/spec/golden/demo_calculation_spec.rb`).

Hand-computed detail (Ana AR): salario 1,200,000 + bono 25,000 → haberes
1,225,000; `round(1,200,000·0.17)` = 204,000 + `round(1,225,000·0.03)` = 36,750 →
descuentos 240,750; aporte `round(1,200,000·0.29)` = 348,000; final = 1,225,000 −
240,750 = **984,250**.

## SC-002 — repeat calculation → identical totals, no duplicates

- Repeat POST for `2026-09` → list returns exactly **4** rows (unique
  `[employee_id, period_year, period_month]`); Ana still
  haberes **1,225,000** / final **984,250** — byte-identical.

## SC-003 — period differences follow Job history

Bruno Sosa (AR), raise 1,000,000 → 1,100,000 effective
`2026-07-01`:

| Period | Job base | haberes | descuentos | aportes | final |
|--------|----------|---------|------------|---------|-------|
| 2026-06 | 1,000,000 (+ Extra horas) | 1,125,000 | 203,750 | 290,000 | **921,250** |
| 2026-07 | 1,100,000 | 1,125,000 | 220,750 | 319,000 | **904,250** |

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

A failing employee persists **no** Liquidacion row (checked: 0 rows for Ana
`2024-09`). Partial-success batches leave the successful employees persisted
and uniquely re-calculable.

## SC-006 — detail within 2 clicks

SPA click path: **Employees page → “Calcular” (with period) → payroll list →
click result → detail** = 2 clicks. Detail shows totals + per-item breakdown
grouped haber → descuento → aporte and an explicit “not calculated” state
(no fake zeros). Covered by `frontend/tests/views/payroll_list.spec.js` and
`liquidacion_detail.spec.js` plus the US2 manual pass.

## SC-007 — formula + subtotal test coverage green pre-merge

Every formula type in the CEL contract is covered with golden values
(`cel_evaluator_spec.rb`, `demo_calculation_spec.rb`, service + request specs):
literal, reference, arithmetic, conditional/ternary, country-dependent, and
running-subtotal (`haberes_totales`) expressions; plus idempotency, partial
failure, and error codes. Full suites below.

## Suites (final verification run)

| Check | Result |
|-------|--------|
| `backend` `bundle exec rspec` | 125 examples, 0 failures |
| SimpleCov minimum coverage (line 90 / branch 78) | 95.80% / 84.12% → pass |
| `backend` `bundle exec rubocop` | no offenses |
| `backend` `bin/brakeman -q` | 0 warnings |
| `backend` `bundle exec bundler-audit check --update` | 0 vulnerabilities |
| `frontend` `npm run test` | 7/7 passed |
| `frontend` `npm run build` | builds successfully |

## Reproducing

See `README.md` (setup) and `specs/001-monthly-salary-calculator/quickstart.md`.
The Postman collection (`postman/salary_calculator.collection.json`) drives
scenarios 1–4 with the `baseUrl` variable set.