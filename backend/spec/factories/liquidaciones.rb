FactoryBot.define do
  factory :liquidacion do
    employee
    period_year { 2026 }
    period_month { 7 }
    haberes_totales_cents { 1_000_000 }
    descuentos_totales_cents { 0 }
    aportes_totales_cents { 0 }
    final_salary_cents { 1_000_000 }

    # A run whose items exist but which has not been calculated yet.
    trait :pending do
      haberes_totales_cents { nil }
      descuentos_totales_cents { nil }
      aportes_totales_cents { nil }
      final_salary_cents { nil }
    end
  end
end
