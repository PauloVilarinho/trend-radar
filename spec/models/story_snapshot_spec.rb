require "rails_helper"

RSpec.describe StorySnapshot, type: :model do
  it "belongs to a story" do
    story = create(:story)
    snap = build(:story_snapshot, story: story)
    expect(snap).to be_valid
  end

  it "requires captured_at" do
    expect(build(:story_snapshot, captured_at: nil)).not_to be_valid
  end

  it "requires score" do
    expect(build(:story_snapshot, score: nil)).not_to be_valid
  end
end
