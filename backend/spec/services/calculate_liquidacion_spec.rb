require 'rails_helper'

RSpec.describe CalculateLiquidacion do
  subject(:call) { described_class.call(employee_ids: [ employee.id ], period: period) }

  let(:period) { '2026-03' }
  let(:employee) { create(:employee, name: 'Ana García') }
  let(:items) do
    [
      { description: 'Salario', category: 'haber', formula: 'base_salary' },
      { description: 'Descuento legal', category: 'descuento', formula: 'round(base_salary * 0.17)' },
      { description: 'Descuento previsional', category: 'descuento', formula: 'round(haberes_totales * 0.03)' },
      { description: 'Aporte', category: 'aporte', formula: 'round(base_salary * 0.27)' }
    ]
  end
  let!(:liquidacion) { prepare_pending_run(employee, period, items) }

  before do
    create(:job, employee: employee, country: 'AR', base_salary_cents: 1_000_000,
                 effective_from: Date.new(2025, 1, 1), effective_to: nil)
  end

  describe 'successful calculation' do
    it 'fills the prepared rows and stores totals derived from them' do
      entry = call[:results].first

      expect(entry[:employee_id]).to eq(employee.id)
      expect(entry[:status]).to eq('success')

      liquidacion.reload
      expect(liquidacion.period).to eq('2026-03')
      expect(liquidacion.haberes_totales_cents).to eq(1_000_000)
      expect(liquidacion.descuentos_totales_cents).to eq(200_000)
      expect(liquidacion.aportes_totales_cents).to eq(270_000)
      expect(liquidacion.final_salary_cents).to eq(800_000)
      expect(liquidacion).not_to be_pending
    end

    it 'writes amount_cents into the existing rows without creating or deleting any' do
      expect { call }.not_to change(Asignacion, :count)

      liquidacion.reload
      expect(liquidacion.asignaciones.count).to eq(4)

      salario = liquidacion.asignaciones.find_by!(description: 'Salario')
      expect(salario.category).to eq('haber')
      expect(salario.formula).to eq('base_salary')
      expect(salario.formula_version).to eq(1)
      expect(salario.amount_cents).to eq(1_000_000)
      expect(salario.position).to eq(1)

      previsional = liquidacion.asignaciones.find_by!(description: 'Descuento previsional')
      expect(previsional.amount_cents).to eq(30_000)
      expect(previsional.position).to eq(3)

      aporte = liquidacion.asignaciones.find_by!(description: 'Aporte')
      expect(aporte.amount_cents).to eq(270_000)
      expect(aporte.position).to eq(4)
    end

    it 'aggregates totals from the persisted rows, not from memory' do
      call

      liquidacion.reload
      expect(liquidacion.haberes_totales_cents)
        .to eq(liquidacion.asignaciones.where(category: 'haber').sum(:amount_cents))
      expect(liquidacion.descuentos_totales_cents)
        .to eq(liquidacion.asignaciones.where(category: 'descuento').sum(:amount_cents))
      expect(liquidacion.aportes_totales_cents)
        .to eq(liquidacion.asignaciones.where(category: 'aporte').sum(:amount_cents))
    end

    it 'enforces final_salary equals haberes minus descuentos' do
      call
      liquidacion.reload
      expect(liquidacion.final_salary_cents)
        .to eq(liquidacion.haberes_totales_cents - liquidacion.descuentos_totales_cents)
    end

    it 'is idempotent: a second run keeps the same rows and totals' do
      2.times { described_class.call(employee_ids: [ employee.id ], period: period) }

      liquidaciones = Liquidacion.where(employee_id: employee.id, period_year: 2026, period_month: 3)
      expect(liquidaciones.count).to eq(1)
      liquidacion.reload
      expect(liquidacion.haberes_totales_cents).to eq(1_000_000)
      expect(liquidacion.descuentos_totales_cents).to eq(200_000)
      expect(liquidacion.asignaciones.count).to eq(4)
    end
  end

  describe 'per-employee failures' do
    it 'returns unknown_employee for an id that does not exist' do
      entry = described_class.call(employee_ids: [ 424_242 ], period: period)[:results].first

      expect(entry[:status]).to eq('failure')
      expect(entry[:error][:code]).to eq('unknown_employee')
    end

    it 'returns no_job_for_period when the employee has no job in the period' do
      jobless = create(:employee, name: 'Sin Contrato')

      entry = described_class.call(employee_ids: [ jobless.id ], period: period)[:results].first

      expect(entry[:status]).to eq('failure')
      expect(entry[:error][:code]).to eq('no_job_for_period')
    end

    it 'returns unsupported_jurisdiction when the job country has no legislation' do
      abroad = create(:employee, name: 'Fuera')
      create(:job, employee: abroad, country: 'BR', base_salary_cents: 900_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)

      entry = described_class.call(employee_ids: [ abroad.id ], period: period)[:results].first

      expect(entry[:status]).to eq('failure')
      expect(entry[:error][:code]).to eq('unsupported_jurisdiction')
      expect(entry[:error][:detail]).to eq('No legislation for BR')
    end

    it 'returns no_applicable_items when no run was prepared for the period' do
      unprepared = create(:employee, name: 'Sin preparar')
      create(:job, employee: unprepared, country: 'AR', base_salary_cents: 1_000_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)

      entry = described_class.call(employee_ids: [ unprepared.id ], period: period)[:results].first

      expect(entry[:status]).to eq('failure')
      expect(entry[:error][:code]).to eq('no_applicable_items')
      expect(entry[:error][:detail]).to eq('No prepared items found for 2026-03')
    end

    it 'returns no_applicable_items when the run exists but has no items' do
      empty = create(:employee, name: 'Sin items')
      create(:job, employee: empty, country: 'AR', base_salary_cents: 1_000_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)
      create(:liquidacion, :pending, employee: empty, period_year: 2026, period_month: 3)

      entry = described_class.call(employee_ids: [ empty.id ], period: period)[:results].first

      expect(entry[:status]).to eq('failure')
      expect(entry[:error][:code]).to eq('no_applicable_items')
    end

    it 'returns formula_invalid and writes nothing when a prepared row has bad syntax' do
      broken = create(:employee, name: 'Rota Sintaxis')
      create(:job, employee: broken, country: 'AR', base_salary_cents: 1_000_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)
      run = prepare_pending_run(broken, period, [
        { description: 'Mala formula', category: 'haber', formula: '(1 + 2' }
      ])

      entry = described_class.call(employee_ids: [ broken.id ], period: period)[:results].first

      expect(entry[:status]).to eq('failure')
      expect(entry[:error][:code]).to eq('formula_invalid')
      expect(entry[:error][:detail]).to include('Mala formula')
      expect(run.reload.asignaciones.map(&:amount_cents)).to eq([ nil ])
      expect(run).to be_pending
      expect(run.haberes_totales_cents).to be_nil
    end

    it 'returns formula_error and writes nothing when evaluation fails at runtime' do
      runtime = create(:employee, name: 'Rota Runtime')
      create(:job, employee: runtime, country: 'AR', base_salary_cents: 1_000_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)
      run = prepare_pending_run(runtime, period, [
        { description: 'Division por cero', category: 'haber', formula: 'base_salary / 0' }
      ])

      entry = described_class.call(employee_ids: [ runtime.id ], period: period)[:results].first

      expect(entry[:status]).to eq('failure')
      expect(entry[:error][:code]).to eq('formula_error')
      expect(entry[:error][:detail]).to include('Division por cero')
      expect(run.reload).to be_pending
    end

    it 'fails a haber row that references an unavailable subtotal with no partial write' do
      premature = create(:employee, name: 'Prematuro')
      create(:job, employee: premature, country: 'AR', base_salary_cents: 1_000_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)
      run = prepare_pending_run(premature, period, [
        { description: 'Haberes antes de tiempo', category: 'haber',
          formula: 'round(haberes_totales * 0.03)' }
      ])

      entry = described_class.call(employee_ids: [ premature.id ], period: period)[:results].first

      expect(entry[:status]).to eq('failure')
      expect(entry[:error][:code]).to eq('formula_invalid')
      expect(run.reload).to be_pending
    end

    it 'rolls back earlier amounts when a later row fails' do
      partial = create(:employee, name: 'Parcial')
      create(:job, employee: partial, country: 'AR', base_salary_cents: 1_000_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)
      run = prepare_pending_run(partial, period, [
        { description: 'Salario parcial', category: 'haber', formula: 'base_salary' },
        { description: 'Mala parcial', category: 'descuento', formula: 'base_salary / 0' }
      ])

      entry = described_class.call(employee_ids: [ partial.id ], period: period)[:results].first

      expect(entry[:status]).to eq('failure')
      expect(entry[:error][:code]).to eq('formula_error')
      expect(run.reload.asignaciones.map(&:amount_cents)).to contain_exactly(nil, nil)
      expect(run).to be_pending
    end
  end

  describe 'mixed batches' do
    it 'keeps successes and failures independent in one call' do
      jobless = create(:employee, name: 'Sin Contrato')

      result = described_class.call(employee_ids: [ employee.id, jobless.id ], period: period)
      statuses = result[:results].map { |entry| [ entry[:employee_id], entry[:status] ] }

      expect(statuses).to contain_exactly([ employee.id, 'success' ], [ jobless.id, 'failure' ])
      expect(Liquidacion.where(employee_id: employee.id).count).to eq(1)
      expect(Liquidacion.where(employee_id: jobless.id).count).to eq(0)
    end
  end
end
