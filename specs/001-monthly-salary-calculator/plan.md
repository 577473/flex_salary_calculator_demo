# Implementation Plan: Flexible Monthly Salary Calculator

**Branch**: `001-monthly-salary-calculator` | **Date**: 2026-10-07 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-monthly-salary-calculator/spec.md`

## Summary

Build a payroll demo where a list of employees and a (year, month) period
produces per-employee Liquidaciones. Each Liquidacion totals
`haberes_totales`, `descuentos_totales`, `aportes_totales` (employer-side,
not deducted) and `final_salary = haberes_totales - descuentos_totales`, from
per-item contributions whose formulas (literals, conditionals, employee and
contract references, running subtotal references) are stored in the DB and
evaluated in Ruby with a CEL evaluator (`cel` gem + custom `round`/`min`/`max`
helpers). Contractual conditions (Job) are time-effective; calculation is
deterministic and idempotent per employee+period, with a persistent per-item
audit breakdown. Exposed via a Vue 3 SPA, a REST API, and SQLite storage —
documented (ARCHITECTURE.md, API.md, Postman collection), each functionality
covered by tests (RSpec + Vitest).

## Technical Context

**Language/Version**: Ruby 3.3+ (developed on 4.0.7) / Rails 8.1 (API-only); JavaScript (Vue 3, Vite) for the SPA

**Primary Dependencies**: backend — `cel` (CEL evaluator) 0.6.1+, `rack-cors`,
`sqlite3`, `puma`; test: `rspec-rails`, `factory_bot_rails`, `faker`, `shoulda-matchers`.
frontend — `vue@3`, `vue-router`, `pinia`, `axios`; test: `vitest`, `@vue/test-utils`

**Storage**: SQLite (file-backed, local, seeded example data)

**Testing**: RSpec 3.12 (model/unit/request + golden values) and Vitest
(component flows)

**Target Platform**: Local (Windows/Linux/macOS laptop); Rails dev server on
:3000, Vite dev server on :5173

**Project Type**: Web application (API backend + SPA frontend, local demo)

**Performance Goals**: 50-employee payroll run end-to-end < 10 s on a laptop
(SC-004); UI result detail within 2 clicks (SC-006)

**Constraints**: Money in integer cents; CEL formulas only (no arbitrary code);
deterministic results (SC-002); explicit failure instead of silent rules
(FR-008/FR-014)

**Scale/Scope**: Demo scale — tens of employees, 2 countries, 4 core entities

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Radical Candor: Verified Truth Only | PASS | No simulated integrations; every claim backed by tests (CI). |
| II. Legislation-Driven Isolation | PASS | Rules isolated per item expression; `country` passed as a formula input; explicit refusal for unsupported jurisdictions; money in Integer cents; no silent cross-country fallback. |
| III. Test-First (NON-NEGOTIABLE) | PASS | RSpec/Vitest; golden-value tests per formula type and jurisdiction; red-green-refactor. |
| IV. Rails Convention & Specialist Guidance | PASS w/ deviation | Rails API conventions + service objects followed (per constitution). Deviation: Vue SPA instead of Hotwire UI — user-mandated; see Complexity Tracking. |
| V. Auditability & Observability | PASS | Per-liquidacion Asignacion snapshot rows keep formula+version+amount; structured logs; no PII in logs. |

**Gates**: all pass. Deviation (Vue frontend) documented and justified below.

## Project Structure

### Documentation (this feature)

```text
specs/001-monthly-salary-calculator/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── api.md           # REST contract
│   ├── cel.md           # CEL formula/expression contract
│   └── postman/salary_calculator.collection.json  # Postman import draft
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
backend/                # Rails 8.1 API-only app
├── app/
│   ├── controllers/api/v1/   # employees, liquidaciones
│   ├── models/               # Employee, Job, Liquidacion, Asignacion, AsignacionTemplate
│   ├── services/             # PeriodResolver, ItemSelector, CelEvaluator, CalculateLiquidacion
│   └── views/ (API serializers instead: app/serializers/)
├── config/                   # CORS, routes
├── db/                       # migrations + seeds (2 countries)
└── spec/                     # RSpec suites

frontend/               # Vue 3 + Vite SPA
├── src/
│   ├── views/          # Employees, Period/Payroll, LiquidacionDetail
│   ├── stores/         # Pinia
│   ├── services/       # api client
├── tests/              # Vitest

postman/
└── salary_calculator.collection.json

docs/
├── ARCHITECTURE.md
└── API.md

README.md
Procfile
.gitignore
```

**Structure Decision**: Option 2 (web application: frontend + backend).
`backend/` is a Rails 8.1 API-only app; `frontend/` is the Vue 3/Vite SPA;
`postman/` ships the importable collection; `docs/` holds project/architecture/
API documentation. Shared implementation context under a single feature spec.

## Complexity Tracking

> Critical deviation from Constitution Principle IV (Hotwire UI) — must be justified.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Vue 3 SPA instead of Rails Hotwire UI | Explicit user requirement ("Use Vue.js for the frontend") and an independent REST surface is itself a deliverable; SPA cleanly exercises the API. | Rails views/Hotwire served by the API app: contradicts the explicit Vue requirement; would not demonstrate the REST API the demo must expose. |

**Suggested follow-up**: amend constitution (MINOR bump) to allow Vue SPA
frontends alongside the Rails API; this is a governance action, not executed
here.

## Implementation Milestones

1. Backend scaffold: rails new (api), models+migrations, seeds (AR/UY).
2. Domain services: PeriodResolver, CEL wrapper (`cel` + round/min/max), ItemSelector, Calculator.
3. REST API: controllers, serializers, error envelope, specs.
4. Frontend: Vue app (list employees, calculate, list/detail liquidaciones), Vitest.
5. Docs + Postman collection + README/ARCHITECTURE/API; final verification via quickstart.