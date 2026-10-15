require 'rails_helper'

RSpec.describe ItemSelector do
  describe '.call' do
    before do
      create(:asignacion_template, description: 'Salario', category: 'haber',
                                   effective_from: Date.new(2025, 1, 1))
      create(:asignacion_template, description: 'Aporte', category: 'aporte',
                                   effective_from: Date.new(2025, 1, 1))
      create(:asignacion_template, description: 'Descuento', category: 'descuento',
                                   effective_from: Date.new(2025, 1, 1))
    end

    it 'returns every template whose range covers the period' do
      descriptions = described_class.call(year: 2026, month: 3).map(&:description)
      expect(descriptions).to contain_exactly('Salario', 'Aporte', 'Descuento')
    end

    it 'orders by category haber, then descuento, then aporte' do
      order = described_class.call(year: 2026, month: 3).map(&:category)
      expect(order).to eq(%w[haber descuento aporte])
    end

    it 'orders within a category by effective_from then id' do
      create(:asignacion_template, description: 'Salario viejo', category: 'haber',
                                   effective_from: Date.new(2024, 1, 1))
      create(:asignacion_template, description: 'Salario nuevo', category: 'haber',
                                   effective_from: Date.new(2026, 1, 1))

      order = described_class.call(year: 2026, month: 3)
                                .select { |template| template.category == 'haber' }
                                .map(&:description)
      expect(order).to eq([ 'Salario viejo', 'Salario', 'Salario nuevo' ])
    end

    it 'excludes templates whose range does not contain the period' do
      older = create(:asignacion_template, description: 'Solo 2025', category: 'haber',
                                           effective_from: Date.new(2025, 1, 1),
                                           effective_to: Date.new(2025, 12, 31))

      selected = described_class.call(year: 2026, month: 3)
      expect(selected).not_to include(older)
    end

    it 'respects year-specific ranges' do
      yearly = create(:asignacion_template, description: 'Anual 2026', category: 'haber',
                                            effective_from: Date.new(2026, 1, 1),
                                            effective_to: Date.new(2026, 12, 31))

      expect(described_class.call(year: 2026, month: 3)).to include(yearly)
      expect(described_class.call(year: 2026, month: 12)).to include(yearly)
      expect(described_class.call(year: 2025, month: 3)).not_to include(yearly)
    end

    it 'includes open-ended templates for any future period' do
      permanent = create(:asignacion_template, description: 'Permanente', category: 'haber',
                                               effective_from: Date.new(2025, 1, 1),
                                               effective_to: nil)

      expect(described_class.call(year: 2099, month: 1)).to include(permanent)
    end
  end
end
