require 'rails_helper'

RSpec.describe 'Golden demo payroll calculation' do
  # The upstream-prepared item set for every employee: one Asignacion per item,
  # in evaluation order. Formulas are hand-verified (see docs/VALIDATION.md).
  let(:catalog) do
    [
      { description: 'Salario base', category: 'haber', formula: 'base_salary' },
      { description: 'Bono fijo', category: 'haber',
        formula: 'country == "AR" ? 5000000 : 250000' },
      { description: 'Aguinaldo', category: 'haber',
        formula: 'period_month == 12 ? round(base_salary / 2) : 0' },
      { description: 'Extra horas', category: 'haber',
        formula: 'period_month == 6 ? round(base_salary * 0.1) : 0' },
      { description: 'Descuento legal', category: 'descuento',
        formula: 'round(base_salary * (country == "AR" ? 0.17 : 0.15))' },
      { description: 'Descuento previsional', category: 'descuento',
        formula: 'round(haberes_totales * 0.03)' },
      { description: 'Aporte empleador', category: 'aporte',
        formula: 'round(base_salary * (country == "AR" ? 0.29 : 0.23))' }
    ].freeze
  end

  let!(:ana)    { create(:employee, name: 'Ana García') }
  let!(:bruno)  { create(:employee, name: 'Bruno Sosa') }
  let!(:camila) { create(:employee, name: 'Camila Díaz') }
  let!(:diego)  { create(:employee, name: 'Diego Araújo') }

  before do
    create(:job, employee: ana, country: 'AR', base_salary_cents: 120_000_000,
                 effective_from: Date.new(2025, 1, 1), effective_to: nil)
    create(:job, employee: bruno, country: 'AR', base_salary_cents: 100_000_000,
                 effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 6, 30))
    create(:job, employee: bruno, country: 'AR', base_salary_cents: 110_000_000,
                 effective_from: Date.new(2026, 7, 1), effective_to: nil)
    create(:job, employee: camila, country: 'UY', base_salary_cents: 6_000_000,
                 effective_from: Date.new(2025, 1, 1), effective_to: nil)
    create(:job, employee: diego, country: 'UY', base_salary_cents: 5_000_000,
                 effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 6, 30))
    create(:job, employee: diego, country: 'UY', base_salary_cents: 5_500_000,
                 effective_from: Date.new(2026, 7, 1), effective_to: nil)
  end

  # Stand-in for the upstream step: create the empty run and its items.
  def prepare(employee, period)
    prepare_pending_run(employee, period, catalog)
  end

  def calculate(employee, period)
    entry = CalculateLiquidacion.call(employee_ids: [ employee.id ], period: period)[:results].first
    raise "calculation failed for #{employee.name} (#{period}): #{entry[:error]}" unless entry[:status] == 'success'

    Liquidacion.find(entry[:liquidacion][:id])
  end

  shared_examples 'exact totals' do |haberes, descuentos, aportes, final|
    before { prepare(employee, period) }

    it 'matches hand-computed totals in integer cents' do
      liquidacion = calculate(employee, period)
      expect(liquidacion.haberes_totales_cents).to eq(haberes)
      expect(liquidacion.descuentos_totales_cents).to eq(descuentos)
      expect(liquidacion.aportes_totales_cents).to eq(aportes)
      expect(liquidacion.final_salary_cents).to eq(final)
    end
  end

  describe '2026-03 (regular month)' do
    let(:period) { '2026-03' }

    context 'Ana (AR, base 120_000_000)' do
      let(:employee) { ana }

      include_examples 'exact totals', 125_000_000, 24_150_000, 34_800_000, 100_850_000
    end

    context 'Bruno (AR, base 100_000_000 before mid-year change)' do
      let(:employee) { bruno }

      include_examples 'exact totals', 105_000_000, 20_150_000, 29_000_000, 84_850_000
    end

    context 'Camila (UY, base 6_000_000)' do
      let(:employee) { camila }

      include_examples 'exact totals', 6_250_000, 1_087_500, 1_380_000, 5_162_500
    end

    context 'Diego (UY, base 5_000_000 before mid-year change)' do
      let(:employee) { diego }

      include_examples 'exact totals', 5_250_000, 907_500, 1_150_000, 4_342_500
    end
  end

  describe '2026-08 (after mid-year change)' do
    let(:period) { '2026-08' }

    context 'Bruno (AR, new base 110_000_000)' do
      let(:employee) { bruno }

      include_examples 'exact totals', 115_000_000, 22_150_000, 31_900_000, 92_850_000
    end

    context 'Diego (UY, new base 5_500_000)' do
      let(:employee) { diego }

      include_examples 'exact totals', 5_750_000, 997_500, 1_265_000, 4_752_500
    end
  end

  describe '2026-06 (extra hours active)' do
    let(:period) { '2026-06' }

    context 'Ana (AR, base 120_000_000)' do
      let(:employee) { ana }

      include_examples 'exact totals', 137_000_000, 24_510_000, 34_800_000, 112_490_000
    end
  end

  describe '2026-12 (aguinaldo active)' do
    let(:period) { '2026-12' }

    context 'Ana (AR, base 120_000_000)' do
      let(:employee) { ana }

      include_examples 'exact totals', 185_000_000, 25_950_000, 34_800_000, 159_050_000
    end

    context 'Camila (UY, base 6_000_000)' do
      let(:employee) { camila }

      include_examples 'exact totals', 9_250_000, 1_177_500, 1_380_000, 8_072_500
    end
  end

  describe 'snapshot audit trail' do
    it 'persists one snapshot per item in evaluation order' do
      prepare(ana, '2026-03')
      liquidacion = calculate(ana, '2026-03')

      expect(liquidacion.asignaciones.count).to eq(7)
      expect(liquidacion.asignaciones.map(&:position)).to eq((1..7).to_a)

      salario = liquidacion.asignaciones.find_by!(description: 'Salario base')
      expect(salario.category).to eq('haber')
      expect(salario.formula).to eq('base_salary')
      expect(salario.formula_version).to eq(1)
      expect(salario.amount_cents).to eq(120_000_000)
      expect(salario.position).to eq(1)

      previsional = liquidacion.asignaciones.find_by!(description: 'Descuento previsional')
      expect(previsional.category).to eq('descuento')
      expect(previsional.amount_cents).to eq(3_750_000)

      aporte = liquidacion.asignaciones.find_by!(description: 'Aporte empleador')
      expect(aporte.amount_cents).to eq(34_800_000)
    end

    it 'produces identical totals on a second run with no duplicate rows' do
      prepare(ana, '2026-03')
      first = calculate(ana, '2026-03')
      second = calculate(ana, '2026-03')

      expect(second.id).to eq(first.id)
      expect(Liquidacion.where(employee_id: ana.id, period_year: 2026, period_month: 3).count).to eq(1)
      expect(second.asignaciones.count).to eq(7)
    end
  end
end
