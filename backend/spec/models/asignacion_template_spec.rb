require 'rails_helper'

RSpec.describe AsignacionTemplate, type: :model do
  subject { build(:asignacion_template) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:formula) }
    it { is_expected.to validate_presence_of(:effective_from) }
  end

  describe 'category' do
    it 'exposes haber/descuento/aporte values' do
      expect(described_class.categories.keys).to contain_exactly('haber', 'descuento', 'aporte')
    end

    it 'rejects an invalid category' do
      expect { build(:asignacion_template, category: 'bonus') }.to raise_error(ArgumentError)
    end

    it 'allows multiple templates within the same category' do
      create(:asignacion_template, description: 'Sueldo base', category: 'haber')
      another = build(:asignacion_template, description: 'Bono fijo', category: 'haber')
      expect(another).to be_valid
    end

    it 'rejects a duplicate description within the same category' do
      create(:asignacion_template, description: 'Sueldo base', category: 'haber')
      duplicate = build(:asignacion_template, description: 'Sueldo base', category: 'haber')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:description]).to be_present
    end

    it 'allows the same description in a different category' do
      create(:asignacion_template, description: 'Sueldo base', category: 'haber')
      other = build(:asignacion_template, description: 'Sueldo base', category: 'aporte')
      expect(other).to be_valid
    end
  end

  describe 'version default' do
    it 'defaults to 1' do
      expect(described_class.new.version).to eq(1)
    end
  end

  describe 'effective range' do
    it 'rejects effective_to before effective_from' do
      template = build(:asignacion_template, effective_from: Date.new(2026, 6, 1), effective_to: Date.new(2026, 1, 1))
      expect(template).not_to be_valid
    end

    it 'covers an open-ended range forever' do
      template = build(:asignacion_template)
      expect(template.covers?(Date.new(2099, 12, 31))).to be(true)
    end
  end
end
