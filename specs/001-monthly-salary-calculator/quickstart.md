# Quickstart: Flexible Monthly Salary Calculator

Validation guide — proves the feature works end-to-end. For full model/service
detail see [data-model.md](data-model.md), [contracts/api.md](contracts/api.md),
[contracts/cel.md](contracts/cel.md).

## Prerequisites

- Ruby 3.3+ (developed on 4.0.7) and Bundler
- Node 18+ and npm/yarn (Vue SPA dev server; developed on Node 24 LTS)
- Postman (to import `postman/salary_calculator.collection.json`)

## Setup

```bash
# 1. Backend (Rails 8.1 API)
cd backend
bundle install
ruby bin/rails db:prepare     # creates SQLite db + schema + seeds (AR & UY data)
ruby bin/rails server         # http://localhost:3000

# 2. Frontend (Vue 3 + Vite) — in a second terminal
cd frontend
npm install
npm run dev                   # http://localhost:5173
```

`ruby bin/rails …` works on Windows and macOS/Linux (on macOS/Linux the bare
executable `bin/rails …` also works; on Windows the `ruby` prefix is required).

`ruby bin/rails db:prepare` seeds: 4 employees (2 with mid-year salary changes),
Job history, and one AsignacionTemplate catalog whose formulas cover reference,
arithmetic, conditional/ternary, country-dependent, and subtotal-dependent
behavior across AR and UY (integer literals appear inside formulas; pure-literal
evaluation is covered by `cel_evaluator_spec.rb`). It also **prepares a pending
payroll run** (empty Liquidacion + one Asignacion per applicable item) for every
employee for every month in 2025-01..2026-12 — the stand-in for the upstream step
that owns run creation. Seeding is idempotent — safe to rerun.

> Re-seeding updates Jobs and templates and refreshes runs that are new or still
> **pending**, but does **not** rewrite already-calculated Liquidaciones (FR-009
> keeps history). After changing seeds or the catalog, recalculate the period —
> or `ruby bin/rails db:reset` for a clean slate — so stored totals reflect the
> new formulas.

## Run scenarios

1. **Health / API sanity**
   - `curl http://localhost:3000/api/v1/health` → `{"status":"ok"}`

2. **Pending runs (before calculating)**
   - `GET /api/v1/liquidaciones?period=2026-09` → rows exist with `"pending": true`
     and `null` totals; the UI shows `—`, never `$0.00`.

3. **Calculate payroll**
   - POST `/api/v1/liquidaciones/calculate`
     `{"employee_ids":[1,2,3,4],"period":"2026-09"}` (import the Postman
     collection and run "Calculate Payroll")
   - Expected: envelope with 4 `success` results (periods without a Job or
     broken conditions show `failure`, never wrong zeros). A period with no
     prepared run fails with `no_applicable_items`.

4. **Verifiable invariants**
   - `GET /api/v1/liquidaciones?period=2026-09` returns the same totals as a
     repeat POST: recalculation is idempotent (no duplicate rows).
   - `GET /api/v1/liquidaciones/:id` returns `final_salary_cents ==`
     `haberes_totales_cents - descuentos_totales_cents` and a full `items`
     breakdown grouped by category (haber/descuento/aporte).
   - Locale check: compare an **AR** employee vs a **UY** employee for the same
     period — discounts/aportes differ (country-dependent formula).

5. **Period binding**
   - An employee with Jobs changing in March: `period=2026-02` uses February's
     base salary; `period=2026-03` uses March's. January of a different year
     resolves that year's own conditions.

6. **Web interface**
   - Open `http://localhost:5173` → Employees page → select period →
     "Calculate" → results list → detail (totals + item breakdown).
     Meets SC-006 (detail within 2 clicks).

7. **Tests**
   - Backend: `cd backend && bundle exec rspec` (golden values, services,
     request specs — all green) and `bundle exec rubocop` (no offenses).
   - Frontend: `cd frontend && npm run test` (Vitest component flows).

## Expected outcomes (mapped to success criteria)

| Check | Meets |
|-------|-------|
| All seeded Liquidaciones match hand-computed golden values | SC-001 |
| Repeat calculation → identical totals | SC-002 |
| March/February/other-year differences follow Job history | SC-003 |
| 50-employee run visible in UI < 10 s | SC-004 |
| Explicit errors, no incorrect persisted values | SC-005 |
| Detail ≤ 2 clicks | SC-006 |
| Formula + subtotal test coverage green pre-merge | SC-007 |

## Documentation map

- Architecture: `docs/ARCHITECTURE.md` (repo root, implementation phase)
- API reference: `docs/API.md` plus `contracts/api.md`
- Postman: `postman/salary_calculator.collection.json` (import, set
  `baseUrl`)