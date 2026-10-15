class ItemSelector
  CATEGORY_ORDER = { "haber" => 0, "descuento" => 1, "aporte" => 2 }.freeze

  def self.call(year:, month:)
    month_date = Date.new(year, month, -1)
    templates = AsignacionTemplate.all.select { |template| template.covers?(month_date) }
    templates.sort_by { |template| [ CATEGORY_ORDER.fetch(template.category), template.effective_from, template.id ] }
  end
end
