#!/usr/bin/env ruby
# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Minimal, self-contained example of the salary-calculation core.
#
# It uses the REAL application classes (Employee, Job, AsignacionTemplate,
# Liquidacion, Asignacion and the CalculateLiquidacion service) but no
# persistent database, no migrations, no seeds and no web server: the data
# lives in a throwaway in-memory SQLite database that disappears on exit.
#
# Run it (from the backend/ directory):
#
#   bundle exec ruby scripts/sample_calculation.rb            # period 2026-03
#   bundle exec ruby scripts/sample_calculation.rb 2026-06    # any YYYY-MM
#
# From an IDE: run this file as a plain Ruby program with the working
# directory set to backend/. No other setup is required.
# ---------------------------------------------------------------------------

require "bundler/setup"
require "active_record"
require "cel"

# --- 1. Ephemeral in-memory database ---------------------------------------
# ActiveRecord needs a connection even for throwaway objects, so point it at
# an in-memory SQLite DB and load the real schema into it.
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

# The app's inflection rules (Liquidacion -> liquidaciones, etc.). These must
# be registered before the schema is loaded so foreign-key columns resolve
# correctly (liquidacion_id, not liquidacione_id).
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular "liquidacion", "liquidaciones"
  inflect.irregular "asignacion", "asignaciones"
end

ActiveRecord::Schema.verbose = false
load File.expand_path("../db/schema.rb", __dir__)

# --- 2. Load the real models and services ----------------------------------
%w[
  app/models/application_record.rb
  app/models/employee.rb
  app/models/job.rb
  app/models/asignacion_template.rb
  app/models/liquidacion.rb
  app/models/asignacion.rb
  app/services/cel_evaluator.rb
  app/services/period_resolver.rb
  app/services/item_selector.rb
  app/services/calculate_liquidacion.rb
].each { |path| require File.expand_path("../#{path}", __dir__) }

# --- 3. Minimal in-memory sample data --------------------------------------
# The contract states its currency (like its base salary); the calculator never
# reads it, it only tells a reader what the minor units below are denominated in.
def hire(name, country, currency, base_salary_cents, from: Date.new(2025, 1, 1))
  employee = Employee.create!(name: name)
  Job.create!(employee: employee, country: country, currency: currency,
              base_salary_cents: base_salary_cents,
              effective_from: from, effective_to: nil)
  employee
end

# A new contract never rewrites history: it closes the current one (end date
# only) and appends a new open one. The old rows are kept for past periods.
def new_contract(employee, country, currency, base_salary_cents, from:)
  employee.jobs.where(effective_to: nil).each { |job| job.update!(effective_to: from - 1) }
  Job.create!(employee: employee, country: country, currency: currency,
              base_salary_cents: base_salary_cents,
              effective_from: from, effective_to: nil)
  employee
end

# One employee per country so the country-dependent formulas are visible, plus
# one with a contract history (two closed contracts then an open one).
# Amounts are monthly middle-class gross salaries in local minor units (cents):
# AR ≈ 1,200,000 ARS, UY ≈ 60,000 UYU.
ana = hire("Ana García", "AR", "ARS", 120_000_000)
camila = hire("Camila Díaz", "UY", "UYU", 6_000_000)
elena = hire("Elena Ríos", "AR", "ARS", 80_000_000, from: Date.new(2025, 1, 1))
new_contract(elena, "AR", "ARS", 90_000_000, from: Date.new(2025, 7, 1))
new_contract(elena, "AR", "ARS", 100_000_000, from: Date.new(2026, 1, 1))
employees = [ ana, camila, elena ]

# The same formula catalog the app seeds (see db/seeds.rb). Items are not
# country-scoped; country dependence lives inside each formula.
CATALOG = [
  { description: "Salario base", category: "haber", formula: "base_salary" },
  { description: "Bono fijo", category: "haber", formula: 'country == "AR" ? 5000000 : 250000' },
  { description: "Aguinaldo", category: "haber", formula: "period_month == 12 ? round(base_salary / 2) : 0" },
  { description: "Extra horas", category: "haber", formula: "period_month == 6 ? round(base_salary * 0.1) : 0" },
  { description: "Descuento legal", category: "descuento", formula: 'round(base_salary * (country == "AR" ? 0.17 : 0.15))' },
  { description: "Descuento previsional", category: "descuento", formula: "round(haberes_totales * 0.03)" },
  { description: "Aporte empleador", category: "aporte", formula: 'round(base_salary * (country == "AR" ? 0.29 : 0.23))' }
].freeze

CATALOG.each do |item|
  AsignacionTemplate.create!(**item, effective_from: Date.new(2025, 1, 1), version: 1)
end

# --- 4. Prepare the run, then calculate ------------------------------------
period = ARGV[0] || "2026-03"
period_year, period_month = period.split("-").map { |value| Integer(value, 10) }

# Stand-in for the upstream step that lives outside the calculator: create the
# empty Liquidacion and attach one Asignacion (formula, category, position) per
# applicable item BEFORE anything is calculated.
employees.each do |employee|
  liquidacion = Liquidacion.create!(
    employee: employee, period_year: period_year, period_month: period_month
  )
  ItemSelector.call(year: period_year, month: period_month).each_with_index do |template, index|
    liquidacion.asignaciones.create!(
      template: template, description: template.description, category: template.category,
      formula: template.formula, formula_version: template.version, position: index + 1
    )
  end
end

results = CalculateLiquidacion.call(employee_ids: employees.map(&:id), period: period)[:results]

# --- 5. Print a human-readable report --------------------------------------
def thousands(cents)
  cents.abs.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
end

puts
puts "Salary calculation for period #{period}"
puts "=" * 112

results.each do |result|
  employee = Employee.find(result[:employee_id])

  if result[:status] == "failure"
    puts "#{employee.name}: FAILED (#{result[:error][:code]}) - #{result[:error][:detail]}"
    next
  end

  liquidacion = Liquidacion.find(result[:liquidacion][:id])

  # The contract is resolved by period, not assumed to be the newest one.
  job = PeriodResolver.call(employee, year: period_year, month: period_month)
  span = job.effective_to ? "#{job.effective_from}..#{job.effective_to}" : "#{job.effective_from}..open"
  puts
  puts "#{employee.name}  (job: #{job.country}, currency #{job.currency}, " \
       "base salary #{thousands(job.base_salary_cents)} cents, #{span})"
  puts "-" * 112
  puts format("  %-10s %-24s %-56s %12s", "CATEGORY", "ITEM", "FORMULA", "AMOUNT")

  liquidacion.asignaciones.order(:position).each do |asignacion|
    puts format("  %-10s %-24s %-56s %12s",
                asignacion.category, asignacion.description, asignacion.formula,
                thousands(asignacion.amount_cents))
  end

  puts "-" * 112
  puts format("  %-58s %12s", "haberes_totales_cents", thousands(liquidacion.haberes_totales_cents))
  puts format("  %-58s %12s", "descuentos_totales_cents", thousands(liquidacion.descuentos_totales_cents))
  puts format("  %-58s %12s", "aportes_totales_cents (employer-side)", thousands(liquidacion.aportes_totales_cents))
  puts format("  %-58s %12s", "final_salary_cents (haberes - descuentos)", thousands(liquidacion.final_salary_cents))
end

puts
puts "All amounts are integer cents of the contract currency (ARS/UYU)."
puts "Data was in-memory only; nothing was persisted."
