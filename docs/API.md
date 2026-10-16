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
format. **No floats anywhere.** `null` means *not calculated yet* (a pending
run) and must not be read as zero.

Each amount is denominated in a currency. The currency is a contract attribute:
`Job.currency` is the ISO 4217 code (like `base_salary_cents` is the amount), and
a run's `currency` is the one of the Job effective for its period. It is
**display-only** — the calculator works on raw minor units and never reads it.
There is no currency conversion.

## Currency of a run

`GET /employees/:id` exposes each job's `currency`. `GET /liquidaciones` and
`GET /liquidaciones/:id` expose a top-level `currency` for the run (the Job
currency for the period); a pending run still reports its `currency` even though
its amounts are `null`. A contract may change currency between periods (a later
Job with a different `currency`), so the code is resolved per period, not per
employee.

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

- `200` → `{"employee":{"id","name","jobs":[{"id","country","currency","base_salary_cents","effective_from","effective_to"}]}}`
- `404` problem+json when the employee does not exist.

### POST /api/v1/liquidaciones/calculate

Trigger payroll calculation for a set of employees and one period. The
calculator **fills in a run that an upstream step already prepared** (empty
Liquidacion + one Asignacion per applicable item): it does not create or delete
items, only writes each row's `amount_cents` and then derives the Liquidacion
totals from the stored rows. A run with no prepared items fails with
`no_applicable_items`. Recalculation is idempotent (unique employee + period);
per-employee failures never block the rest of the batch (FR-014).

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
        "currency": "ARS",
        "haberes_totales_cents": 125000000, "descuentos_totales_cents": 24150000,
        "aportes_totales_cents": 34800000, "final_salary_cents": 100850000,
        "pending": false,
        "items_url": "/api/v1/liquidaciones/1" }
    ]
  }
  ```
- A run that has not been calculated yet is returned with `"pending": true` and
  all totals as `null`.
- `400` problem+json when `period` is missing or not `YYYY-MM`.

### GET /api/v1/liquidaciones/:id

Detail including the per-item audit breakdown (FR-009). Items are grouped by
category in evaluation order: haberes → descuentos → aportes.

- `200` →
  ```json
  {
    "liquidacion": {
      "id": 1, "employee_id": 1, "name": "Ana García", "period": "2026-09",
      "currency": "ARS",
      "haberes_totales_cents": 125000000, "descuentos_totales_cents": 24150000,
      "aportes_totales_cents": 34800000, "final_salary_cents": 100850000,
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
- `404` problem+json when the liquidacion does not exist.

## Per-employee failure codes

These codes are stable contract. A failing item aborts that employee's
Liquidacion with no partial record (FR-008).

| Code                 | Meaning                                                          |
|----------------------|------------------------------------------------------------------|
| `no_job_for_period`  | No contractual Job covers the requested period.                  |
| `unsupported_jurisdiction` | The employee's Job country has no supported legislation.   |
| `no_applicable_items`| No prepared run (empty Liquidacion + items) exists for the period.     |
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