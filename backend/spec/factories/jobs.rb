FactoryBot.define do
  factory :job do
    employee
    country { 'AR' }
    base_salary_cents { 1_000_000 }
    effective_from { Date.new(2026, 1, 1) }
    effective_to { nil }
  end
end
