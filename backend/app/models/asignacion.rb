class Asignacion < ApplicationRecord
  belongs_to :liquidacion
  belongs_to :template, class_name: "AsignacionTemplate"

  enum :category, { haber: "haber", descuento: "descuento", aporte: "aporte" }

  validates :description, :formula, :formula_version, :position, presence: true
  validates :category, inclusion: { in: categories.keys }
  validates :formula_version, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  # amount_cents is the calculator's output: nil until the row has been evaluated.
  validates :amount_cents, numericality: { only_integer: true }, allow_nil: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  def calculated?
    !amount_cents.nil?
  end
end
