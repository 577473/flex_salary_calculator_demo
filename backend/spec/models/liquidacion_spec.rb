require 'rails_helper'

RSpec.describe Liquidacion, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:period_year) }
    it { is_expected.to validate_presence_of(:period_month) }
    it { is_expected.to validate_inclusion_of(:period_month).in_range(1..12) }
    it { is_expected.to validate_numericality_of(:haberes_totales_cents).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:descuentos_totales_cents).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:aportes_totales_cents).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:final_salary_cents).is_greater_than_or_equal_to(0).allow_nil }
  end

  describe 'pending vs calculated totals' do
    it 'accepts a pending run where every total is nil' do
      expect(build(:liquidacion, :pending)).to be_valid
    end

    it 'reports pending? while the totals are unset' do
      expect(build(:liquidacion, :pending)).to be_pending
      expect(build(:liquidacion)).not_to be_pending
    end

    it 'rejects a partially calculated run (some totals set, others nil)' do
      liquidacion = build(:liquidacion, :pending, haberes_totales_cents: 1000)

      expect(liquidacion).not_to be_valid
      expect(liquidacion.errors[:base]).to be_present
    end
  end

  describe 'uniqueness' do
    it 'rejects duplicate employee+period pairs' do
      employee = create(:employee)
      create(:liquidacion, employee: employee, period_year: 2026, period_month: 7)
      duplicate = build(:liquidacion, employee: employee, period_year: 2026, period_month: 7)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:period_month]).to be_present
    end

    it 'allows the same month in a different year' do
      employee = create(:employee)
      create(:liquidacion, employee: employee, period_year: 2025, period_month: 7)
      other_year = build(:liquidacion, employee: employee, period_year: 2026, period_month: 7)
      expect(other_year).to be_valid
    end
  end

  describe 'final_salary consistency' do
    it 'rejects final_salary different from haberes - descuentos' do
      liquidacion = build(:liquidacion, haberes_totales_cents: 1000, descuentos_totales_cents: 200, final_salary_cents: 900)
      expect(liquidacion).not_to be_valid
      expect(liquidacion.errors[:final_salary_cents]).to be_present
    end

    it 'accepts final_salary equal to haberes - descuentos' do
      liquidacion = build(:liquidacion, haberes_totales_cents: 1000, descuentos_totales_cents: 200, final_salary_cents: 800)
      expect(liquidacion).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:employee) }
    it { is_expected.to have_many(:asignaciones).dependent(:destroy) }
  end
end
