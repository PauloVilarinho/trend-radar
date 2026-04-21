require "rails_helper"

RSpec.describe "TopicSubscriptions", type: :request do
  let(:user) { create(:user) }
  let(:topic) { create(:topic) }

  describe "POST /topics/:topic_id/subscription" do
    context "unauthenticated" do
      it "redirects to sign in" do
        post "/topics/#{topic.id}/subscription"
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "authenticated" do
      before { sign_in user }

      it "creates a subscription" do
        expect {
          post "/topics/#{topic.id}/subscription"
        }.to change(TopicSubscription, :count).by(1)
        expect(response).to redirect_to(topics_path)
      end

      it "accepts a discord_webhook on create" do
        post "/topics/#{topic.id}/subscription", params: {
          topic_subscription: { discord_webhook: "https://discord.com/api/webhooks/1/tok" }
        }
        expect(TopicSubscription.last.discord_webhook).to eq("https://discord.com/api/webhooks/1/tok")
      end

      it "renders index with errors on double subscribe" do
        create(:topic_subscription, user: user, topic: topic)
        post "/topics/#{topic.id}/subscription"
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects bad discord webhook format" do
        post "/topics/#{topic.id}/subscription", params: {
          topic_subscription: { discord_webhook: "https://bad.example/foo" }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH /topics/:topic_id/subscription" do
    before { sign_in user }

    it "updates webhook and active flag on user's own subscription" do
      sub = create(:topic_subscription, user: user, topic: topic)
      patch "/topics/#{topic.id}/subscription", params: {
        topic_subscription: { discord_webhook: "https://discord.com/api/webhooks/9/zz", active: false }
      }
      expect(response).to redirect_to(topics_path)
      sub.reload
      expect(sub.discord_webhook).to eq("https://discord.com/api/webhooks/9/zz")
      expect(sub.active).to eq(false)
    end

    it "does not touch other users' subscriptions" do
      other = create(:user)
      create(:topic_subscription, user: other, topic: topic)
      patch "/topics/#{topic.id}/subscription", params: {
        topic_subscription: { active: false }
      }
      expect(response).to have_http_status(:not_found).or redirect_to(topics_path)
    end
  end

  describe "DELETE /topics/:topic_id/subscription" do
    before { sign_in user }

    it "destroys the user's subscription" do
      create(:topic_subscription, user: user, topic: topic)
      expect {
        delete "/topics/#{topic.id}/subscription"
      }.to change(TopicSubscription, :count).by(-1)
      expect(response).to redirect_to(topics_path)
    end

    it "does not destroy other users' subscriptions" do
      other = create(:user)
      create(:topic_subscription, user: other, topic: topic)
      expect {
        delete "/topics/#{topic.id}/subscription"
      }.not_to change(TopicSubscription, :count)
    end
  end
end
