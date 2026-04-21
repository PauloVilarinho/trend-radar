FactoryBot.define do
  factory :topic_subscription do
    user
    topic
    discord_webhook { nil }
    active { true }
  end
end
