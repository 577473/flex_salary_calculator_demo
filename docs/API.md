# Flex Salary Calculator — REST API

**Base URL (local)**: `http://localhost:3000`
**Root**: `/api/v1`
**Bodies**: JSON (`application/json`)
**Errors**: Problem+JSON `{"errors":[{"status","title","detail","source"}]}` for
whole-request failures. Per-employee business failures are returned inside the
response envelope, never as HTTP errors.

## Money serialization

Amounts are integers in cents with a `_cents` suffix (`haberes_totales_cents`,
`descuentos_totales_cents`, `aportes_totales_cents`, `final_salary_cents`,
`amount_cents`, `base_salary_cents`). Periods use the canonical `"YYYY-MM"`
format. **No floats anywhere.**

## Endpoints

### GET /api/v1/health

Liveness.

- `200` → `{"status":"ok"}`

### GET /api/v1/employees

List employees.

- `200` →
  ```json
  { "employees": [ { "id": 1, "name": "Ana García" } ] }
  ```

### GET /api/v1/employees/:id

- `200` → `{"employee":{"id","name","jobs":[{"id","country","base_salary_cents","effective_from","effective_to"}]}}`
- `404` problem+json when the employee does not exist.

### POST /api/v1/liquidaciones/calculate

Trigger payroll calculation for a set of employees and one period. Recalculation
upserts (unique employee + period); per-employee failures never block the rest
of the batch (FR-014).

Request:

```json
{ "employee_ids": [1, 2, 3, 4], "period": "2026-09" }
```

Responses:

- `400` problem+json: missing or empty `employee_ids`; missing `period`;
  `period` not `YYYY-MM`; `period` month outside `01..12`.
- `422` problem+json: every requested employee is unknown (request-level).
- `200` per-employee envelope (partial success is normal):

  ```json
  {
    "results": [
      { "employee_id": 1, "status": "success",
        "liquidacion": { "url": "/api/v1/liquidaciones/1" } },
      { "employee_id": 4, "status": "failure",
        "error": { "code": "no_job_for_period",
                   "detail": "No contractual Job found for 2026-09" } }
    ]
  }
  ```

### GET /api/v1/liquidaciones?period=2026-09[&employee_id=1]

List Liquidaciones for a period. `period` is required; `employee_id` is optional.

- `200` →
  ```json
  {
    "liquidaciones": [
      { "id": 1, "employee_id": 1, "name": "Ana García", "period": "2026-09",
        "haberes_totales_cents": 120000, "descuentos_totales_cents": 20400,
        "aportes_totales_cents": 34800, "final_salary_cents": 99600,
        "items_url": "/api/v1/liquidaciones/1" }
    ]
  }
  ```
- `400` problem+json when `period` is missing or not `YYYY-MM`.

### GET /api/v1/liquidaciones/:id

Detail including the per-item audit breakdown (FR-009). Items are grouped by
category in evaluation order: haberes → descuentos → aportes.

- `200` →
  ```json
  {
    "liquidacion": {
      "id": 1, "employee_id": 1, "name": "Ana García", "period": "2026-09",
      "haberes_totales_cents": 120000, "descuentos_totales_cents": 20400,
      "aportes_totales_cents": 34800, "final_salary_cents": 99600,
      "items": [
        { "description": "Base salary", "category": "haber",
          "amount_cents": 120000, "formula": "base_salary",
          "formula_version": 1 }
      ]
    }
  }
  ```
- `404` problem+json when the liquidacion does not exist.

## Per-employee failure codes

These codes are stable contract. A failing item aborts that employee's
Liquidacion with no partial record (FR-008).

| Code                 | Meaning                                                          |
|----------------------|------------------------------------------------------------------|
| `no_job_for_period`  | No contractual Job covers the requested period.                  |
| `no_applicable_items`| No AsignacionTemplate applies to the employee's country/period.  |
| `formula_invalid`    | Formula failed to compile/check (unknown variable, bad syntax).  |
| `formula_error`      | Formula failed at evaluation (division by zero, non-integer money result, referenced subtotal unavailable). |
| `unknown_employee`   | The requested employee id does not exist (mixed batches only).   |

`detail` for item failures is prefixed with the failing item's description,
e.g. `"Descuento legal: division by zero"`.

## CORS

The demo allows origin `http://localhost:5173` (Vite dev server), methods
GET/POST, header `content-type`.

## Postman

Import `postman/salary_calculator.collection.json`, set the `baseUrl` variable
(default `http://localhost:3000`), and use the `period` variable to switch
periods. No authentication is required for v1.