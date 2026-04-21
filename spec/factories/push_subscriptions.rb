FactoryBot.define do
  factory :push_subscription do
    user
    sequence(:endpoint) { |n| "https://push.example.com/#{n}" }
    p256dh_key { "sample-p256dh-key" }
    auth_key { "sample-auth-key" }
    user_agent { "Mozilla/5.0" }
  end
end
