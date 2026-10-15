class LiquidacionSerializer
  CATEGORY_ORDER = { "haber" => 0, "descuento" => 1, "aporte" => 2 }.freeze
  private_constant :CATEGORY_ORDER

  class << self
    def list(liquidaciones)
      { liquidaciones: liquidaciones.map { |liquidacion| list_attributes(liquidacion) } }
    end

    def show(liquidacion)
      { liquidacion: list_attributes(liquidacion).except(:items_url).merge(items: item_attributes(liquidacion)) }
    end

    private

    def list_attributes(liquidacion)
      {
        id: liquidacion.id,
        employee_id: liquidacion.employee_id,
        name: liquidacion.employee.name,
        period: period_string(liquidacion),
        haberes_totales_cents: liquidacion.haberes_totales_cents,
        descuentos_totales_cents: liquidacion.descuentos_totales_cents,
        aportes_totales_cents: liquidacion.aportes_totales_cents,
        final_salary_cents: liquidacion.final_salary_cents,
        pending: liquidacion.pending?,
        items_url: Rails.application.routes.url_helpers.api_v1_liquidacion_path(liquidacion)
      }
    end

    def item_attributes(liquidacion)
      liquidacion.asignaciones.sort_by { |asignacion| [ CATEGORY_ORDER.fetch(asignacion.category), asignacion.position ] }.map do |asignacion|
        {
          description: asignacion.description,
          category: asignacion.category,
          amount_cents: asignacion.amount_cents,
          formula: asignacion.formula,
          formula_version: asignacion.formula_version
        }
      end
    end

    def period_string(liquidacion)
      format("%04d-%02d", liquidacion.period_year, liquidacion.period_month)
    end
  end
end
