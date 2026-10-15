# Stands in for the upstream step (outside the calculator) that creates the
# empty Liquidacion and attaches one Asignacion per applicable item — formula,
# category and position — before anything is calculated.
module PendingPayroll
  # items: array of { description:, category:, formula: } (evaluation order).
  def prepare_pending_run(employee, period, items)
    year, month = period.split("-").map { |value| Integer(value, 10) }
    liquidacion = create(
      :liquidacion, :pending, employee: employee, period_year: year, period_month: month
    )

    items.each_with_index do |item, index|
      template = AsignacionTemplate.find_or_create_by!(
        description: item[:description], category: item[:category]
      ) do |record|
        record.formula = item[:formula]
        record.effective_from = item.fetch(:effective_from, Date.new(2025, 1, 1))
        record.version = 1
      end

      create(
        :asignacion, :pending, liquidacion: liquidacion, template: template,
        description: item[:description], category: item[:category],
        formula: item[:formula], position: index + 1
      )
    end

    liquidacion
  end
end

RSpec.configure do |config|
  config.include PendingPayroll
end
