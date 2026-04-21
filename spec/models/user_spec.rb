require "rails_helper"

RSpec.describe User, type: :model do
  describe "defaults" do
    it "defaults admin to false" do
      user = create(:user)
      expect(user.admin).to eq(false)
    end

    it "can be marked admin via trait" do
      user = create(:user, :admin)
      expect(user.admin).to eq(true)
    end
  end

  describe "associations" do
    let(:user) { create(:user) }

    it "has_many subscribed_topics through topic_subscriptions" do
      topic = create(:topic)
      create(:topic_subscription, user: user, topic: topic)
      expect(user.subscribed_topics).to include(topic)
    end

    it "has_many created_topics via created_by_id" do
      topic = create(:topic, created_by: user)
      expect(user.created_topics).to include(topic)
    end

    it "nullifies created_topics when the creator is destroyed" do
      topic = create(:topic, created_by: user)
      user.destroy!
      expect(topic.reload.created_by_id).to be_nil
    end

    it "destroys topic_subscriptions when the user is destroyed" do
      create(:topic_subscription, user: user, topic: create(:topic))
      expect { user.destroy! }.to change(TopicSubscription, :count).by(-1)
    end
  end
end
