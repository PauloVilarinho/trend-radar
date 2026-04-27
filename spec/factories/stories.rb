FactoryBot.define do
  factory :story do
    sequence(:hn_id) { |n| 44_000_000 + n }
    title { "Example story" }
    url { "https://example.com/article" }
    by { "alice" }
    score { 10 }
    descendants { 2 }
    story_type { "story" }
    hn_created_at { 1.hour.ago }
    first_seen_at { 1.hour.ago }
    last_polled_at { Time.current }
    tracking_status { "active" }
  end
end
