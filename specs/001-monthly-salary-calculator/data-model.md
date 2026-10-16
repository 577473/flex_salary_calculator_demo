# Data Model: Flexible Monthly Salary Calculator

**Source**: [spec.md](spec.md) Key Entities + FR-001..FR-014 + clarified item scoping
**Storage**: SQLite (local, file-backed)

## Conventions

- Monetary values: **Integer cents**, column suffix `_cents`. Never Float.
- Currency: each contract (`Job`) states its own ISO 4217 `currency`, exactly
  like its `base_salary_cents`. It is **display-only**: the calculator works on
  raw integer minor units and never reads it. A run's amounts are denominated in
  the currency of the Job effective for its period (resolved for formatting; not
  stored on `Liquidacion`/`Asignacion`). No conversion between currencies.
- Period: year + month integers. Canonical API representation: `"YYYY-MM"`.
  The same month in different years is a distinct period.
- Effective ranges: `effective_from` (inclusive) and `effective_to`
  (inclusive, nullable = open-ended).
- ISO country codes (3166-1 alpha-2) identify an employee's jurisdiction
  (`Job.country`); they are provided to each item's formula, not used to select
  templates.
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
| currency | string(3) | required, ISO 4217 alpha-3, upcase; independent of country |
| base_salary_cents | integer | required, >= 0 |
| effective_from | date | required |
| effective_to | date | nullable (open-ended); >= effective_from |

Uniqueness/lifecycle:
- Per employee, at most one Job in effect for any given period (no overlapping
  ranges; validated on create/update: `effective_from <= new effective_to` AND
  `new effective_from >= existing effective_to` for every other row).
- FR-004: calculator resolves the single Job whose range contains the period.

### AsignacionTemplate (seeded formula catalog)

Reusable payroll-item definition. Every applicable item is evaluated for the
employee+period; the item's formula carries any jurisdiction dependence.

| Field | Type | Rules |
|-------|------|-------|
| id | integer PK | |
| description | string | required, unique per category |
| formula | text | required, valid CEL (see contracts/cel.md) |
| category | string | in `haber` / `descuento` / `aporte` |
| effective_from | date | required |
| effective_to | date | nullable; default empty = permanent |
| version | integer | default 1; bumped whenever formula changes (audit, FR-009) |

Rules:
- FR-005: an item is applicable to employee E in period P iff
  `effective_from <= P <= effective_to`; its formula receives `country`
  (E's Job country for P) as an input and MUST encode any jurisdiction rule
  itself. Items are not scoped by a country relationship.
- Items are unique per `[category, description]`.
- An unsupported jurisdiction (no legislation) is refused explicitly, not
  silently evaluated against another jurisdiction's rule.
- No per-employee overrides in v1 (clarified).

### Liquidacion (payroll result per employee + period)

| Field | Type | Rules |
|-------|------|-------|
| id | integer PK | |
| employee_id | FK → Employee | required |
| period_year | integer | required |
| period_month | integer | 1..12 |
| haberes_totales_cents | integer | nullable; >= 0 |
| descuentos_totales_cents | integer | nullable; >= 0 |
| aportes_totales_cents | integer | nullable; >= 0 |
| final_salary_cents | integer | nullable; >= 0; = haberes - descuentos |

Uniqueness: unique index `[employee_id, period_year, period_month]` →
recalculation fills the same prepared run (idempotent; FR-007).

State (two-value, no history):
- **pending** — the run and its Asignacion rows exist, but nothing has been
  calculated: all four totals are `NULL` (`Liquidacion#pending?`).
- **calculated** — all four totals are set.
- All-or-none: a row with some totals set and others `NULL` is invalid.

### Asignacion (applied item line, belongs_to Liquidacion)

One payroll item belonging to a Liquidacion. It is created (with description,
category, formula, version and position) BEFORE calculation and becomes an
immutable audit snapshot once `amount_cents` is filled in.

| Field | Type | Rules |
|-------|------|-------|
| id | integer PK | |
| liquidacion_id | FK → Liquidacion | required |
| template_id | FK → AsignacionTemplate | required |
| description | text | snapshot from template |
| category | string | snapshot (`haber`/`descuento`/`aporte`) |
| formula | text | snapshot (the formula AS evaluated) |
| formula_version | integer | snapshot from template version (FR-009) |
| amount_cents | integer | nullable until calculated; rounded to cent |
| position | integer | evaluation order within the Liquidacion |

Relationships (user-specified): `Liquidacion -n Asignacion`
(Liquidacion `has_many :asignaciones`).
Rationale for snapshot: FR-009 auditability — a later catalog formula change
must not rewrite history.

## Evaluation Order & Dependencies (FR-002, clarified)

The run is prepared first, then calculated:

1. **Prepare** (upstream step, outside the calculator — this repo's seeds and
   specs stand in for it): create the empty Liquidacion for (employee, period)
   and one Asignacion per applicable catalog item, carrying its description,
   category, formula, formula_version and position. `amount_cents` and the
   totals stay `NULL` → the run is *pending*.
2. Resolve Job for (employee, period) — missing Job ⇒ per-employee failure.
   A job country without legislation ⇒ `unsupported_jurisdiction` failure.
3. Evaluate the prepared rows category by category: **haberes → descuentos →
   aportes**. A formula may reference `haberes_totales`, `descuentos_totales`,
   `aportes_totales` (the running subtotal, Integer cents, available only for
   categories already evaluated) plus `base_salary`, `country`, `period_year`,
   `period_month`, `name`. Referencing a not-yet-computed subtotal or any
   sibling item ⇒ explicit item failure (FR-008).
4. Persist each row's `amount_cents`, then derive the Liquidacion totals **from
   the stored rows** (never from in-memory intermediates) and set
   `final_salary = haberes - descuentos`. The run is no longer pending.
5. A run with no prepared rows ⇒ `no_applicable_items` failure. Any item
   failure aborts the transaction: no amounts and no totals are written.

## Seeded Example Data (FR-012)

- 5 employees; three carry a contract history to prove period-bound
  calculations — Bruno and Diego each have a mid-year base-salary change (two
  Jobs), and Elena has two closed Jobs then an open one (three Jobs).
- Countries: **Argentina (AR)** and **Uruguay (UY)** — at least two countries.
- Base salaries are integer cents approximating a local-currency middle-class
  monthly gross (realistic `_cents` magnitudes):
  - Ana García (AR): `120_000_000`
  - Bruno Sosa (AR): `100_000_000` → `110_000_000` (raise effective 2026-07-01)
  - Camila Díaz (UY): `6_000_000`
  - Diego Araújo (UY): `5_000_000` → `5_500_000` (raise effective 2026-07-01)
  - Elena Ríos (AR): `80_000_000` → `90_000_000` → `100_000_000` (closed
    2025-01..06, closed 2025-07..12, open from 2026-01-01)
- Currency is a contract attribute: every Job states its own ISO 4217 code (the
  seed uses the local currency, AR→ARS / UY→UYU, but the column is independent of
  `country`). Amounts are minor units of the Job currency for the period; a run's
  currency is resolved from that Job purely for display — the calculator never
  uses it, and there is no conversion (see spec.md Assumptions).
- A single item catalog (not duplicated per country) with examples covering:
  - literal value (fixed bonus, country-dependent amount
    e.g., `country == "AR" ? 5000000 : 250000`),
  - reference + arithmetic (e.g., `base_salary * 2`),
  - conditional/ternary (e.g., `period_month == 12 ? base_salary / 2 : 0`),
  - country-dependent percentage discount
    (e.g., `round(base_salary * (country == "AR" ? 0.17 : 0.15))`),
  - subtotal-dependent item (e.g., a descuento referencing `haberes_totales`).
- Re-seeding updates Jobs/templates in place but never rewrites stored
  Liquidaciones (FR-009 keeps history); recalculate a period after changing the
  catalog so persisted totals reflect the new formulas.
- Seeds also prepare a **pending** run (empty Liquidacion + one Asignacion per
  applicable item) for every employee for every month in 2025-01..2026-12, so
  the UI can open a period before anything has been calculated.