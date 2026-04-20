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
    end
  end
end
