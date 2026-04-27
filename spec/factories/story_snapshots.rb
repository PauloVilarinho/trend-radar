FactoryBot.define do
  factory :story_snapshot do
    story
    score { 10 }
    descendants { 2 }
    captured_at { Time.current }
  end
end
