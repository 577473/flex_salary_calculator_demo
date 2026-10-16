FactoryBot.define do
  factory :job do
    employee
    country { 'AR' }
    # Demo contracts are denominated in their jurisdiction's local currency.
    currency { Currency.for_country(country) || 'ARS' }
    base_salary_cents { 1_000_000 }
    effective_from { Date.new(2026, 1, 1) }
    effective_to { nil }
  end
end
