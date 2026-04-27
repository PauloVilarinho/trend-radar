require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  describe "GET /" do
    context "when unauthenticated" do
      it "redirects to sign in" do
        get "/"
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      let(:user) { create(:user) }
      before { sign_in user }

      it "renders the dashboard inertia page" do
        get "/"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("dashboard/index")
      end

      it "renders matches for topics this user subscribes to, sorted by matched_at desc" do
        subscribed = create(:topic)
        unsubscribed = create(:topic)
        create(:topic_subscription, user: user, topic: subscribed)

        story_old = create(:story, title: "Older story")
        story_new = create(:story, title: "Newer story")
        story_other = create(:story, title: "Other-topic story")

        create(:match, story: story_old, topic: subscribed,
                       matched_at: 2.hours.ago, reason: "Older match")
        create(:match, story: story_new, topic: subscribed,
                       matched_at: 10.minutes.ago, reason: "Newer match")
        create(:match, topic: subscribed, dismissed_at: Time.current, reason: "Hidden")
        create(:match, story: story_other, topic: unsubscribed, reason: "Not subscribed")

        get "/"

        body = response.body
        expect(body).to include("dashboard/index")
        expect(body.index("Newer match")).to be < body.index("Older match")
        expect(body).not_to include("Hidden")
        expect(body).not_to include("Not subscribed")
      end
    end
  end
end
