<!--
Sync Impact Report
==================
- Version change: [unversioned scaffold] -> 1.0.0 (initial ratification)
- Modified principles:
  - [PRINCIPLE_1_NAME] -> I. Radical Candor: Verified Truth Only
  - [PRINCIPLE_2_NAME] -> II. Legislation-Driven Calculation Isolation
  - [PRINCIPLE_3_NAME] -> III. Test-First (NON-NEGOTIABLE)
  - [PRINCIPLE_4_NAME] -> IV. Rails Convention & Specialist Guidance
  - [PRINCIPLE_5_NAME] -> V. Auditability & Observability
- Added sections:
  - [SECTION_2_NAME] -> Additional Constraints (filled as Technology &
    Domain Constraints)
  - [SECTION_3_NAME] -> Development Workflow & Quality Gates (filled)
  - Governance (filled with amendment, versioning, and review rules)
- Removed sections: none
- Follow-up TODOs: none (all placeholders resolved)
- Amendment 1.0.0 -> 1.1.0 (2026-10-14):
  - Modified principle: II. Legislation-Driven Calculation Isolation — rules are
    isolated per calculation item, with each item's expression carrying its own
    rule and any jurisdiction dependence via explicit bindings; country is no
    longer a per-item database scope. Explicit refusal for an unsupported
    jurisdiction is preserved through a supported-jurisdiction registry.
  - Impact: `asignacion_templates.country` column removed; `ItemSelector` no
    longer filters by country; `CalculateLiquidacion` keeps `country` as a
    formula binding and adds the `unsupported_jurisdiction` failure code. Golden
    values unchanged. Reflected in data-model.md, contracts/{cel,api}.md, and
    docs/ARCHITECTURE.md.
  - Follow-up TODOs: none.
-->

# Flex Salary Calculator Constitution

## Core Principles

### I. Radical Candor: Verified Truth Only

No code, test, document, or explanation may claim behavior that has not been
demonstrated to work. Simulated integrations, stubbed functionality presented as
real, invented fallbacks, and unverified performance claims MUST NOT be
committed. If a requirement is infeasible (e.g., a jurisdiction's rule cannot be
implemented as specified), the fact MUST be reported directly with evidence and
options, never papered over. Subagent and AI-generated output MUST be inspected
and verified before acceptance.

**Rationale**: Salary calculations drive legal payroll obligations; a false
"it works" is a compliance incident, not a bug.

### II. Legislation-Driven Calculation Isolation

Salary calculation rules MUST live in self-contained, independently testable
units — one definition per calculation item — and MUST NOT be hard-coded into
shared orchestration code paths. Each item is defined by an expression that
receives the applicable context (the employee's jurisdiction/country, contract
conditions, and prior running subtotals) as explicit bindings and encodes its
own rule inside that expression. Jurisdiction-dependent behavior MUST live in
the item's expression, never in a database relationship or a per-country row.
Each item MUST declare:

- explicit inputs, outputs, and rounding rules within the expression itself;
- a version identifier or effective date range so rule changes are traceable;
- refusal to calculate (explicit error) when the employee's jurisdiction has no
  supported legislation — silently applying another jurisdiction's rules is
  forbidden.

Monetary values MUST use integer minor units (or equivalent exact
representation); floating-point arithmetic MUST NOT be used for money.

**Rationale**: Cross-country payroll means divergent and changing legislation;
isolating each rule inside its own expression (with an explicit refusal for
unsupported jurisdictions) is the only way to keep correctness auditable
without duplicating the same logic once per country.

### III. Test-First (NON-NEGOTIABLE)

Every calculation rule, service, and endpoint is developed TDD:
tests written and failing first, then implementation, then refactor
(red-green-refactor). Each jurisdiction MUST have golden-value tests covering
its documented legislation examples, edge cases (period boundaries, rounding
thresholds), and contract-condition variants. A change without a failing-test
first (or a test added alongside the change) MUST NOT be merged. The test suite
MUST pass in CI before merge.

**Rationale**: Payroll errors are financially and legally material; tests are
the executable specification of legislation.

### IV. Rails Convention & Specialist Guidance

The application is Ruby on Rails (7.2+ with Ruby 3.3+) and MUST follow Rails
conventions: ActiveRecord for persistence, strong parameters, RESTful routing,
Zeitwerk-compatible naming, and service objects for business logic that does
not belong in models or controllers. All coding work MUST follow the project's
Rails specialist guidance at
`https://github.com/ChrisRoyse/610ClaudeSubagents/raw/refs/heads/main/agents/ruby-on-rails-specialist.md`
(including its security hardening, N+1 prevention, Hotwire, and testing
requirements). Non-obvious framework choices MUST cite guidance or Rails docs
rather than personal preference.

**Rationale**: Convention-over-configuration only pays off when everyone
(including AI agents) applies the same conventions consistently.

### V. Auditability & Observability

Every salary calculation MUST emit a structured, immutable breakdown
(input values, rule set version, intermediate steps, rounding adjustments)
sufficient for a payroll auditor to reproduce the result. Application code
MUST use structured logging with correlation IDs; calculation failures MUST be
surfaced through error tracking, not swallowed. Personal data (PII) MUST NOT
appear in logs.

**Rationale**: Payroll results must be defensible months later; an
untraceable number cannot be explained to an auditor or regulator.

## Technology & Domain Constraints

- Stack: Ruby 3.3+, Rails 7.2+, PostgreSQL 16+, Hotwire for UI; background
  processing via Solid Queue or Sidekiq.
- Money: integer minor units with an explicit currency code per amount;
  exchange-rate handling (if present) MUST be versioned and sourced from a
  single documented provider.
- Data protection: employee PII is subject to GDPR-equivalent handling —
  encryption at rest, minimal retention, no PII in logs or test fixtures
  (factories use synthetic data).
- Security baseline: OWASP Top 10 protections (CSRF, XSS, SQL injection),
  Brakeman and bundler-audit clean, parameterized queries only.
- Dependencies: gems are pinned and justified; no gem may be added without a
  passing CI run and a stated purpose.

## Development Workflow & Quality Gates

- TDD is mandatory (Principle III); CI enforces: test suite, RuboCop,
  Brakeman, bundler-audit, and SimpleCov coverage thresholds.
- Every PR requires review (human or verified agent) against this constitution;
  reviewer MUST confirm tests fail without the change when feasible.
- Branching: short-lived branches off `master`/`main`; no direct pushes of
  unreviewed changes; migrations MUST be zero-downtime safe.
- Definition of done: tests green, linters/security scans green, calculation
  breakdown implemented for any new rule, documentation updated for any
  jurisdiction added.
- AI-generated code is treated as a PR contribution: inspected, run, and
  tested before acceptance (Principle I).

## Governance

- This constitution supersedes informal practice documents; conflicts MUST be
  resolved in favor of this document.
- Amendments MUST be proposed as a documented change with rationale, impact
  analysis on existing rules/tests, and a migration plan for affected
  calculation code; approval requires review by a project maintainer.
- Versioning follows semantic versioning: MAJOR for removal or redefinition
  of principles, MINOR for added/expanded principles or sections, PATCH for
  clarifications and wording fixes. The version line below and the Sync Impact
  Report MUST be updated with every amendment.
- Compliance review: every PR MUST be checked against the Principles and
  Quality Gates; violations block merge. A full compliance review MUST also be
  performed whenever the constitution version changes.
- Runtime development guidance is maintained at the Rails specialist URL cited
  in Principle IV; guidance updates MUST be consistent with this constitution.

**Version**: 1.1.0 | **Ratified**: 2026-10-07 | **Last Amended**: 2026-10-14
