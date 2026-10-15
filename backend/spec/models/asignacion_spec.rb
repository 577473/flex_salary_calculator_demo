require 'rails_helper'

RSpec.describe Asignacion, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:formula) }
    it { is_expected.to validate_presence_of(:formula_version) }
    it { is_expected.to validate_presence_of(:position) }
  end

  describe 'amount_cents (calculator output)' do
    it 'is optional: a freshly assigned item has no amount yet' do
      asignacion = build(:asignacion, :pending)

      expect(asignacion).to be_valid
      expect(asignacion).not_to be_calculated
    end

    it 'must be an integer when present' do
      expect(build(:asignacion, amount_cents: 10.5)).not_to be_valid
    end

    it 'is calculated once an amount is present' do
      expect(build(:asignacion, amount_cents: 500)).to be_calculated
    end
  end

  describe 'category' do
    it 'exposes haber/descuento/aporte values' do
      expect(described_class.categories.keys).to contain_exactly('haber', 'descuento', 'aporte')
    end

    it 'rejects an invalid category' do
      expect { build(:asignacion, category: 'bonus') }.to raise_error(ArgumentError)
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:liquidacion) }
    it { is_expected.to belong_to(:template).class_name('AsignacionTemplate') }
  end
end
