class Liquidacion < ApplicationRecord
  belongs_to :employee
  has_many :asignaciones, dependent: :destroy

  TOTAL_KEYS = %i[haberes_totales_cents descuentos_totales_cents aportes_totales_cents final_salary_cents].freeze

  validates :period_year, presence: true, numericality: { only_integer: true }
  validates :period_month, presence: true, inclusion: { in: 1..12 }
  validates :period_month, uniqueness: { scope: [ :employee_id, :period_year ] }
  # Totals are the calculator's output: nil while the payroll run is still pending.
  validates :haberes_totales_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :descuentos_totales_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :aportes_totales_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :final_salary_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  validate :totals_are_together
  validate :final_salary_matches

  def period
    "#{period_year}-#{format('%02d', period_month)}"
  end

  def pending?
    TOTAL_KEYS.any? { |key| self[key].nil? }
  end

  private

  def totals_are_together
    return if TOTAL_KEYS.all? { |key| self[key].nil? } || TOTAL_KEYS.all? { |key| !self[key].nil? }

    errors.add(:base, :incomplete_totals, message: "all totals must be set together (pending or calculated)")
  end

  def final_salary_matches
    return if [ haberes_totales_cents, descuentos_totales_cents, final_salary_cents ].any?(&:nil?)

    expected = haberes_totales_cents - descuentos_totales_cents
    errors.add(:final_salary_cents, :does_not_match) unless final_salary_cents == expected
  end
end
