---

description: "Task list for flexible monthly salary calculator feature implementation"
---

# Tasks: Flexible Monthly Salary Calculator

**Input**: Design documents from `/specs/001-monthly-salary-calculator/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Included — the feature explicitly requires tests for each functionality and the constitution mandates TDD (write tests first, watch them fail, then implement).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Web app: `backend/app/...`, `backend/spec/...`, `frontend/src/...`, `frontend/tests/...`
- Docs: `docs/`, demos/deliverables: `postman/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Create repository layout directories `backend/`, `frontend/`, `postman/`, `docs/` plus root `.gitignore` and `Procfile` (web: rails in backend, vite in frontend)
- [x] T002 [P] Scaffold Rails API-only app in `backend/` (`rails new backend --api --database=sqlite3 --skip-test`; Ruby 4.0.7 + Rails 8.1.4 installed via Scoop+MSYS2 devkit)
- [x] T003 [P] Add gems to `backend/Gemfile` and `bundle install`: `cel` (~> 0.6), `rack-cors`; test group: `rspec-rails`, `factory_bot_rails`, `faker`, `shoulda-matchers`, `brakeman`, `bundler-audit`, `simplecov`, `rubocop-rails-omakase`; run `ruby bin/rails g rspec:install`
- [x] T004 [P] Scaffold Vue 3 + Vite + vue-router + pinia + axios in `frontend/` (Vite 6.4 pinned for Node 18; npm6 shim quirk → build with `node_modules\.bin\vite.cmd`), add `vitest` + `@vue/test-utils` + `jsdom` dev deps, add `.env` with `VITE_API_URL=http://localhost:3000`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Create migrations for all tables with indexes and constraints in `backend/db/migrate/`: `employees`, `jobs` (unique-in-range handled at model layer), `asignacion_templates` (category enum + effective range), `liquidaciones` (unique index on `[employee_id, period_year, period_month]`), `asignaciones` (liquidacion FK, template FK); run `ruby bin/rails db:migrate`
- [x] T006 [P] Create models with associations, validations, and enums in `backend/app/models/`: `employee.rb`, `job.rb` (no-overlap range validation), `asignacion_template.rb` (category enum haber/descuento/aporte, version default 1), `liquidacion.rb` (uniqueness + final_salary consistency), `asignacion.rb`; add `backend/spec/models/*_spec.rb` for each (TDD: failing first)
- [x] T007 [P] Implement problem+json error envelope base controller `backend/app/controllers/api/base_controller.rb` with `rescue_from` for `ActionController::ParameterMissing`, `RecordNotFound`, `400`, `422` handling and consistent `{"errors":[...]}` output
- [x] T008 [P] Define REST routes under `/api/v1` in `backend/config/routes.rb`: `GET /health`, resources `employees` (index/show), `POST /liquidaciones/calculate`, `GET /liquidaciones` (with `period`, `employee_id` filters), `GET /liquidaciones/:id`
- [x] T009 [P] Configure CORS in `backend/config/initializers/cors.rb` via rack-cors allowing origin `http://localhost:5173`, methods GET/POST, headers content-type
- [x] T010 [P] Configure structured logging in `backend/config/environments/*.rb` (JSON-ish lograge-style tags, correlation id, no PII fields) and frontend API error-toast handling stub in `frontend/src/services/error.js`
- [x] T011 [P] Add `backend/.rubocop.yml` (rails+rspec) and run `bundle exec rubocop -a` baseline; add `backend/.simplecov` with minimum coverage threshold

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Calculate and persist monthly payroll (Priority: P1)

**Goal**: Given employee list + (month, year) period, compute each employee's Liquidacion (haberes/descuentos/aportes/final_salary) from CEL formulas over their time-effective Job conditions and applicable items, and persist it idempotently with a per-item audit breakdown.

**Independent Test**: Seed data present; `CalculateLiquidacion.call(employee_ids, period)` returns per-employee success/failure; every success matches a hand-computed golden value stored in SQLite; re-running yields identical totals and no duplicate rows.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T012 [P] [US1] Golden-value specs in `backend/spec/golden/demo_calculation_spec.rb`: fixed AR and UY examples from a single catalog (reference, ternary, country-dependent, subtotal-dependent items — integer literals inside formulas; round-half-up) asserting exact `_cents` totals per period
- [x] T013 [P] [US1] Unit specs for CelEvaluator in `backend/spec/services/cel_evaluator_spec.rb`: literals, comparisons, logic, ternary, arithmetic, `round`/`min`/`max`, unknown variable, bad syntax, division, integer/double semantics
- [x] T014 [P] [US1] Unit specs in `backend/spec/services/period_resolver_spec.rb` and `backend/spec/services/item_selector_spec.rb`: mid-year change resolution, year specificity, open-ended ranges, no-overlap, category+range filtering (country passed as a formula input)
- [x] T015 [P] [US1] Service specs for `CalculateLiquidacion` in `backend/spec/services/calculate_liquidacion_spec.rb`: success totals, idempotent upsert, per-employee partial failure (`no_job_for_period`, `no_applicable_items`, `formula_invalid`, `formula_error`), no partial Liquidacion persisted on item failure, `final_salary == haberes - descuentos`

### Implementation for User Story 1

- [x] T016 [US1] Implement `backend/app/services/cel_evaluator.rb`: wrap `cel` gem (Environment compile/check/evaluate), register `round`/`min`/`max` extensions, enforce money-int result, cache compiled expressions by formula text
- [x] T017 [P] [US1] Implement `backend/app/services/period_resolver.rb`: resolve the unique in-effect Job for employee + (year, month), return nil when none
- [x] T018 [P] [US1] Implement `backend/app/services/item_selector.rb`: select applicable AsignacionTemplates by effective range, ordered by category (haberes → descuentos → aportes) then position
- [x] T019 [US1] Implement `backend/app/services/calculate_liquidacion.rb`: orchestrate selector + evaluator + resolver, bind variables (`name`, `country`, `base_salary`, `period_year`, `period_month`, running `haberes_totales`/`descuentos_totales`/`aportes_totales`), evaluate category-ordered items, upsert Liquidacion + rebuild Asignacion snapshots, return per-employee envelope (depends on T016-T018)
- [x] T020 [US1] Write idempotent seeds in `backend/db/seeds.rb` per FR-012/data-model.md: 4 employees (2 with mid-year Job changes), a single AR/UY item catalog incl. `round(base_salary * (country == "AR" ? 0.17 : 0.15))`, aguinaldo ternary, `round(haberes_totales * 0.03)`, employer aportes
- [x] T021 [US1] Verify with `cd backend && ruby bin/rails db:seed && bundle exec rspec` — all US1 specs green against seeded golden values

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently (MVP)

---

## Phase 4: User Story 2 - Inspect results through the web interface (Priority: P2)

**Goal**: A Vue SPA lists employees and periods, triggers calculation, and shows any Liquidacion's totals and per-item breakdown (grouped by subtotal category) within 2 clicks.

**Independent Test**: With seeded data and calculated results, the SPA at `http://localhost:5173` shows the payroll list for a period and a detail view whose totals equal the stored Liquidacion and whose items match the breakdown, without using the Postman collection.

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T022 [P] [US2] Request specs in `backend/spec/requests/api/v1/liquidaciones_spec.rb` and `_employees_spec.rb`: GET employees, GET liquidaciones `?period=` (required), GET detail with items — success shapes, `400`/`404` errors, money as `_cents` integers
- [x] T023 [P] [US2] Vitest component specs in `frontend/tests/views/liquidacion_detail.spec.js` and `frontend/tests/views/payroll_list.spec.js`: totals rendering, item grouping by category, empty/not-found state for missing period result (no fake zeros)

### Implementation for User Story 2

- [x] T024 [P] [US2] Implement controllers and serializers in `backend/app/controllers/api/v1/employees_controller.rb`, `liquidaciones_controller.rb` (index/detail only) and `backend/app/serializers/liquidacion_serializer.rb` (items grouped by category, `_cents` fields), satisfying the request specs
- [x] T025 [US2] Implement frontend API client `frontend/src/services/api.js` (`getEmployees`, `getLiquidaciones(period)`, `getLiquidacion(id)`, `calculatePayroll(ids, period)`) using `VITE_API_URL`, plus error mapping
- [x] T026 [P] [US2] Set up Pinia store `frontend/src/stores/payroll.js` (period, employees, results, status) and router `frontend/src/router/index.js` (Employees, Payroll, LiquidacionDetail)
- [x] T027 [P] [US2] Implement views `frontend/src/views/EmployeesView.vue`, `PayrollView.vue` (period + calculate), `LiquidacionDetailView.vue` (totals + grouped item breakdown + missing-result state)
- [x] T028 [US2] Verify US2: `cd backend && bundle exec rspec spec/requests` and `cd frontend && npm run test` green; manual run per quickstart.md scenario 5

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Access payroll data through the REST API (Priority: P3)

**Goal**: A documented REST API triggers calculation and reads results (totals + breakdown) with a consistent validation/error contract and an importable Postman collection.

**Independent Test**: Import `postman/salary_calculator.collection.json`, set `baseUrl`, run Calculate Payroll then Get Liquidacion against a fresh seeded database and observe correct totals/errors.

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T029 [P] [US3] Contract request spec in `backend/spec/requests/api/v1/calculate_spec.rb`: `400` (missing/empty `employee_ids`, malformed `period`), `422` (all unknown employees), `200` envelope successes + per-employee failures (`no_job_for_period`, `formula_error`), mixed-batch partial success

### Implementation for User Story 3

- [x] T030 [US3] Implement `backend/app/controllers/api/v1/liquidaciones_controller.rb#calculate`: strong params, `YYYY-MM` period parsing, unknown-employee request-level handling, delegates to `CalculateLiquidacion`, renders envelope JSON with `results[]` and per-item failure `code`/`detail` (depends on US1 service)
- [x] T031 [US3] Map and document failure codes in `backend/app/serializers/envelope_serializer.rb` and `docs/API.md` so clients can act on stable codes
- [x] T032 [P] [US3] Generate final importable Postman collection `postman/salary_calculator.collection.json` (v2.1.0 schema, top-level `baseUrl` variable, env vars `period`, all 6 requests incl. error examples), copy from `specs/001-monthly-salary-calculator/contracts/postman/`
- [x] T033 [US3] Write `docs/API.md` from `specs/001-monthly-salary-calculator/contracts/api.md`: every endpoint, request/response examples, error contract, money serialization

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T034 [P] Write `docs/ARCHITECTURE.md`: components (Rails API, Vue SPA, SQLite, CEL evaluator), request flow diagram for calculate + fetch, separation of concerns map, seed overview
- [x] T035 Write root `README.md`: overview, prerequisites, setup, run (Procfile), tests, docs map, Postman usage
- [x] T036 [P] Execute `specs/001-monthly-salary-calculator/quickstart.md` end-to-end and record outcomes (SC-001..SC-007) in `docs/VALIDATION.md`
- [x] T037 [P] Add CI workflow `.github/workflows/ci.yml`: RuboCop, Brakeman, bundler-audit, RSpec + SimpleCov threshold, frontend `npm run test`
- [x] T038 [P] Full verification run: `cd backend && bundle exec rspec`, `cd frontend && npm run test`, `bundle exec rubocop`, `bin/brakeman -q` — fix any drift
- [x] T039 [P] Security/audit pass: ensure seeds/logs contain no real PII, all queries parameterized, money never Float (grep `_cents` floats), N+1 check on liquidaciones#index (`includes`)

## Phase 7: Asignacion lifecycle refactor (calculator fills, never creates)

The calculator no longer creates `Asignacion` rows. An upstream step
(out of scope for this repo) pre-creates an empty `Liquidacion` and one
`Asignacion` per applicable item; the calculator only fills `amount_cents` and
derives the Liquidacion totals from the stored rows. Seeds and specs act as the
upstream stand-in.

- [x] T040 Migration `backend/db/migrate/20261014010000_allow_pending_payroll_state.rb`: make `liquidaciones` totals and `asignaciones.amount_cents` nullable (down deletes pending rows, then restores NOT NULL)
- [x] T041 [P] `Liquidacion`: nullable totals, all-or-none (`totals_are_together`), `final_salary_matches` on calculated rows, `pending?`
- [x] T042 [P] `Asignacion`: `amount_cents` optional + integer when present, `calculated?`
- [x] T043 `CalculateLiquidacion`: find prepared run + rows (empty ⇒ `no_applicable_items`, detail "No prepared items found for #{period}"), evaluate stored formulas category-ordered, write amounts, aggregate totals from stored rows in one transaction; keep `unsupported_jurisdiction` + final-salary invariant
- [x] T044 Update `backend/db/seeds.rb`: prepare pending runs for every employee for 2025-01..2026-12 via `ItemSelector`; refresh only new/pending runs
- [x] T045 Update `backend/scripts/sample_calculation.rb`: prepare pending rows before calculating
- [x] T046 Specs: `spec/support/pending_payroll.rb` helper + `:pending` factory traits; update model, calculate service, golden, and request specs (pending flag / null amounts; rollback leaves run pending)
- [x] T047 Frontend: `formatMoney(null|undefined)` ⇒ `—` (never `$0.00`) + pending badge/notice; add `tests/utils/money.spec.js`
- [x] T048 Docs propagation: `spec.md`, `data-model.md`, `contracts/api.md`, `docs/API.md`, `docs/ARCHITECTURE.md`, `docs/TESTS.md`, `quickstart.md`, `README.md`, `tasks.md`
- [x] T049 Verify: `bundle exec rspec` (137), `bundle exec rubocop` (clean), `ruby bin/brakeman -q` (0), `cd frontend && npm test` (13), sample script golden values, dev seed

---

## Phase 8: Contract currency (display)

Satisfies the constitution's "explicit currency code per amount" by modeling each
contract's currency on `Job` — a contractual attribute, exactly like
`base_salary_cents`. Currency is **display-only**: the calculator never reads it,
and there is no conversion. A run's currency is resolved from the Job effective
for its period (not snapshotted on `Liquidacion`/`Asignacion`).

- [x] T050 Migration `backend/db/migrate/20261015000000_add_currency_to_jobs.rb`: add `jobs.currency` (ISO 4217), backfill AR→ARS / UY→UYU, `NOT NULL`
- [x] T051 `Currency` value object (`backend/app/models/currency.rb`): `BY_COUNTRY`, `for_country`
- [x] T052 `Job`: validate `currency` presence + `/\A[A-Z]{3}\z/`, upcase; independent of `country`
- [x] T053 Serializers: `EmployeeSerializer` job `currency`; `LiquidacionSerializer` run-level `currency` derived via `PeriodResolver`; controllers eager-load `employee: :jobs`
- [x] T054 Seeds + `scripts/sample_calculation.rb`: explicit per-contract currency
- [x] T055 Specs: factory derived currency, `job_spec` currency, new `currency_spec`, `employees_spec`, `liquidaciones_spec` (incl. per-period currency); frontend `money.spec` + view specs
- [x] T056 Frontend: `formatMoney(cents, currency)` via `Intl.NumberFormat`; views pass run currency
- [x] T057 Docs propagation: `spec.md`, `data-model.md`, `contracts/api.md`, `docs/API.md`, `docs/ARCHITECTURE.md`, `docs/TESTS.md`, `docs/VALIDATION.md`, `README.md`, `tasks.md`
- [x] T058 Verify: `bundle exec rspec` (144), `bundle exec rubocop` (clean), `ruby bin/brakeman -q` (0), `cd frontend && npm test` (14), sample script + dev seed

---

## Phase 9: Contract-history calculation tests

Job creation stays out of the calculator's scope; the fixture stands in for the
upstream system. One employee with two **closed** Jobs and one **open** Job
proves the calculator resolves the Job covering the requested period and always
returns the same totals for a given (employee, period), regardless of when asked.

- [x] T059 Golden spec `backend/spec/golden/job_history_spec.rb`: (a) closed Job C across periods; (b) open Job A across periods; (c) closed Job B at its matching period + inclusive month boundaries; historical recalculation is identical; per-period idempotency (one run, no duplicate rows); the calculator never mutates the Job history. Docs: `docs/TESTS.md`, `docs/VALIDATION.md`, `tasks.md`.
- [x] T060 Seeds: add `Elena Ríos` (two closed Jobs 2025-01..06 / 2025-07..12, then an open Job from 2026-01-01) so the dev DB carries a contract-history employee; keep seeding idempotent. Docs: `ARCHITECTURE.md`, `README.md`, `quickstart.md`, `data-model.md`, `docs/VALIDATION.md`.
- [x] T061 Sample script `backend/scripts/sample_calculation.rb`: resolve the printed Job by period via `PeriodResolver` (not `jobs.first`), add a contract-history employee (Elena) with two closed + one open contract, and print each contract's effective range. Docs: `README.md`.

---

## Phase 10: Human-readable currency rendering

Amounts are stored as integer minor units (cents); the presentation layer renders
them in the contract currency. The frontend already did this
(`formatMoney(cents, currency)`); the sample script now matches.

- [x] T062 `backend/scripts/sample_calculation.rb`: render every printed amount in the contract currency (`$ 1.200.000,00` for ARS, `UYU 60.000,00` for UYU) — base salary, per-item amounts and totals — mirroring the frontend's `Intl.NumberFormat("es-AR", { style: "currency" })`; null amounts render as `—`. Docs: `README.md`.

---

## Phase 11: Service entry point accepts an employee list (FR-001)

FR-001 frames the entry point as "a given **list of employees** and a given
period". `CalculateLiquidacion.call` now accepts either an employee list (the
domain form) or ids, matching the sample script and the seeded-console examples.

- [x] T063 `CalculateLiquidacion.call(employees:, period:)`: resolve the `Employee` records to ids and delegate to the existing `employee_ids:` pipeline (accepts an array or an `ActiveRecord::Relation`, preserves order, raises `ArgumentError` when neither is given). Sample script now calls `call(employees: employees, period:)`. Docs: `README.md`, `docs/ARCHITECTURE.md`, `docs/TESTS.md`, `docs/VALIDATION.md`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2). Depends on models+migrations (T005, T006). Service orchestration depends on T016-T018. No dependency on US2/US3.
- **User Story 2 (P2)**: Can start after Foundational (Phase 2). Consumes US1 results via GET endpoints (T024) — US1 service not required for UI to function, but UI demo needs seeded/calculated data.
- **User Story 3 (P3)**: Depends on US1's `CalculateLiquidacion` service (T030). Independent of US2.

### Within Each User Story

- Tests MUST be written and FAIL before implementation (constitution Principle III)
- Tests → services/models → controllers/serializers → frontend wiring → integration

### Parallel Opportunities

- Setup tasks T002-T004 run in parallel
- Foundational tasks T005-T011 run in parallel
- All test-first tasks within a story run in parallel (T012-T015, T022-T023, T029)
- US1 impl T017/T018 parallel after T016; US2 views/stores (T026-T027) parallel after T025
- Individual stories runnable in parallel across team members

---

## Parallel Example: User Story 1

```bash
# Launch all US1 test-first tasks together (TDD red state):
Task: "Golden-value specs in backend/spec/golden/demo_calculation_spec.rb"
Task: "CelEvaluator unit specs in backend/spec/services/cel_evaluator_spec.rb"
Task: "PeriodResolver + ItemSelector specs"
Task: "CalculateLiquidacion service specs"

# Then implement services in parallel:
Task: "CelEvaluator wrapper (backend/app/services/cel_evaluator.rb) → unblocks tests"
Task: "PeriodResolver (backend/app/services/period_resolver.rb)"
Task: "ItemSelector (backend/app/services/item_selector.rb)"
# CalculateLiquidacion orchestrates after those settle.
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (TDD: specs red → schema → services → seeds → green)
4. **STOP and VALIDATE**: golden values match hand-computed sums; idempotency proven by double-run
5. Deploy/demo if ready (rake runner or `ruby bin/rails runner` script per quickstart)

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → MVP!
3. Add User Story 2 (GET API + Vue SPA) → Test independently → Demo
4. Add User Story 3 (calculate endpoint + Postman + docs) → Test independently → Final
5. Polish: CI, ARCHITECTURE/API/README docs, security pass

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (domain core)
   - Developer B: User Story 2 (UI + GET API)
   - Developer C: User Story 3 (calculate endpoint + Postman) after Developer A lands the service
3. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Every US phase includes test-first tasks; do not implement before tests are written (constitution)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- Golden values: hand-compute from seed formulas in integer cents — never derive expected values from the implementation