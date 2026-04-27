require "rails_helper"

RSpec.describe Match, type: :model do
  it "belongs to story and topic" do
    match = build(:match)
    expect(match).to be_valid
  end

  it "enforces uniqueness on (story, topic)" do
    m = create(:match)
    dup = build(:match, story: m.story, topic: m.topic)
    expect(dup).not_to be_valid
  end

  it "is visible when not dismissed and not posted and above threshold" do
    m = create(:match)
    expect(Match.visible).to include(m)
  end

  it "is hidden when dismissed" do
    m = create(:match, dismissed_at: Time.current)
    expect(Match.visible).not_to include(m)
  end

  it "is hidden when posted" do
    m = create(:match, posted_at: Time.current)
    expect(Match.visible).not_to include(m)
  end

  it "is hidden when relevance_score is below threshold (rejected classification)" do
    m = create(:match, relevance_score: 0.4)
    expect(Match.visible).not_to include(m)
  end
end
