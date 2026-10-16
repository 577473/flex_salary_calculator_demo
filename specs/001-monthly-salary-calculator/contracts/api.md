# REST API Contract

**Base URL (local)**: `http://localhost:3000`
**Root**: `/api/v1`
**Bodies**: JSON (`application/json`)
**Errors**: Problem+JSON `{"errors":[{"status","title","detail","source"}]}` for
whole-request failures. Per-employee business failures are returned in the
response envelope, NOT as HTTP errors.

## Endpoints

### GET /api/v1/health

Liveness.

- 200 → `{"status":"ok"}`

### GET /api/v1/employees

List employees (with current job info).

- 200 → `{"employees":[{"id", "name"}]}`

### GET /api/v1/employees/:id

- 200 → `{"employee":{"id","name","jobs":[{"id","country","currency",
  "base_salary_cents","effective_from","effective_to"}]}}` (`currency` is the
  contract's ISO 4217 code).
- 404 problem+json: unknown id.

### POST /api/v1/liquidaciones/calculate

Trigger payroll calculation for a set of employees and one period. The
calculator does not create items: it fills in a run that an upstream step
already prepared (empty Liquidacion + one Asignacion per applicable item).

Request:

```json
{
  "employee_ids": [1, 2, 3],
  "period": "2026-09"
}
```

Responses:

- **400** problem+json: malformed body / missing `employee_ids` or `period` /
  `period` not `YYYY-MM` / `employee_ids` empty.
- **422** problem+json: all requested employees unknown (request-level).
- **200**: per-employee envelope (partial success is normal):

```json
{
  "results": [
    {
      "employee_id": 1,
      "status": "success",
      "liquidacion": { "url": "/api/v1/liquidaciones/1" }
    },
    {
      "employee_id": 4,
      "status": "failure",
      "error": { "code": "no_job_for_period", "detail": "No contractual Job found for 2026-09" }
    }
  ]
}
```

Failure codes: `no_job_for_period`, `unsupported_jurisdiction`,
`no_applicable_items` (no prepared run / no prepared items for that period),
`formula_invalid`, `formula_error` (includes item description + reason),
`unknown_employee`.

Rules bonded to spec: per-employee failures never block other employees
(FR-014); failing items abort that employee's Liquidacion with no partial
totals-only record (FR-008); recalculation upserts (unique employee+period,
FR-007); determinism (FR-006).

### GET /api/v1/liquidaciones?period=2026-09[&employee_id=1]

List Liquidaciones, filtered by required `period`, optional `employee_id`.

- 200 → `{"liquidaciones":[{"id","employee_id","name","period","currency","haberes_totales_cents","descuentos_totales_cents","aportes_totales_cents","final_salary_cents","pending","items_url"}]}`
- `currency` (ISO 4217) is the currency of the Job effective for the run's
  period; it is resolved for display and the calculator never reads it.
- Amounts serialized as strings in `"cents"` fields? **Decision**: numeric
  fields returned as integer cents (`"haberes_totales_cents": 125000000`) — see
  GET /:id below. A **pending** run (not yet calculated) returns its totals and
  item amounts as `null` and `"pending": true` (the currency is still reported).
- 400 problem+json: missing/invalid `period`.

### GET /api/v1/liquidaciones/:id

Detail incl. per-item audit breakdown (FR-009):

- 200 →

```json
{
  "liquidacion": {
    "id": 1,
    "employee_id": 1,
    "name": "Ana García",
    "period": "2026-09",
    "currency": "ARS",
    "haberes_totales_cents": 125000000,
    "descuentos_totales_cents": 24150000,
    "aportes_totales_cents": 34800000,
    "final_salary_cents": 100850000,
    "pending": false,
    "items": [
      { "description": "Salario base", "category": "haber", "amount_cents": 120000000, "formula": "base_salary", "formula_version": 1 },
      { "description": "Bono fijo", "category": "haber", "amount_cents": 5000000, "formula": "country == \"AR\" ? 5000000 : 250000", "formula_version": 1 },
      { "description": "Aguinaldo", "category": "haber", "amount_cents": 0, "formula": "period_month == 12 ? round(base_salary / 2) : 0", "formula_version": 1 },
      { "description": "Extra horas", "category": "haber", "amount_cents": 0, "formula": "period_month == 6 ? round(base_salary * 0.1) : 0", "formula_version": 1 },
      { "description": "Descuento legal", "category": "descuento", "amount_cents": 20400000, "formula": "round(base_salary * (country == \"AR\" ? 0.17 : 0.15))", "formula_version": 1 },
      { "description": "Descuento previsional", "category": "descuento", "amount_cents": 3750000, "formula": "round(haberes_totales * 0.03)", "formula_version": 1 },
      { "description": "Aporte empleador", "category": "aporte", "amount_cents": 34800000, "formula": "round(base_salary * (country == \"AR\" ? 0.29 : 0.23))", "formula_version": 1 }
    ]
  }
}
```

- 404 problem+json: unknown id.

## Money serialization

Integers in cents with `_cents` suffix (or `amount_cents`); final `period` is
`"YYYY-MM"`. No floats anywhere. `null` means "not calculated yet" (pending
run) and MUST NOT be read as zero.

Every run carries a `currency` (ISO 4217) so a client can format its amounts:
it is the currency of the Job effective for the period, and is purely
presentational — amounts are raw minor units and the calculator never uses the
code. `Job.currency` is the source of truth (a contract states its own
currency, like its base salary).

## CORS

In production of this demo, allow origin `http://localhost:5173` (Vite dev
server), methods GET/POST, headers content-type. See Postman collection
(uses `{{baseUrl}}`, no auth for v1).