FactoryBot.define do
  factory :asignacion_template do
    sequence(:description) { |n| "Concepto #{n}" }
    formula { 'base_salary' }
    category { 'haber' }
    effective_from { Date.new(2026, 1, 1) }
    effective_to { nil }
    version { 1 }
  end
end
