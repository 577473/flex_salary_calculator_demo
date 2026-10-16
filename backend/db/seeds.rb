# Idempotent demo data (FR-012). Safe to re-run: existing records are updated, never duplicated.
# Mirrors the golden fixtures in spec/golden/demo_calculation_spec.rb (Ana/Bruno/
# Camila/Diego) and spec/golden/job_history_spec.rb (Elena: two closed Jobs + one
# open Job).
# `ItemSelector` is required here for the upstream preparation step (below).

EMPLOYEES = [
  { name: 'Ana García' },
  { name: 'Bruno Sosa' },
  { name: 'Camila Díaz' },
  { name: 'Diego Araújo' },
  { name: 'Elena Ríos' }
].freeze

# Each contract states its own currency, exactly like its base salary. It is a
# display concern only: the calculator works on raw integer minor units.
JOBS = [
  { employee: 'Ana García', country: 'AR', currency: 'ARS', base_salary_cents: 120_000_000, effective_from: Date.new(2025, 1, 1), effective_to: nil },
  { employee: 'Bruno Sosa', country: 'AR', currency: 'ARS', base_salary_cents: 100_000_000, effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 6, 30) },
  { employee: 'Bruno Sosa', country: 'AR', currency: 'ARS', base_salary_cents: 110_000_000, effective_from: Date.new(2026, 7, 1), effective_to: nil },
  { employee: 'Camila Díaz', country: 'UY', currency: 'UYU', base_salary_cents: 6_000_000, effective_from: Date.new(2025, 1, 1), effective_to: nil },
  { employee: 'Diego Araújo', country: 'UY', currency: 'UYU', base_salary_cents: 5_000_000, effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 6, 30) },
  { employee: 'Diego Araújo', country: 'UY', currency: 'UYU', base_salary_cents: 5_500_000, effective_from: Date.new(2026, 7, 1), effective_to: nil },
  # Elena holds a contract history — two closed Jobs then an open one — so a run
  # resolves the Job covering the requested period (mirrors job_history_spec.rb).
  { employee: 'Elena Ríos', country: 'AR', currency: 'ARS', base_salary_cents: 80_000_000, effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2025, 6, 30) },
  { employee: 'Elena Ríos', country: 'AR', currency: 'ARS', base_salary_cents: 90_000_000, effective_from: Date.new(2025, 7, 1), effective_to: Date.new(2025, 12, 31) },
  { employee: 'Elena Ríos', country: 'AR', currency: 'ARS', base_salary_cents: 100_000_000, effective_from: Date.new(2026, 1, 1), effective_to: nil }
].freeze

TEMPLATES = [
  { description: 'Salario base', category: 'haber', formula: 'base_salary' },
  { description: 'Bono fijo', category: 'haber', formula: 'country == "AR" ? 5000000 : 250000' },
  { description: 'Aguinaldo', category: 'haber', formula: 'period_month == 12 ? round(base_salary / 2) : 0' },
  { description: 'Extra horas', category: 'haber', formula: 'period_month == 6 ? round(base_salary * 0.1) : 0' },
  { description: 'Descuento legal', category: 'descuento', formula: 'round(base_salary * (country == "AR" ? 0.17 : 0.15))' },
  { description: 'Descuento previsional', category: 'descuento', formula: 'round(haberes_totales * 0.03)' },
  { description: 'Aporte empleador', category: 'aporte', formula: 'round(base_salary * (country == "AR" ? 0.29 : 0.23))' }
].freeze

employees = EMPLOYEES.map { |data| Employee.find_or_create_by!(data) }

JOBS.each do |data|
  employee = employees.find { |record| record.name == data[:employee] }
  job = employee.jobs.find_or_initialize_by(
    effective_from: data[:effective_from]
  )
  job.assign_attributes(data.slice(:country, :currency, :base_salary_cents, :effective_to))
  job.save!
end

TEMPLATES.each do |data|
  template = AsignacionTemplate.find_or_initialize_by(
    category: data[:category], description: data[:description]
  )
  template.assign_attributes(
    formula: data[:formula], effective_from: Date.new(2025, 1, 1), version: 1
  )
  template.save!
end

# Stand-in for the upstream step that lives outside this app: it creates the
# empty Liquidacion for an employee+period and attaches one Asignacion per
# applicable item (description, category, formula, position) BEFORE anything is
# calculated. Only pending runs are refreshed here; calculated Liquidaciones are
# audit history and are never rewritten (FR-009).
PERIODS = (2025..2026).flat_map { |year| (1..12).map { |month| [ year, month ] } }.freeze

pending_rows = 0
employees.each do |employee|
  PERIODS.each do |year, month|
    liquidacion = Liquidacion.find_or_create_by!(
      employee: employee, period_year: year, period_month: month
    )
    ItemSelector.call(year: year, month: month).each_with_index do |template, index|
      asignacion = liquidacion.asignaciones.find_or_initialize_by(template: template)
      next unless asignacion.new_record? || asignacion.amount_cents.nil?

      asignacion.assign_attributes(
        description: template.description, category: template.category,
        formula: template.formula, formula_version: template.version,
        position: index + 1
      )
      asignacion.save!
      pending_rows += 1
    end
  end
end

puts "Seeded #{Employee.count} employees, #{Job.count} jobs, #{AsignacionTemplate.count} templates, " \
     "#{Liquidacion.count} liquidaciones (#{pending_rows} pending items prepared)"
