# Architecture — Flex Salary Calculator

## System overview

Todo produce monthly payroll: a list of employees + one `(year, month)` period
in, per-employee `Liquidacion` records out (haberes, descuentos, aportes,
final_salary) with a persistent per-item audit breakdown. Formulas live in the
database and are evaluated with a CEL evaluator; results are exposed through a
REST API consumed by a Vue SPA and a Postman collection.

```text
 +----------------+    HTTP     +---------------------------+   SQLite
 |  Vue 3 SPA     | ----------> |  Rails 8.1 API (api/v1)   | <--------> db/production.sqlite3
 |  Vite :5173    |   JSON      |  controllers/serializers  |
 +----------------+             +------------+--------------+   ^
       ^                                    |                     |
       | reads                             v                     |
       +--------------------------- CEL evaluator (cel gem)      |
                                    + services, SQL           /  |
                                    +-------------------------/   |
```

No background jobs, no external services, no network dependencies at runtime.
Everything runs locally on the developer machine.

## Components

### 1. Rails 8.1 API-only backend (`backend/`)

- Controllers (`app/controllers/api/v1/`) — thin HTTP layer:
  - `employees_controller.rb` — index / show.
  - `liquidaciones_controller.rb#index` — list by required `period` (optional
    `employee_id`), `#show` detail with grouped items, `#calculate` —
    triggers payroll.
  - `Api::BaseController` — problem+json error envelope (`400`/`404`/`422`),
    `request_id` tagging, CORS.
- Serializers (`app/serializers/`) — money as integer `_cents` fields:
  - `employee_serializer.rb`, `liquidacion_serializer.rb`,
    `envelope_serializer.rb` (stable per-employee failure codes).
- Models (`app/models/`): `Employee`, `Job` (time-effective contract
  conditions), `AsignacionTemplate` (country + category + effective-range rule
  with a CEL formula), `Liquidacion` (unique per employee+period, totals),
  `Asignacion` (per-item audit snapshot: formula, version, amount, category).
- Services (`app/services/`) — the domain core, tested in isolation:
  - `period_resolver.rb` — pick the unique Job covering `(employee, year, month)`
    (`nil` = no contract → `no_job_for_period`).
  - `item_selector.rb` — filter templates by country + effective range,
    ordered `haber → descuento → aporte` then `position`.
  - `cel_evaluator.rb` — wrap the `cel` gem; compile/check/evaluate each
    formula; `round`/`min`/`max` extensions; enforce integer money result;
    cache compiled expressions by formula text.
  - `calculate_liquidacion.rb` — orchestrate: resolve job, select items, bind
    variables (`name`, `country`, `base_salary`, `period_year`,
    `period_month`; running `haberes_totales` / `descuentos_totales` /
    `aportes_totales`), evaluate in category order, **upsert** the Liquidacion
    (unique employee+period) + rebuild Asignacion snapshots in one transaction,
    return the per-employee envelope.

### 2. CEL evaluator wrapper

Domain-critical. Exposes a tiny, auditable surface over `cel`:

- `Cel::Environment.new(declarations: {}, extensions: { salary: SalaryHelpers })`
  — no globals; only the fixed binding set the calculator provides.
- Helpers: `round(value, digits=0)`, `min(...)`, `max(...)`.
- Result policy: money amounts must be integers after `round`; a formula that
  yields a non-integer amount for a money field is a `formula_error`, never a
  silent truncation.
- Error classification: parse/check failures → `formula_invalid`; evaluation
  failures (division by zero, missing binding, non-integer money) →
  `formula_error`.

### 3. Vue 3 + Vite SPA (`frontend/`)

- `src/services/api.js` — axios client rooted at `VITE_API_URL`
  (`http://localhost:3000`), thin methods per endpoint; error mapping in
  `src/services/error.js`.
- `src/stores/payroll.js` — Pinia store: period, employees, results
  (success/`failure` with codes), list, detail.
- `src/views/` — `EmployeesView`, `PayrollView` (period form + calculate +
  results list), `LiquidacionDetailView` (totals + grouped per-item breakdown;
  explicit "not calculated" state, no fake zeros).
- `src/router/index.js` — `/`, `/payroll`, `/payroll/:id`.
- `src/utils/money.js` — `es-AR` integer-cent formatting.

### 4. SQLite storage

File-backed `backend/storage/` (Rails 8 default) / `backend/db/`. Four core
tables + `asignaciones` snapshot table. See `data-model.md` for the ERD and the
unique `[employee_id, period_year, period_month]` index that makes
recalculation idempotent.

### 5. Postman collection (`postman/`)

Importable v2.1.0 collection (6 requests + error examples) grounded in
`contracts/api.md`. Variable `baseUrl` (default `http://localhost:3000`),
`period` for switching payroll months.

## Request flows

### Calculate payroll (write path)

```text
POST /api/v1/liquidaciones/calculate {"employee_ids":[...], "period":"YYYY-MM"}
  │
  ├─ BaseController: validate params → 400/422 problem+json on request-level errors
  │
  ├─#calculate: per-employee/period validation
  │
  ├─ CalculateLiquidacion.call(employee_ids, period)
  │     for each employee:
  │       period_resolver.resolve(employee, period)      → nil? no_job_for_period
  │       item_selector.select(employee.country, period) → empty? no_applicable_items
  │       for each item (haber→descuento→aporte, position):
  │         cel_evaluator.evaluate(formula, bindings, running_subtotals)
  │             → formula_invalid | formula_error | amount_cents
  │       upsert Liquidacion + rebuild Asignaciones (one transaction)
  │
  └─ EnvelopeSerializer.envelope(results)
       { results: [ { employee_id, status: success,
                      liquidacion: { url } } | { employee_id, status: failure,
                      error: { code, detail } } ] }
```

Failures are per-employee: one broken employee never blocks the batch
(FR-014), and a failing item aborts that employee's Liquidacion with **no**
partial record persisted (FR-008).

### Fetch results (read path)

```text
GET /api/v1/liquidaciones?period=2026-09
  → LiquidacionesController#index
    → joins employees (includes, no N+1)
    → LiquidacionSerializer.list  (totals in _cents)

GET /api/v1/liquidaciones/1
  → #show (includes employee + asignaciones)
  → Asignaciones grouped haber → descuento → aporte in evaluation order
  → LiquidacionSerializer.show (totals + items + formula_version per item)
```

## Separation of concerns

| Concern             | Owner                                          |
|---------------------|------------------------------------------------|
| HTTP + validation   | `Api::BaseController`, `api/v1/*` controllers |
| Presentation shape  | `app/serializers/*` (money = integer `_cents`) |
| Domain orchestration| `CalculateLiquidacion`                          |
| Contract resolution | `PeriodResolver`, `ItemSelector`               |
| Formula evaluation  | `CelEvaluator` (cel gem, whitelisted helpers)  |
| Persistence/audit   | Models + migrations; snapshot `Asignacion` rows|
| Client state & UI   | Pinia store, `views/*`, `services/api.js`      |

Rules: controllers pass through to services; services never render JSON;
serializers never compute money; formulas are data (CEL), never code.

## Seeds overview (`backend/db/seeds.rb`, idempotent)

4 employees (synthetic names — no real-person PII), 2 countries, 14 templates:

- `Ana García` (AR, 1,200,000) — single job from 2025-01-01.
- `Bruno Sosa` (AR, 1,000,000 → 1,100,000) — mid-year raise at 2026-07-01.
- `Camila Díaz` (UY, 900,000) — single job.
- `Diego Araújo` (UY, 800,000 → 850,000) — mid-year raise at 2026-07-01.

Template catalog (same set for AR and UY; country gates inside formulas):

| Description        | Category  | Formula |
|--------------------|-----------|---------|
| Salario base       | haber     | `base_salary` |
| Bono fijo          | haber     | `25000` |
| Aguinaldo          | haber     | `period_month == 12 ? round(base_salary / 2) : 0` |
| Extra horas        | haber     | `period_month == 6 ? round(base_salary * 0.1) : 0` |
| Descuento legal    | descuento | `round(base_salary * (country == "AR" ? 0.17 : 0.15))` |
| Descuento previsional | descuento | `round(haberes_totales * 0.03)` |
| Aporte empleador   | aporte    | `round(base_salary * (country == "AR" ? 0.29 : 0.23))` |

The catalog exercises every formula type in `contracts/cel.md`: literal,
reference, arithmetic, conditional/ternary, country-dependent, and
subtotal-dependent (`haberes_totales`) expressions, plus `round`.

## Consistency & invariants

- Money: integer cents only; no floats cross the API or storage boundary
  (enforced by the evaluator, serializers, and request specs).
- Idempotency: unique `[employee_id, period_year, period_month]` + upsert, so
  repeat calculation yields identical totals and no duplicate rows (SC-002).
- Persisted audit trail: each `Asignacion` snapshot stores `formula`,
  `formula_version`, category and amount — the UI and API detail render from
  this trail, not from recomputation (FR-009).
- Determinism: a given (employee, period) always produces the same Liquidacion
  (SC-002), validated by golden-value specs.