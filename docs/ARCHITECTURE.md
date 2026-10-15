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
  conditions), `AsignacionTemplate` (category + effective-range rule with a CEL
  formula that may read the bound `country`), `Liquidacion` (unique per
  employee+period; totals are nullable until calculated → `pending?`),
  `Asignacion` (per-item line: created with formula/version/category/position,
  `amount_cents` filled in by the calculator → `calculated?`).
- Services (`app/services/`) — the domain core, tested in isolation:
  - `period_resolver.rb` — pick the unique Job covering `(employee, year, month)`
    (`nil` = no contract → `no_job_for_period`).
  - `item_selector.rb` — filter templates by effective range,
    ordered `haber → descuento → aporte` then `effective_from`/`id`. Retained as
    the selection rule; used by the seeds as the **upstream stand-in**, not by
    the calculator.
  - `cel_evaluator.rb` — wrap the `cel` gem; compile/check/evaluate each
    formula; `round`/`min`/`max` extensions; enforce integer money result;
    cache compiled expressions by formula text.
  - `calculate_liquidacion.rb` — orchestrate: **find the already-prepared
    Liquidacion + its Asignacion rows** (empty ⇒ `no_applicable_items`), resolve
    job, refuse unsupported jurisdictions, bind variables (`name`, `country`,
    `base_salary`, `period_year`, `period_month`; running `haberes_totales` /
    `descuentos_totales` / `aportes_totales`), evaluate the stored rows' formulas
    in category order, write each `amount_cents`, then derive the Liquidacion
    totals **from the stored rows** in one transaction; return the per-employee
    envelope. It never creates items.

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
  results list; pending rows flagged), `LiquidacionDetailView` (totals + grouped
  per-item breakdown; explicit "pending"/"not calculated" state, no fake zeros).
- `src/router/index.js` — `/`, `/payroll`, `/payroll/:id`.
- `src/utils/money.js` — `es-AR` integer-cent formatting; `null`/`undefined`
  render as `—` (pending), never as `$0.00`.

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
  │       liquidacion = Liquidacion.find_by(employee, period)   → none/empty? no_applicable_items
  │       period_resolver.resolve(employee, period)            → nil? no_job_for_period
  │       supported_jurisdiction?(job.country)                → false? unsupported_jurisdiction
  │       for each prepared Asignacion (haber→descuento→aporte, position):
  │         cel_evaluator.evaluate(row.formula, bindings, running_subtotals)
  │             → formula_invalid | formula_error | row.amount_cents
  │       persist row amounts; derive totals FROM stored rows (one transaction)
  │
  └─ EnvelopeSerializer.envelope(results)
       { results: [ { employee_id, status: success,
                      liquidacion: { url } } | { employee_id, status: failure,
                      error: { code, detail } } ] }
```

The run and its items are created by an **upstream step** (outside the
calculator): an empty Liquidacion plus one Asignacion per applicable item,
carrying formula/category/position and null amounts. In this repo, `db/seeds.rb`
and the spec helper stand in for that step. Failures are per-employee: one broken
employee never blocks the batch (FR-014), and a failing item aborts that
employee's calculation with **no** partial amounts or totals persisted (FR-008) —
the run stays pending.

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
| Run/item preparation| Upstream step; seeds + spec helper stand in     |
| Formula evaluation  | `CelEvaluator` (cel gem, whitelisted helpers)  |
| Persistence/audit   | Models + migrations; snapshot `Asignacion` rows|
| Client state & UI   | Pinia store, `views/*`, `services/api.js`      |

Rules: controllers pass through to services; services never render JSON;
serializers never compute money; formulas are data (CEL), never code.

## Seeds overview (`backend/db/seeds.rb`, idempotent)

4 employees (synthetic names — no real-person PII), 2 countries, 7 templates
(one catalog; country gates inside the formulas):

- `Ana García` (AR, 120,000,000) — single job from 2025-01-01.
- `Bruno Sosa` (AR, 100,000,000 → 110,000,000) — mid-year raise at 2026-07-01.
- `Camila Díaz` (UY, 6,000,000) — single job.
- `Diego Araújo` (UY, 5,000,000 → 5,500,000) — mid-year raise at 2026-07-01.

(base salaries in integer cents — approximate middle-class monthly gross in each
country's local currency)

Single item catalog (not duplicated per country; country gates inside formulas):

| Description        | Category  | Formula |
|--------------------|-----------|---------|
| Salario base       | haber     | `base_salary` |
| Bono fijo          | haber     | `country == "AR" ? 5000000 : 250000` |
| Aguinaldo          | haber     | `period_month == 12 ? round(base_salary / 2) : 0` |
| Extra horas        | haber     | `period_month == 6 ? round(base_salary * 0.1) : 0` |
| Descuento legal    | descuento | `round(base_salary * (country == "AR" ? 0.17 : 0.15))` |
| Descuento previsional | descuento | `round(haberes_totales * 0.03)` |
| Aporte empleador   | aporte    | `round(base_salary * (country == "AR" ? 0.29 : 0.23))` |

The catalog exercises the formula types in `contracts/cel.md`: reference,
arithmetic, conditional/ternary, country-dependent, and subtotal-dependent
(`haberes_totales`) expressions, plus `round`; integer literals appear inside
these formulas, and pure-literal evaluation is covered by `cel_evaluator_spec.rb`.

Seeding also **prepares a pending run** for every employee and every month from
2025-01 to 2026-12: an empty Liquidacion plus one Asignacion per applicable item
(selection via `ItemSelector`), with null amounts. This stands in for the
upstream step that owns run creation. Re-seeding only refreshes runs that are new
or still pending — it never rewrites a calculated run (FR-009 keeps history).

## Consistency & invariants

- Money: integer cents only; no floats cross the API or storage boundary
  (enforced by the evaluator, serializers, and request specs).
- Idempotency: unique `[employee_id, period_year, period_month]` + filling the
  same prepared rows, so repeat calculation yields identical totals and no
  duplicate rows (SC-002).
- Two-state lifecycle: a run is *pending* until calculated (null totals/amounts)
  and *calculated* afterwards (all totals set, all-or-none).
- Persisted audit trail: each `Asignacion` stores `formula`,
  `formula_version`, category, position and amount — the UI and API detail render
  from this trail, not from recomputation (FR-009).
- Determinism: a given (employee, period) always produces the same Liquidacion
  (SC-002), validated by golden-value specs.