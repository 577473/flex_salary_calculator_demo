# Data Model: Flexible Monthly Salary Calculator

**Source**: [spec.md](spec.md) Key Entities + FR-001..FR-014 + clarified item scoping
**Storage**: SQLite (local, file-backed)

## Conventions

- Monetary values: **Integer cents**, column suffix `_cents`. Never Float.
- Period: year + month integers. Canonical API representation: `"YYYY-MM"`.
  The same month in different years is a distinct period.
- Effective ranges: `effective_from` (inclusive) and `effective_to`
  (inclusive, nullable = open-ended).
- ISO country codes (3166-1 alpha-2) on all country-scoped records.
- Every table has `id`, `created_at`, `updated_at` unless noted.

## Entities

### Employee

Row for a person to be paid.

| Field | Type | Rules |
|-------|------|-------|
| id | integer PK | |
| name | string | present, max 200 chars |

Relationships: `has_many :jobs`, `has_many :liquidaciones` (both dependent-order).

### Job (contractual conditions — time-effective)

Contractual base conditions for an employee over an effective period range.

| Field | Type | Rules |
|-------|------|-------|
| id | integer PK | |
| employee_id | FK → Employee | required |
| country | string(2) | required, ISO 3166-1 alpha-2, upcase |
| base_salary_cents | integer | required, >= 0 |
| effective_from | date | required |
| effective_to | date | nullable (open-ended); >= effective_from |

Uniqueness/lifecycle:
- Per employee, at most one Job in effect for any given period (no overlapping
  ranges; validated on create/update: `effective_from <= new effective_to` AND
  `new effective_from >= existing effective_to` for every other row).
- FR-004: calculator resolves the single Job whose range contains the period.

### AsignacionTemplate (seeded formula catalog)

Reusable payroll-item definition used to pick which formulas apply to an
employee+period.

| Field | Type | Rules |
|-------|------|-------|
| id | integer PK | |
| description | string | required, unique per (country, category) |
| formula | text | required, valid CEL (see contracts/cel.md) |
| category | string | in `haber` / `descuento` / `aporte` |
| country | string(2) | required ISO code |
| effective_from | date | required |
| effective_to | date | nullable; default empty = permanent |
| version | integer | default 1; bumped whenever formula changes (audit, FR-009) |

Rules:
- FR-005: an item is applicable to employee E in period P iff
  `country == E.job(P).country` AND `effective_from <= P <= effective_to`.
- No per-employee overrides in v1 (clarified).

### Liquidacion (payroll result per employee + period)

| Field | Type | Rules |
|-------|------|-------|
| id | integer PK | |
| employee_id | FK → Employee | required |
| period_year | integer | required |
| period_month | integer | 1..12 |
| haberes_totales_cents | integer | >= 0 |
| descuentos_totales_cents | integer | >= 0 |
| aportes_totales_cents | integer | >= 0 |
| final_salary_cents | integer | >= 0; = haberes - descuentos |

Uniqueness: unique index `[employee_id, period_year, period_month]` →
recalculation is idempotent (upsert; FR-007).
State: no lifecycle/locking in v1 (deferred to post-plan).

### Asignacion (applied item line, belongs_to Liquidacion)

Immutable audit snapshot of one item that contributed to a Liquidacion.

| Field | Type | Rules |
|-------|------|-------|
| id | integer PK | |
| liquidacion_id | FK → Liquidacion | required |
| template_id | FK → AsignacionTemplate | required |
| description | text | snapshot from template |
| category | string | snapshot (`haber`/`descuento`/`aporte`) |
| formula | text | snapshot (the formula AS evaluated) |
| formula_version | integer | snapshot from template version (FR-009) |
| amount_cents | integer | computed, rounded to cent |
| position | integer | evaluation order within the Liquidacion |

Relationships (user-specified): `Liquidacion -n Asignacion`
(Liquidacion `has_many :asignaciones`).
Rationale for snapshot: FR-009 auditability — a later catalog formula change
must not rewrite history.

## Evaluation Order & Dependencies (FR-002, clarified)

1. Resolve Job for (employee, period) — missing Job ⇒ per-employee failure.
2. Select applicable AsignacionTemplates (country = Job.country, range contains
   period), grouped by category.
3. Evaluate items category by category: **haberes → descuentos → aportes**.
   A formula may reference `haberes_totales`, `descuentos_totales`,
   `aportes_totales` (the running subtotal, Integer cents, available only for
   categories already evaluated) plus `base_salary`, `country`,
   `period_year`, `period_month`, `name`. Referencing a not-yet-computed
   subtotal or any sibling item ⇒ explicit item failure (FR-008).
4. Write one Asignacion per evaluated item (amount + snapshots) and the
   Liquidacion totals. `final_salary = haberes - descuentos`.

## Seeded Example Data (FR-012)

- 4 employees; 2 with mid-year base-salary change (two Jobs each) to prove
  period-bound calculations.
- Countries: **Argentina (AR)** and **Uruguay (UY)** — at least two countries.
- Templates per country/category covering:
  - literal value (fixed bonus),
  - reference + arithmetic (e.g., `base_salary * 2`),
  - conditional/ternary (e.g., `period_month == 12 ? base_salary / 2 : 0`),
  - country-dependent percentage discount
    (e.g., `round(base_salary * (country == "AR" ? 0.17 : 0.15))`),
  - subtotal-dependent item (e.g., a descuento referencing `haberes_totales`).