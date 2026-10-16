require 'rails_helper'

# Job entries are created by an upstream system, not by the calculator. This
# fixture stands in for that system: one employee with two CLOSED contracts
# (C, B) and one OPEN contract (A), laid out as the employee's lifetime would be.
#
#   C: 2025-01-01 .. 2025-06-30   (closed)  base 80_000_000 ARS
#   B: 2025-07-01 .. 2025-12-31   (closed)  base 90_000_000 ARS
#   A: 2026-01-01 .. nil          (open)    base 100_000_000 ARS
#
# The calculator must resolve the Job that covers the requested period and
# always return the same totals for a given (employee, period) — no matter how
# many times, or in what order, the calculation is asked.
RSpec.describe 'Golden job-history calculation' do
  # Same 7-item catalog the app seeds (see spec/golden/demo_calculation_spec.rb).
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

  let!(:employee) { create(:employee, name: 'Elena Ríos') }
  let!(:job_c) do
    create(:job, employee: employee, country: 'AR', base_salary_cents: 80_000_000,
                 effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2025, 6, 30))
  end
  let!(:job_b) do
    create(:job, employee: employee, country: 'AR', base_salary_cents: 90_000_000,
                 effective_from: Date.new(2025, 7, 1), effective_to: Date.new(2025, 12, 31))
  end
  let!(:job_a) do
    create(:job, employee: employee, country: 'AR', base_salary_cents: 100_000_000,
                 effective_from: Date.new(2026, 1, 1), effective_to: nil)
  end

  # Prepare the upstream run once per period, then calculate. Repeated calls for
  # the same period reuse the prepared run (never creating a duplicate).
  def calculate(period)
    year, month = period.split('-').map { |value| Integer(value, 10) }
    unless Liquidacion.exists?(employee: employee, period_year: year, period_month: month)
      prepare_pending_run(employee, period, catalog)
    end

    entry = CalculateLiquidacion.call(employee_ids: [ employee.id ], period: period)[:results].first
    raise "calculation failed for #{period}: #{entry[:error]}" unless entry[:status] == 'success'

    Liquidacion.find(entry[:liquidacion][:id])
  end

  def totals(period)
    liquidacion = calculate(period)
    [ liquidacion.haberes_totales_cents, liquidacion.descuentos_totales_cents,
      liquidacion.aportes_totales_cents, liquidacion.final_salary_cents ]
  end

  describe 'a) closed job C, different periods' do
    it 'pays job C for a regular month (2025-03)' do
      expect(totals('2025-03')).to eq([ 85_000_000, 16_150_000, 23_200_000, 68_850_000 ])
    end

    it 'pays job C — and only job C — for an extra-hours month (2025-06)' do
      expect(totals('2025-06')).to eq([ 93_000_000, 16_390_000, 23_200_000, 76_610_000 ])
    end
  end

  describe 'b) open job A, different periods' do
    it 'pays job A for a regular month (2026-03)' do
      expect(totals('2026-03')).to eq([ 105_000_000, 20_150_000, 29_000_000, 84_850_000 ])
    end

    it 'pays job A — and only job A — for an aguinaldo month (2026-12)' do
      expect(totals('2026-12')).to eq([ 155_000_000, 21_650_000, 29_000_000, 133_350_000 ])
    end
  end

  describe 'c) closed job B, matching period' do
    it 'pays job B for 2025-09' do
      expect(totals('2025-09')).to eq([ 95_000_000, 18_150_000, 26_100_000, 76_850_000 ])
    end

    it 'switches contracts on the inclusive month boundaries' do
      expect(totals('2025-06').first).to eq(93_000_000)  # C (extra hours)
      expect(totals('2025-07').first).to eq(95_000_000)  # B (no extra)
      expect(totals('2025-12').first).to eq(140_000_000) # B + aguinaldo
      expect(totals('2026-01').first).to eq(105_000_000) # A
    end
  end

  describe 'determinism: a (employee, period) always yields the same values' do
    it 'returns identical totals when a historical period is recalculated later' do
      first = totals('2025-03')   # closed job C

      totals('2026-12')           # calculate a much later, open-job period in between

      expect(totals('2025-03')).to eq(first)
    end

    it 'is idempotent per period: no duplicate rows and stable totals' do
      liquidacion = calculate('2025-03')
      2.times { calculate('2025-03') }

      runs = Liquidacion.where(employee: employee, period_year: 2025, period_month: 3)
      expect(runs.count).to eq(1)
      expect(liquidacion.reload.asignaciones.count).to eq(7)
      expect(totals('2025-03')).to eq([ 85_000_000, 16_150_000, 23_200_000, 68_850_000 ])
    end

    it 'does not mutate the contract history it reads from' do
      snapshot = [ job_c, job_b, job_a ].map do |job|
        [ job.country, job.currency, job.base_salary_cents, job.effective_from, job.effective_to ]
      end

      calculate('2025-03')
      calculate('2025-09')
      calculate('2026-12')

      expect(Job.where(employee: employee).count).to eq(3)
      expect([ job_c.reload, job_b.reload, job_a.reload ].map do |job|
        [ job.country, job.currency, job.base_salary_cents, job.effective_from, job.effective_to ]
      end).to eq(snapshot)
    end
  end
end
