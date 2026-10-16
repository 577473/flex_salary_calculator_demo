class Job < ApplicationRecord
  INFINITE_END = Date::Infinity.new

  belongs_to :employee

  before_validation :upcase_country
  before_validation :upcase_currency

  validates :country, presence: true
  validates :country, format: { with: /\A[A-Z]{2}\z/, message: :invalid_iso_code }
  # The contract states its currency (ISO 4217), like it states its base salary.
  # The calculator never reads it: amounts are raw minor units of this currency.
  validates :currency, presence: true
  validates :currency, format: { with: /\A[A-Z]{3}\z/, message: :invalid_iso_code }
  validates :base_salary_cents, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :effective_from, presence: true

  validate :effective_to_not_before_from
  validate :no_overlap_with_other_jobs

  def effective_to_or_infinity
    effective_to || INFINITE_END
  end

  def covers?(month_date)
    effective_from <= month_date && month_date <= effective_to_or_infinity
  end

  private

  def upcase_country
    self.country = country.to_s.strip.upcase
  end

  def upcase_currency
    self.currency = currency.to_s.strip.upcase
  end

  def effective_to_not_before_from
    return if effective_from.nil? || effective_to.nil?

    errors.add(:effective_to, :not_before_from) if effective_to < effective_from
  end

  def no_overlap_with_other_jobs
    return if employee.nil? || effective_from.nil? || errors[:effective_to].any?

    overlaps = employee.jobs.where.not(id: id).any? do |other|
      effective_from <= other.effective_to_or_infinity && other.effective_from <= effective_to_or_infinity
    end
    errors.add(:effective_from, :overlaps_existing_job) if overlaps
  end
end
