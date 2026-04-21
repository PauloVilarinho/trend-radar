require "rails_helper"

RSpec.describe TopicSubscription, type: :model do
  describe "validations" do
    let(:user) { create(:user) }
    let(:topic) { create(:topic) }

    it "is valid with minimum required attributes" do
      expect(build(:topic_subscription, user: user, topic: topic)).to be_valid
    end

    it "allows nil discord_webhook" do
      expect(build(:topic_subscription, user: user, topic: topic, discord_webhook: nil)).to be_valid
    end

    it "validates discord_webhook format when present" do
      sub = build(:topic_subscription, user: user, topic: topic,
                                        discord_webhook: "https://example.com/webhook")
      expect(sub).not_to be_valid
      expect(sub.errors[:discord_webhook]).to be_present
    end

    it "accepts valid discord webhook URLs" do
      sub = build(:topic_subscription, user: user, topic: topic,
                                        discord_webhook: "https://discord.com/api/webhooks/123/abc")
      expect(sub).to be_valid
    end

    it "requires a unique (user, topic) pair" do
      create(:topic_subscription, user: user, topic: topic)
      dup = build(:topic_subscription, user: user, topic: topic)
      expect(dup).not_to be_valid
      expect(dup.errors[:topic_id]).to be_present
    end
  end

  describe "per-user subscription limit" do
    let(:user) { create(:user) }

    it "rejects creating a 51st subscription for a user" do
      50.times { create(:topic_subscription, user: user, topic: create(:topic)) }
      over = build(:topic_subscription, user: user, topic: create(:topic))
      expect(over).not_to be_valid
      expect(over.errors[:base]).to include(/limit/i)
    end
  end
end
