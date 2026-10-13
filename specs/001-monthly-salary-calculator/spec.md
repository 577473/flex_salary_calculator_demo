# Feature Specification: Flexible Monthly Salary Calculator

**Feature Branch**: `001-monthly-salary-calculator`

**Created**: 2026-10-07

**Status**: Draft

**Input**: User description: "build a flexible monthly salary calculator module.
This means a class that given a list of employees and a specific month (a month
within a given year) it will calculate the amount to pay each employee from
three subtotals — haberes_totales, descuentos_totales, aportes_totales — each
built from items calculated from formulas stored in the DB (value, conditional,
or dependent on employee/contract fields), parsed with Google's CEL. Employees
have time-varying contractual conditions (Job history). Results are saved per
employee+period (Liquidacion). Lightweight local storage with example data,
exposed through a web interface, a REST API, and the DB schema."

## Clarifications

### Session 2026-10-07

- Q: How should `final_salary` be composed from the three subtotals? → A:
  `final_salary = haberes_totales - descuentos_totales`; `aportes_totales`
  represents employer-side contributions and is NOT deducted from employee pay.
- Q: May an item's formula reference the computed amount of another item or a
  running subtotal? → A: Formulas may reference the running subtotal totals
  computed so far (haberes → descuentos → aportes evaluation order); they may
  NOT reference individual sibling items.
- Q: How are Asignacion items scoped/applied to an employee + period? → A: By
  the employee's Job country for that period, the item's subtotal category
  (haberes/descuentos/aportes), and an effective period range; per-employee
  item overrides are out of scope for v1.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Calculate and persist monthly payroll (Priority: P1)

A payroll operator selects a list of employees and a specific period (month +
year). The system computes, for each employee, that period's
`haberes_totales`, `descuentos_totales`, `aportes_totales`, and
`final_salary` from that employee's applicable items and the contractual
conditions in effect for that employee in that period, and saves one
Liquidacion record per employee + period.

**Why this priority**: This is the core value of the feature; without it there
is no product.

**Independent Test**: Given seeded employees, jobs (with different base
salaries across periods), and item formulas, when the calculation runs for a
chosen period, then correct per-employee Liquidacion records exist in storage
with totals matching golden hand-computed values.

**Acceptance Scenarios**:

1. **Given** an employee whose base salary changed in March of the target
   year, **When** payroll is calculated for February, **Then** February's
   result uses February's contractual conditions, and recalculating for March
   uses March's conditions.
2. **Given** an employee with items covering base salary, a bonus, a legal
   discount, and a staff-pension contribution, **When** payroll is calculated
   for a period, **Then** `haberes_totales` equals the sum of earnings items,
   `descuentos_totales` the sum of discount items, `aportes_totales` the sum
   of employer-side contribution items, and `final_salary` equals
   `haberes_totales - descuentos_totales` (aportes are employer-side and do
   not reduce the employee's pay).
3. **Given** an item whose formula is a conditional (e.g., extra hours paid
   only above a threshold), **When** inputs fall on either side of the
   threshold, **Then** the item contributes the expected amount in each case.
4. **Given** payroll already calculated for an employee + period, **When** the
   calculation runs again for the same period, **Then** the record reflects
   the current formulas and data deterministically (same inputs → same
   outputs) without creating duplicate records for that employee + period.

---

### User Story 2 - Inspect results through the web interface (Priority: P2)

A payroll operator opens the web interface, sees the list of employees and
periods, drills into a period's Liquidacion, and views the totals plus the
per-item breakdown (description and computed amount of every item that
contributed).

**Why this priority**: Payroll results are useless to a business stakeholder
if they cannot be reviewed; the breakdown supports audit and dispute
resolution.

**Independent Test**: After calculating a period, when an operator opens that
period's detail view, then all three subtotals, the final salary, and each
contributing item's description and amount are displayed.

**Acceptance Scenarios**:

1. **Given** a calculated period, **When** the operator opens its detail page,
   **Then** the three subtotals and final salary match the stored values.
2. **Given** a calculated period, **When** the operator views the item
   breakdown, **Then** every item that participated in the calculation is
   listed with its description and amount, grouped by subtotal category.
3. **Given** an employee with no data for the selected period, **When** the
   operator views that employee in the period, **Then** the system clearly
   indicates no result exists and why (e.g., missing contractual conditions),
   rather than showing zeros.

---

### User Story 3 - Access payroll data through the REST API (Priority: P3)

An integration client triggers payroll calculation for a set of employees and
a period, and reads back the resulting Liquidaciones (totals and item
breakdowns) as structured data.

**Why this priority**: The API enables automation and downstream systems;
valuable but the product works for manual operators without it.

**Independent Test**: Call the calculation endpoint with employee IDs and a
period, then fetch the results endpoint and verify the stored totals and
breakdowns are returned.

**Acceptance Scenarios**:

1. **Given** valid employee IDs and period, **When** the calculation endpoint
   is called, **Then** it returns the created/updated Liquidaciones with all
   totals and the item breakdown.
2. **Given** an unknown employee ID or malformed period, **When** the endpoint
   is called, **Then** it returns a clear validation error and creates no
   records.
3. **Given** an employee whose contractual conditions are missing for the
   requested period, **When** the calculation endpoint is called, **Then** it
   reports an explicit, per-employee failure instead of silently producing a
   wrong or zero result.

---

### Edge Cases

- Period with no Job record for an employee → explicit failure for that
  employee; other employees in the batch still calculate.
- Formula referencing an unknown field or another item → item (and its
  Liquidacion) fails with an explicit, traceable error; no partial/totals-only
  record is persisted.
- Formula referencing a sibling item's amount or a not-yet-computed subtotal →
  explicit error per the evaluation-order rules in FR-002.
- Formula produces a negative or non-monetary value → rejected or clamped per
  documented rule; system never silently stores malformed money values.
- Employee with zero applicable items → not a valid Liquidacion; explicit
  error.
- Recalculation of an existing period (idempotency) → replaces the previous
  result for that employee + period; no duplicates.
- Same month number across different years must use that year's contractual
  data (January 2025 ≠ January 2026).
- Batch request containing a mix of valid and invalid employees → partial
  success is reported per employee with clear failure reasons.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST calculate, for a given list of employees and a given
  period (month + year), one payroll result (Liquidacion) per employee with
  `haberes_totales`, `descuentos_totales`, `aportes_totales`, and
  `final_salary = haberes_totales - descuentos_totales` (aportes are
  employer-side contributions, reported but not deducted), and persist it
  keyed by employee + period.
- **FR-002**: Totals MUST be computed from per-item contributions ("Asignacion"
  items); each item's amount MUST be produced by evaluating a formula stored
  with the item, supporting literal values, conditionals, and references to
  the employee's data, contractual conditions, and the running subtotal
  totals. Items MUST be evaluated in subtotal order (haberes → descuentos →
  aportes); a formula may reference only subtotals evaluated before its own
  category (e.g., a descuento may reference `haberes_totales`, but a haber
  may reference no subtotal), and MUST NOT reference sibling item amounts.
  Formulas referencing a not-yet-computed subtotal or another item MUST fail
  explicitly.
- **FR-003**: Formulas MUST be evaluated by an implementation of Google's
  Common Expression Language (CEL), and MUST NOT be executed as arbitrary
  code.
- **FR-004**: Employee contractual conditions (e.g., base salary, country)
  MUST be stored as dated history, and calculation for period P MUST use only
  the conditions in effect for employee + P — results are reproducible and
  tied to employee + period.
- **FR-005**: System MUST classify each item into exactly one of the three
  subtotals (haberes, descuentos, aportes), and MUST apply only items
  applicable to the employee's contractual context (jurisdiction/contract) for
  the requested period.
- **FR-006**: Calculation MUST be deterministic: identical data + period →
  identical totals (rounding rules fixed and documented).
- **FR-007**: Recalculating an existing employee + period MUST NOT create
  duplicate records; it MUST reflect the latest formulas and conditions.
- **FR-008**: System MUST refuse to persist a Liquidacion when any applicable
  item fails to evaluate (missing field, unknown reference, invalid formula),
  and MUST report the failure with the offending item and reason; silent
  fallbacks to other rules are forbidden.
- **FR-009**: Each stored Liquidacion MUST retain a per-item breakdown
  (item description, subtotal category, computed amount, and the formula
  version used) sufficient to reproduce and audit the totals.
- **FR-010**: System MUST provide a web interface to browse employees,
  periods, calculated Liquidaciones, their totals, and item breakdowns.
- **FR-011**: System MUST provide a REST API to trigger calculation for
  employees + period and to retrieve Liquidaciones with totals and breakdowns,
  returning clear validation errors for invalid input.
- **FR-012**: Storage MUST be lightweight local storage pre-seeded with
  example data: employees, multi-period job history, and item formulas that
  demonstrate literals, conditionals, and employee/contract-dependent
  expressions across at least two countries.
- **FR-013**: Domain logic MUST be modular with separation of concerns
  (persistence, formula evaluation, item selection, subtotal composition, and
  presentation/API as distinct units), each covered by automated tests.
- **FR-014**: Missing contractual conditions for an employee + period MUST
  produce an explicit error for that employee without blocking calculation of
  other employees in the same batch.

### Key Entities *(include if feature involves data)*

- **Employee**: A person to be paid; identified with a name; referenced by
  contractual history and payroll results.
- **Job (contractual conditions)**: Dated contractual base conditions for an
  employee in a period (period range, country, base salary). An employee has
  a history of these; exactly one applies per period.
- **Asignacion (payroll item)**: A component that contributes to payroll —
  description, stored formula, subtotal category (haberes / descuentos /
  aportes), and applicability context (jurisdiction/contract scope).
- **Liquidacion (payroll result)**: The computed result for one employee +
  period: `haberes_totales`, `descuentos_totales`, `aportes_totales`,
  `final_salary`, plus the per-item breakdown used to produce them.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For seeded example data, 100% of calculated Liquidaciones match
  independently hand-computed golden values (totals and final salary).
- **SC-002**: Recalculating the same period twice yields byte-identical totals
  for every employee (determinism rate: 100%).
- **SC-003**: A period where an employee's contract changed mid-history
  produces results that differ across periods exactly as the data dictates —
  zero cases of one period's conditions leaking into another.
- **SC-004**: A payroll run for 50 employees completes end-to-end (trigger →
  results visible in web interface) in under 10 seconds on a laptop.
- **SC-005**: 100% of intentionally invalid scenarios (unknown employee,
  missing contract, broken formula) surface an explicit error and persist no
  incorrect record.
- **SC-006**: An operator can view any employee's period result and its full
  item breakdown in the web interface within 2 clicks from the payroll list.
- **SC-007**: Automated tests cover every formula type (literal, conditional,
  employee/contract reference) and every subtotal composition rule; the suite
  passes before every merge.

## Assumptions

- **Composition rule (clarified)**: `final_salary = haberes_totales -
  descuentos_totales`; `aportes_totales` are employer-side contributions that
  are reported but do not reduce employee pay.
- **Item scoping (clarified)**: Applicability of an Asignacion to an employee +
  period is determined by the employee's Job country for that period, an item
  category (haberes/descuentos/aportes), and an effective period range;
  per-employee item overrides are out of scope for v1.
- **Per-item results**: The user-specified schema (Employee, Job, Liquidacion,
  Asignacion) is kept; FR-009's breakdown requires one additional
  stored detail (e.g., a line-item table or embedded breakdown) — exact shape
  decided at planning time.
- **Money representation**: Amounts use exact decimal values with 2-decimal
  (minor-unit) rounding applied at item level, documented and tested; no
  floating-point money math (constitution Principle II).
- **Currency**: Single currency per employee (implied by Job); multi-currency
  conversion is out of scope for v1.
- **Storage**: "Lightweight local or memory storage" is interpreted as a
  file-backed/embedded local database pre-seeded with example data; no
  external database server required for the demo.
- **CEL**: "Suitable implementation of CEL" is interpreted as an available
  CEL evaluator for the application's runtime; formula safety (no arbitrary
  code execution) is required (FR-003).
- **Period granularity**: Monthly only; a "period" is (year, month) with
  month-year specificity — the same month in different years is a different
  period with potentially different data.
- **Authentication/authorization**: Not in scope for v1 (demo application);
  assumed single trusted operator.
- **Constitution**: All development must satisfy `.specify/memory/constitution.md`
  v1.0.0 (TDD, legislation isolation, audit breakdown, Rails stack).
