class Employee < ApplicationRecord
  has_many :jobs, dependent: :destroy
  has_many :liquidaciones, dependent: :destroy

  validates :name, presence: true, length: { maximum: 200 }
end
