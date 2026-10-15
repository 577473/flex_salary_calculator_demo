# Research Notes: Flexible Monthly Salary Calculator

**Date**: 2026-10-07
**Feature**: `specs/001-monthly-salary-calculator`

## 1. CEL evaluation in Ruby

**Decision**: Use the `cel` gem (v0.6.1+; https://gitlab.com/os85/cel-ruby) as the
CEL foundation, extended with custom math helpers (`round`, `min`, `max`).
Money bindings use Integer cents; money-typed results MUST be normalized with
`round()` before storage.

**Rationale**:
- Active/maintained pure-Ruby CEL evaluator (racc-based parser, cel-go-mirrored
  API: Environment → compile/check/evaluate; tested against the cel-spec
  conformance suite).
- Our required subset (numbers, strings, booleans, comparisons, logic,
  ternary, field access, arithmetic) is implemented in the core language, so
  "a suitable implementation of CEL" is honored rather than inventing a
  lookalike.
- `math`/`sum` extensions are NOT built in, so `round`/`min`/`max` are added
  via the gem's extension API in our own wrapper — keeps formulas CEL-compliant
  and safe (no arbitrary code execution; FR-003).

**Alternatives considered**:
- Hand-rolled CEL-subset parser (racc/recursive descent): full control but high
  effort and spec-drift risk.
- cel-go via CLI subprocess/WASM: true CEL but adds process/bundle infrastructure
  and breaking serialization step.
- Generic expression gems (gtemple/ase): not CEL; rejected.

**Pitfalls to handle**:
- Integer-vs-Double semantics: `int / int`, precedence, division rounding.
  Define rounding policy (half-up to nearest cent) and cover with
  conformance-style unit tests (Constitution Principle III golden tests).
- Bind Int cents, never Float, for money (Constitution Principle II).

## 2. Architecture: Rails API + Vue SPA

**Decision**: API-only Rails 8.1 app (`backend/`, port 3000) + standalone
Vue 3/Vite SPA (`frontend/`, port 5173). Enable CORS for `http://localhost:5173`
via `rack-cors`. Run both with a `Procfile` (foreman). SQLite via file-backed
database (zero-install, no external server).

**Rationale**:
- Vue SFCs need a real bundler; a separate Vite dev server is the least
  contortion and cleanly exercises the REST API (the demo's stated deliverable).
- SQLite keeps the demo lightweight and local (FR-012).

**Alternatives considered**:
- `vite_rails`/vite_ruby single process (same-origin, no CORS): viable but more
  Rails integration wiring.
- Rails-served SPA via `jsbundling-rails` + esbuild with `vue/plugin-vue`:
  works, but no HMR and extra asset-pipeline surgery.

## 3. Money representation & rounding

**Decision**: Integer minor-unit (cents) columns suffixed `_cents` for all
monetary values; `:decimal` columns explicitly rejected because SQLite has no
real DECIMAL and can coerce to REAL/round. Rounding: half-up, to the nearest
cent, applied at item level via the `round()` CEL helper, then totals composed
from already-rounded item cents (deterministic, SC-002).

## 4. API error & batch conventions

**Decision**: Problem+JSON style `{"errors":[{"status","title","detail",
"source"}]}` for whole-request failures (400 malformed params, 422 request
validation). Per-employee business failures are NOT HTTP errors; they are
reported inside the success/failures envelope (200/207-style response). No
authentication for the local demo (per spec assumption).

## 5. Postman collection

**Decision**: Collection v2.1.0 JSON with a top-level `baseUrl` variable
(`http://localhost:3000`) referenced as `{{baseUrl}}` in every request. Static,
committed, diff-friendly file. Draft generated in Phase 1 under
`contracts/postman/`; shipped at repo root `postman/` during implementation.

## 6. Frontend tooling

**Decision**: Vue 3 + Vite + vue-router + Pinia, `axios` against
`VITE_API_URL=http://localhost:3000`. Component tests via Vitest for the
calculate/detail flows. No SSR.

## 7. Testing pyramid

Backend: RSpec 3.12+ — model specs, service unit specs (selector, evaluator,
calculator, rounding), request specs for every endpoint, golden-value specs for
seeded jurisdictions. Frontend: Vitest for the calculate and detail components.
Per Constitution Principle III: every change starts red.