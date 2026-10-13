# CEL Formula Contract

**Evaluator**: `cel` gem (v0.6.1+) wrapped by `CelEvaluator` service; extended
with `round`/`min`/`max` helpers. Formulas are stored in
`AsignacionTemplate.formula` and evaluated per employee+period with the context
below. No arbitrary code execution (FR-003).

## Available variables (CEL bindings)

| Variable | Type | Meaning |
|----------|------|---------|
| `name` | string | employee name |
| `country` | string | Job country for the period (uppercase ISO code, e.g. `"AR"`) |
| `base_salary` | int | Job base salary, **cents** |
| `period_year` | int | period year |
| `period_month` | int | 1..12 |
| `haberes_totales` | int? | running haberes subtotal, cents (available only while evaluating descuentos/aportes) |
| `descuentos_totales` | int? | running descuentos subtotal, cents (available only while evaluating aportes) |
| `aportes_totales` | int? | running aportes subtotal, cents (never readable by items) |

Referencing an unavailable/undeclared variable fails evaluation explicitly.

## Supported syntax (subset enforced)

- Literals: integer, `double` (e.g., `0.17`), string (`"AR"`), boolean.
- Arithmetic: `+ - * / %` (ints and doubles).
- Comparison: `== != < <= > >=`.
- Logic: `&& || !` and ternary `cond ? a : b`.
- Field/identifier access: bare names as above; no nested maps.
- List construction `[...]` and membership `in` (optional, low priority).

## Helpers

- `round(value, [digits])` → int. Rounds half-up. Money **MUST** pass through
  `round(...)` before storage; `amount_cents` is validated integer >= 0.
- `min(a, b, ...)`, `max(a, b, ...)` → same numeric type as inputs.

## Rounding policy

Half-up, to nearest cent (already integer cents here → `round(x)`). Division
that yields a Double MUST be re-rounded: `round(base_salary / 12)`.
Determinism (SC-002): same bindings + same formula ⇒ same output.

## Example formulas (seeds)

| Description | Category | Formula |
|-------------|----------|---------|
| Base salary | haber | `base_salary` |
| Extra hours | haber | `period_month == 6 ? round(base_salary * 0.1) : 0` |
| Fixed bonus | haber | `25000` |
| Aguinaldo (Dec) | haber | `period_month == 12 ? round(base_salary / 2) : 0` |
| Legal discount (country-dep.) | descuento | `round(base_salary * (country == "AR" ? 0.17 : 0.15))` |
| Legal discount (% of earnings) | descuento | `round(haberes_totales * 0.03)` |
| Employer aporte | aporte | `round(base_salary * (country == "AR" ? 0.29 : 0.23))` |

## Failure semantics

- Unknown variable / bad syntax → `formula_invalid` (compile).
- Runtime error (e.g., division by zero) or non-integer money result →
  `formula_error`; item + Liquidacion fail explicitly (FR-008).