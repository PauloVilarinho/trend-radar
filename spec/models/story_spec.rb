require "rails_helper"

RSpec.describe Story, type: :model do
  describe "validations" do
    it "requires hn_id" do
      expect(build(:story, hn_id: nil)).not_to be_valid
    end

    it "enforces uniqueness on hn_id" do
      create(:story, hn_id: 999_999_999)
      expect(build(:story, hn_id: 999_999_999)).not_to be_valid
    end
  end

  describe "#age_hours" do
    it "returns hours since hn_created_at" do
      s = build(:story, hn_created_at: 6.hours.ago)
      expect(s.age_hours).to be_within(0.1).of(6.0)
    end

    it "returns nil when hn_created_at is unset" do
      expect(build(:story, hn_created_at: nil).age_hours).to be_nil
    end
  end

  describe "#active?" do
    it "is true by default" do
      expect(build(:story).active?).to be true
    end

    it "is false when archived" do
      expect(build(:story, tracking_status: "archived").active?).to be false
    end
  end

  describe "#archive!" do
    it "sets status and timestamp" do
      story = create(:story)
      story.archive!
      expect(story.tracking_status).to eq("archived")
      expect(story.archived_at).to be_present
    end
  end
end
