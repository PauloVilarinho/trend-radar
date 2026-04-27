require "rails_helper"

RSpec.describe "Matches", type: :request do
  let(:user) { create(:user) }
  let(:topic) { create(:topic) }
  let!(:_subscription) { create(:topic_subscription, user: user, topic: topic) }
  let(:match) { create(:match, topic: topic) }

  before { sign_in user }

  describe "POST /matches/:id/mark_posted" do
    it "sets posted_at and redirects to dashboard" do
      post "/matches/#{match.id}/mark_posted"
      expect(match.reload.posted_at).to be_present
      expect(response).to redirect_to(root_path)
    end

    it "404s for a match on a topic the user is not subscribed to" do
      other_topic = create(:topic)
      other = create(:match, topic: other_topic)
      post "/matches/#{other.id}/mark_posted"
      expect(response).to have_http_status(:not_found)
      expect(other.reload.posted_at).to be_nil
    end
  end

  describe "POST /matches/:id/dismiss" do
    it "sets dismissed_at" do
      post "/matches/#{match.id}/dismiss"
      expect(match.reload.dismissed_at).to be_present
    end
  end
end
