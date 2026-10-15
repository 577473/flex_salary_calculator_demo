FactoryBot.define do
  factory :employee do
    sequence(:name) { |n| "Empleado #{n}" }

    trait :with_job do
      after(:create) { |employee| create(:job, employee: employee) }
    end
  end
end
