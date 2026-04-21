require "rails_helper"

RSpec.describe "Topics", type: :request do
  let(:user) { create(:user) }

  describe "GET /topics" do
    context "unauthenticated" do
      it "redirects to sign in" do
        get "/topics"
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "authenticated" do
      before { sign_in user }

      it "renders only active topics" do
        create(:topic, name: "Active one")
        create(:topic, name: "Hidden one", active: false)

        get "/topics"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("topics/index")
        expect(response.body).to include("Active one")
        expect(response.body).not_to include("Hidden one")
      end

      it "surfaces subscription state in props" do
        topic = create(:topic, name: "Subbed")
        create(:topic_subscription, user: user, topic: topic,
                                    discord_webhook: "https://discord.com/api/webhooks/1/a",
                                    active: false)
        create(:topic, name: "Unsubbed")

        get "/topics"

        expect(response.body).to include("Subbed")
        expect(response.body).to include("Unsubbed")
        # props JSON embedded in Inertia response
        expect(response.body).to include("subscribed")
      end
    end
  end
end
