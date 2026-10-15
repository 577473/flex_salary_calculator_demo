class AsignacionTemplate < ApplicationRecord
  enum :category, { haber: "haber", descuento: "descuento", aporte: "aporte" }

  validates :description, presence: true
  validates :formula, presence: true
  validates :effective_from, presence: true
  validates :version, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :category, inclusion: { in: categories.keys }
  validates :description, uniqueness: { scope: [ :category ] }

  validate :effective_to_not_before_from

  def covers?(month_date)
    effective_from <= month_date && month_date <= effective_to_or_infinity
  end

  def effective_to_or_infinity
    effective_to || Date::Infinity.new
  end

  private

  def effective_to_not_before_from
    return if effective_from.nil? || effective_to.nil?

    errors.add(:effective_to, :not_before_from) if effective_to < effective_from
  end
end
