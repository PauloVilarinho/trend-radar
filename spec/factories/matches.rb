FactoryBot.define do
  factory :match do
    story
    topic
    relevance_score { 0.8 }
    reason { "Directly discusses AI agents." }
    velocity_score { 20.0 }
    matched_at { Time.current }
  end
end
