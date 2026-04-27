FactoryBot.define do
  factory :notification do
    match
    channel { "web_push" }
    status { "pending" }
    association :target, factory: :push_subscription
  end
end
