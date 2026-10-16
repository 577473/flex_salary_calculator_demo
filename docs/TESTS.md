# Test Map

A high-level view of **what each test covers**, without reading implementation
logic. Use these commands to regenerate the outline at any time:

```bash
# Backend — prints every describe/context/it description, no execution
cd backend && bundle exec rspec --dry-run --format documentation

# Frontend — lists all test names
cd frontend && npx vitest list
```

> On the backend `--dry-run`, ignore the trailing SimpleCov "coverage below
> minimum / exit 2" message: nothing executes, so measured coverage is ~0 by
> design. Use the real run (`bundle exec rspec`) when you want pass/fail + coverage.

Totals: **153 backend examples** (RSpec) and **14 frontend tests** (Vitest).

## Coverage summary

| Area | Files | Examples | Verifies |
|------|-------|----------|----------|
| Domain models | `spec/models/` | 59 | Data integrity: validations, enums, uniqueness, effective ranges, no-overlap, period uniqueness, final-salary invariant, pending vs calculated state, contract currency |
| Core services | `spec/services/` | 50 | The calculation itself: formula evaluation, item selection, period resolution, orchestration, idempotency, failures, aggregation from stored rows |
| REST API | `spec/requests/` | 24 | HTTP contract: status codes, error envelope, response shapes, integer-cent money, pending flag / null amounts, per-period currency |
| Golden values | `spec/golden/` | 20 | Hand-computed end-to-end totals + audit trail + idempotency; contract history (open/closed Jobs) resolved by period |
| Frontend views | `frontend/tests/` | 14 | Rendering, grouping, empty/missing states, money formatting (no fake zeros), currency-aware formatting |

## Domain models — data integrity (`spec/models/`)

| Spec | Examples | Covers |
|------|----------|--------|
| `employee_spec.rb` | 4 | name presence/length; `jobs` / `liquidaciones` associations |
| `job_spec.rb` | 15 | country ISO alpha-2 (upcased); **currency ISO alpha-3 (upcased, independent of country)**; `effective_to` not before `effective_from`; open-ended ranges; **no-overlap** (contiguous and gapped ranges allowed) |
| `currency_spec.rb` | 2 | `Currency.for_country` maps seeded jurisdictions (AR→ARS, UY→UYU) and returns nil otherwise |
| `asignacion_template_spec.rb` | 11 | category enum (haber/descuento/aporte); version defaults to 1; **unique description per category**; same description allowed in another category; effective range |
| `liquidacion_spec.rb` | 16 | required period; nullable totals with `allow_nil`; **pending vs calculated** (all-or-none); **unique employee+period** (same month in another year allowed); `final_salary == haberes − descuentos`; associations |
| `asignacion_spec.rb` | 11 | presence validations; **`amount_cents` optional** (pending) and integer when present; `calculated?`; category enum; `liquidacion` / `template` associations |

## Core services — the calculation (`spec/services/`)

| Spec | Examples | Covers |
|------|----------|--------|
| `cel_evaluator_spec.rb` | 22 | literals, bare bindings, integer arithmetic/division, doubles only via `round`, string/numeric comparisons, boolean logic, ternaries, round half-up (+ optional digits), `min`/`max`, running subtotals, determinism; **failure semantics** (unknown var, bad syntax, non-boolean condition, helper type error, division by zero, non-integer money) → stable codes; error hierarchy |
| `item_selector_spec.rb` | 6 | effective-range selection across the whole catalog; ordering by category then `effective_from`/`id`; excludes out-of-range templates; year-specific ranges; open-ended (used by the seeds' upstream stand-in) |
| `period_resolver_spec.rb` | 7 | job covering the period; nil when none; before/after a mid-year change; inclusive bounds; far-future ranges; mid-month effective |
| `calculate_liquidacion_spec.rb` | 15 | fills **prepared** rows (no row created/deleted) and **derives totals from stored rows**; final invariant + **idempotent re-run**; per-employee failures (`unknown_employee`, `no_job_for_period`, `unsupported_jurisdiction`, `no_applicable_items` for missing/empty run, `formula_invalid`, `formula_error`, unavailable subtotal) leave the run pending with no partial amounts (rollback); mixed batches keep successes/failures independent |

## REST API — HTTP contract (`spec/requests/`)

| Spec | Examples | Covers |
|------|----------|--------|
| `calculate_spec.rb` | 10 | 400 problem+json (missing/empty `employee_ids`, missing/malformed/out-of-range `period`); 422 when every employee is unknown; 200 per-employee envelope (success + failure); `no_applicable_items` when no run was prepared; stable failure codes; unknown employee inside a mixed batch |
| `employees_spec.rb` | 4 | list; empty list; show with jobs; 404 problem+json |
| `liquidaciones_spec.rb` | 10 | list by **required** period with integer-cent amounts; run **currency derived from the Job effective for the period** (can differ between periods); pending runs exposed with `pending: true` and **null totals**; `employee_id` filter; 400s; detail with breakdown (pending item `amount_cents` null); item ordering (haber→descuento→aporte→position); 404 |

## Golden values — end-to-end truth (`spec/golden/`, 20)

### `demo_calculation_spec.rb` (11)

- **Regular month** `2026-03`: Ana (AR), Bruno (AR), Camila (UY), Diego (UY) — exact hand-computed totals.
- **After mid-year raise** `2026-08`: Bruno (new base), Diego (new base) — different totals.
- **Conditional items**: `2026-06` Ana (Extra horas active); `2026-12` Ana & Camila (Aguinaldo active).
- **Audit trail**: one snapshot per item in evaluation order; **identical totals on a second run with no duplicate rows**.
- Each case first prepares a pending run (empty Liquidacion + items) — the
  spec-level stand-in for the upstream step — then calculates it.

### `job_history_spec.rb` (9)

One employee with two **closed** contracts and one **open** contract
(`C: 2025-01..06`, `B: 2025-07..12`, `A: 2026-01..open`, each a different base).
Job rows are created by the fixture (the upstream stand-in), never by the
calculator. Covers:

- **a) closed Job C, different periods** — regular vs extra-hours month.
- **b) open Job A, different periods** — regular vs aguinaldo month.
- **c) closed Job B, matching period** — plus inclusive month boundaries
  (Jun→C, Jul→B, Dec→B, Jan→A).
- **Determinism** — a historical period recalculated after a later open-job
  period yields identical totals; per-period re-runs leave one run with no
  duplicate rows; the calculator never mutates the contract history.

Expected values are hand-computed from the seed formulas — never derived from the
implementation.

## Frontend views (`frontend/tests/views/`)

| Spec | Tests | Covers |
|------|-------|--------|
| `money.spec.js` | 5 | `formatMoney`/`formatPeriod`; **null/undefined render as "—"** (pending) while a real `0` still renders as money; amounts formatted in the given currency (ARS/UYU) with an ARS fallback |
| `liquidacion_detail.spec.js` | 4 | totals rendered as formatted money; items grouped haber→descuento→aporte; pending notice with dashes (no fake zeros); missing-result state with **no fake zeros** |
| `payroll_list.spec.js` | 5 | loads/renders employees; shows final totals after calculation and reports failures without fake zeros; pending run marked and rendered with dashes; empty state when the period has no results; blocks calculation when no period is selected |

## Notes

- Model specs use one-liner matchers (`it { is_expected.to ... }`), so the
  `--dry-run` outline shows them as `example at file:line` (no description text);
  the line number points at the matcher.
- Money is asserted as integer cents everywhere (no floats).
- Coverage minimums (line 90 / branch 78) are enforced by `backend/.simplecov`
  during a real `bundle exec rspec` run, not on `--dry-run`.
