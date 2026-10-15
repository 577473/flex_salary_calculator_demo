require 'rails_helper'

RSpec.describe Employee, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(200) }
  end

  describe 'associations' do
    it { is_expected.to have_many(:jobs).dependent(:destroy) }
    it { is_expected.to have_many(:liquidaciones).dependent(:destroy) }
  end
end
