FactoryBot.define do
  factory :asignacion do
    liquidacion
    template { create(:asignacion_template) }
    description { 'Concepto' }
    category { 'haber' }
    formula { 'base_salary' }
    formula_version { 1 }
    amount_cents { 1_000_000 }
    position { 1 }

    # An item that has been assigned but not yet evaluated by the calculator.
    trait :pending do
      amount_cents { nil }
    end
  end
end
