require "rails_helper"

RSpec.describe Topic, type: :model do
  describe "validations" do
    it "is valid with minimum required attributes" do
      expect(build(:topic)).to be_valid
    end

    it "requires a name" do
      t = build(:topic, name: nil)
      expect(t).not_to be_valid
      expect(t.errors[:name]).to be_present
    end

    it "requires a globally unique name (case-insensitive)" do
      create(:topic, name: "AI")
      expect(build(:topic, name: "AI")).not_to be_valid
      expect(build(:topic, name: "ai")).not_to be_valid
      expect(build(:topic, name: "Ai")).not_to be_valid
    end

    it "requires at least one keyword" do
      t = build(:topic, keywords: [])
      expect(t).not_to be_valid
      expect(t.errors[:keywords]).to be_present
    end

    it "rejects more than 20 keywords" do
      t = build(:topic, keywords: Array.new(21) { |i| "kw#{i}" })
      expect(t).not_to be_valid
      expect(t.errors[:keywords]).to include(/too many/i)
    end

    it "rejects blank keyword strings" do
      expect(build(:topic, keywords: [ "valid", "", "  " ])).not_to be_valid
    end
  end

  describe "associations" do
    it "allows nil created_by (admin deletion nullifies)" do
      expect(build(:topic, created_by: nil)).to be_valid
    end

    it "has_many topic_subscriptions and subscribers" do
      topic = create(:topic)
      user = create(:user)
      create(:topic_subscription, user: user, topic: topic)
      expect(topic.topic_subscriptions.count).to eq(1)
      expect(topic.subscribers).to include(user)
    end
  end
end
