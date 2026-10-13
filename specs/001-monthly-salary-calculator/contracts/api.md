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

- 200 → `{"employee":{"id","name","jobs":[...]}}`
- 404 problem+json: unknown id.

### POST /api/v1/liquidaciones/calculate

Trigger payroll calculation for a set of employees and one period.

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

Failure codes: `no_job_for_period`, `no_applicable_items`, `formula_invalid`,
`formula_error` (includes item description + reason), `unknown_employee`.

Rules bonded to spec: per-employee failures never block other employees
(FR-014); failing items abort that employee's Liquidacion with no partial
totals-only record (FR-008); recalculation upserts (unique employee+period,
FR-007); determinism (FR-006).

### GET /api/v1/liquidaciones?period=2026-09[&employee_id=1]

List Liquidaciones, filtered by required `period`, optional `employee_id`.

- 200 → `{"liquidaciones":[{"id","employee_id","name","period","haberes_totales","descuentos_totales","aportes_totales","final_salary","items_url"}]}`
- Amounts serialized as strings in `"cents"` fields? **Decision**: numeric
  fields returned as integer cents (`"haberes_totales_cents": 120000`) — see
  GET /:id below.
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
    "haberes_totales_cents": 120000,
    "descuentos_totales_cents": 20400,
    "aportes_totales_cents": 34800,
    "final_salary_cents": 99600,
    "items": [
      { "description": "Base salary", "category": "haber", "amount_cents": 120000, "formula": "base_salary", "formula_version": 1 }
    ]
  }
}
```

- 404 problem+json: unknown id.

## Money serialization

Integers in cents with `_cents` suffix (or `amount_cents`); final `period` is
`"YYYY-MM"`. No floats anywhere.

## CORS

In production of this demo, allow origin `http://localhost:5173` (Vite dev
server), methods GET/POST, headers content-type. See Postman collection
(uses `{{baseUrl}}`, no auth for v1).