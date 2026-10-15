class CalculateLiquidacion
  # Jurisdictions the demo ships legislation for. Items are not country-scoped:
  # each item's formula references the `country` binding and encodes its own
  # rule. This registry only exists to refuse (never silently mishandle) a
  # jurisdiction we have no rules for (Constitution Principle II).
  SUPPORTED_COUNTRIES = %w[AR UY].freeze

  CATEGORY_ORDER = { "haber" => 0, "descuento" => 1, "aporte" => 2 }.freeze

  class ItemFailure < StandardError
    attr_reader :code, :detail

    def initialize(code:, detail:)
      @code = code
      @detail = detail
      super(detail)
    end
  end

  def self.call(employee_ids:, period:)
    new(employee_ids: employee_ids, period: period).call
  end

  def initialize(employee_ids:, period:)
    @employee_ids = employee_ids
    @period = period
    @year, @month = parse_period(period)
  end

  def call
    { results: @employee_ids.map { |employee_id| calculate(employee_id) } }
  end

  private

  attr_reader :period, :year, :month

  def parse_period(value)
    year_text, month_text = value.to_s.split("-")
    [ Integer(year_text, 10), Integer(month_text, 10) ]
  end

  # The calculator never picks or creates items: an upstream step creates the
  # empty Liquidacion and its Asignacion rows (formula, category, position)
  # first. This only fills in each row's amount_cents and the Liquidacion totals.
  def calculate(employee_id)
    employee = Employee.find_by(id: employee_id)
    return failure(employee_id, "unknown_employee", "Unknown employee") unless employee

    job = PeriodResolver.call(employee, year: year, month: month)
    return failure(employee_id, "no_job_for_period", "No contractual Job found for #{period}") unless job

    unless SUPPORTED_COUNTRIES.include?(job.country)
      return failure(employee_id, "unsupported_jurisdiction", "No legislation for #{job.country}")
    end

    liquidacion = Liquidacion.find_by(employee: employee, period_year: year, period_month: month)
    items = liquidacion ? liquidacion.asignaciones.to_a : []
    return failure(employee_id, "no_applicable_items", "No prepared items found for #{period}") if items.empty?

    evaluate!(employee, job, liquidacion, items)
    { employee_id: employee_id, status: "success", liquidacion: { id: liquidacion.id } }
  rescue ItemFailure => e
    failure(employee_id, e.code.to_s, e.detail)
  end

  def evaluate!(employee, job, liquidacion, items)
    Liquidacion.transaction do
      haberes, descuentos, aportes = categorize(items)

      base_bindings = {
        name: employee.name,
        country: job.country,
        base_salary: job.base_salary_cents,
        period_year: year,
        period_month: month
      }

      haberes.each { |asignacion| asignacion.amount_cents = evaluate_formula(asignacion, base_bindings) }
      haberes_total = sum(haberes)

      descuentos.each do |asignacion|
        asignacion.amount_cents = evaluate_formula(asignacion, base_bindings.merge(haberes_totales: haberes_total))
      end
      descuentos_total = sum(descuentos)

      aportes.each do |asignacion|
        asignacion.amount_cents = evaluate_formula(
          asignacion, base_bindings.merge(haberes_totales: haberes_total, descuentos_totales: descuentos_total)
        )
      end

      items.each(&:save!)

      totals = totals_from_stored_items(liquidacion)
      final_salary = totals["haber"] - totals["descuento"]
      raise ItemFailure.new(code: :formula_error, detail: "Descuentos exceed haberes") if final_salary.negative?

      liquidacion.update!(
        haberes_totales_cents: totals["haber"],
        descuentos_totales_cents: totals["descuento"],
        aportes_totales_cents: totals["aporte"],
        final_salary_cents: final_salary
      )
      liquidacion
    end
  end

  def categorize(items)
    ordered = items.sort_by { |asignacion| [ CATEGORY_ORDER.fetch(asignacion.category), asignacion.position, asignacion.id ] }
    haberes, descuentos, aportes = ordered.group_by(&:category).values_at("haber", "descuento", "aporte")
    [ Array(haberes), Array(descuentos), Array(aportes) ]
  end

  def evaluate_formula(asignacion, bindings)
    CelEvaluator.evaluate(asignacion.formula, bindings)
  rescue CelEvaluator::Error => e
    raise ItemFailure.new(code: e.code, detail: "#{asignacion.description}: #{e.message}")
  end

  def sum(asignaciones)
    asignaciones.sum(&:amount_cents)
  end

  # Totals are always derived from the rows that were just persisted, never
  # from in-memory intermediates.
  def totals_from_stored_items(liquidacion)
    totals = Hash.new(0)
    liquidacion.asignaciones.reload.each { |asignacion| totals[asignacion.category] += asignacion.amount_cents }
    totals
  end

  def failure(employee_id, code, detail)
    { employee_id: employee_id, status: "failure", error: { code: code, detail: detail } }
  end
end
