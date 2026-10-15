require 'rails_helper'

RSpec.describe Job, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:country) }
    it { is_expected.to validate_presence_of(:base_salary_cents) }
    it { is_expected.to validate_presence_of(:effective_from) }
    it { is_expected.to validate_numericality_of(:base_salary_cents).is_greater_than_or_equal_to(0) }
  end

  describe 'country format' do
    it 'upcases the country code before validation' do
      job = build(:job, country: 'ar')
      job.valid?
      expect(job.country).to eq('AR')
    end

    it 'rejects non ISO 3166-1 alpha-2 values' do
      job = build(:job, country: 'ARG')
      expect(job).not_to be_valid
    end
  end

  describe 'effective range' do
    it 'rejects effective_to before effective_from' do
      job = build(:job, effective_from: Date.new(2026, 6, 1), effective_to: Date.new(2026, 1, 1))
      expect(job).not_to be_valid
      expect(job.errors[:effective_to]).to be_present
    end

    it 'allows open-ended ranges' do
      job = build(:job, effective_to: nil)
      expect(job).to be_valid
    end
  end

  describe 'no-overlap validation' do
    let(:employee) { create(:employee) }

    it 'rejects a new job overlapping an existing one' do
      create(:job, employee: employee, effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2026, 6, 30))
      overlapping = build(:job, employee: employee, effective_from: Date.new(2026, 6, 1), effective_to: Date.new(2026, 8, 31))
      expect(overlapping).not_to be_valid
      expect(overlapping.errors[:effective_from]).to be_present
    end

    it 'allows contiguous ranges (end of one equals start of next)' do
      create(:job, employee: employee, effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2026, 6, 30))
      contiguous = build(:job, employee: employee, effective_from: Date.new(2026, 7, 1), effective_to: Date.new(2026, 12, 31))
      expect(contiguous).to be_valid
    end

    it 'allows gap between ranges' do
      create(:job, employee: employee, effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2026, 6, 30))
      gap = build(:job, employee: employee, effective_from: Date.new(2026, 9, 1), effective_to: Date.new(2026, 12, 31))
      expect(gap).to be_valid
    end
  end
end
