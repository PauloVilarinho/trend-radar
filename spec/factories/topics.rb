FactoryBot.define do
  factory :topic do
    sequence(:name) { |n| "Topic #{n}" }
    keywords { [ "AI", "machine learning" ] }
    active { true }

    trait :with_creator do
      association :created_by, factory: :user
    end
  end
end
