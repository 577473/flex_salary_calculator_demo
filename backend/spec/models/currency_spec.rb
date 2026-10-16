require 'rails_helper'

RSpec.describe Currency do
  describe '.for_country' do
    it 'maps the seeded jurisdictions to their local currency' do
      expect(described_class.for_country('ar')).to eq('ARS')
      expect(described_class.for_country('UY')).to eq('UYU')
    end

    it 'returns nil for a jurisdiction without a known local currency' do
      expect(described_class.for_country('BR')).to be_nil
      expect(described_class.for_country(nil)).to be_nil
    end
  end
end
