require 'rails_helper'

RSpec.describe PeriodResolver do
  describe '.call' do
    it 'returns the job covering the requested period for an open-ended range' do
      employee = create(:employee)
      job = create(:job, employee: employee, effective_from: Date.new(2025, 1, 1), effective_to: nil)

      expect(described_class.call(employee, year: 2026, month: 3)).to eq(job)
    end

    it 'returns nil when the employee has no job' do
      employee = create(:employee)

      expect(described_class.call(employee, year: 2026, month: 3)).to be_nil
    end

    it 'resolves the first job before a mid-year change' do
      employee = create(:employee)
      first_job = create(:job, employee: employee, effective_from: Date.new(2025, 1, 1),
                               effective_to: Date.new(2026, 6, 30))
      create(:job, employee: employee, effective_from: Date.new(2026, 7, 1), effective_to: nil)

      expect(described_class.call(employee, year: 2026, month: 3)).to eq(first_job)
    end

    it 'resolves the second job after a mid-year change' do
      employee = create(:employee)
      create(:job, employee: employee, effective_from: Date.new(2025, 1, 1),
                   effective_to: Date.new(2026, 6, 30))
      second_job = create(:job, employee: employee, effective_from: Date.new(2026, 7, 1),
                                effective_to: nil)

      expect(described_class.call(employee, year: 2026, month: 8)).to eq(second_job)
    end

    it 'treats closed-range bounds as inclusive' do
      employee = create(:employee)
      job = create(:job, employee: employee, effective_from: Date.new(2025, 1, 1),
                         effective_to: Date.new(2026, 6, 30))

      expect(described_class.call(employee, year: 2026, month: 6)).to eq(job)
      expect(described_class.call(employee, year: 2026, month: 7)).to be_nil
    end

    it 'covers open-ended ranges far in the future' do
      employee = create(:employee)
      job = create(:job, employee: employee, effective_from: Date.new(2025, 1, 1), effective_to: nil)

      expect(described_class.call(employee, year: 2099, month: 12)).to eq(job)
    end

    it 'treats a job effective mid-month as in effect for that month' do
      employee = create(:employee)
      job = create(:job, employee: employee, effective_from: Date.new(2026, 3, 15), effective_to: nil)

      expect(described_class.call(employee, year: 2026, month: 3)).to eq(job)
    end
  end
end
