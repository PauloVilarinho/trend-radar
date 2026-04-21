require "rails_helper"

RSpec.describe "Admin::Topics", type: :request do
  describe "require_admin!" do
    context "unauthenticated" do
      it "redirects to sign in" do
        get "/admin/topics"
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "non-admin user" do
      let(:user) { create(:user) }
      before { sign_in user }

      it "redirects to root with alert" do
        get "/admin/topics"
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(flash[:alert] || response.body).to include("Admins only.")
      end

      it "blocks admin create" do
        expect {
          post "/admin/topics", params: { topic: { name: "Nope", keywords: [ "x" ] } }
        }.not_to change(Topic, :count)
      end
    end
  end

  context "admin user" do
    let(:admin) { create(:user, :admin) }
    before { sign_in admin }

    describe "GET /admin/topics" do
      it "renders the admin topics index" do
        create(:topic, name: "Alpha")
        get "/admin/topics"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("admin/topics/index")
        expect(response.body).to include("Alpha")
      end
    end

    describe "GET /admin/topics/new" do
      it "renders the new topic form" do
        get "/admin/topics/new"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("admin/topics/new")
      end
    end

    describe "POST /admin/topics" do
      it "creates a topic and tracks created_by" do
        expect {
          post "/admin/topics", params: {
            topic: { name: "Rust", keywords: [ "rust lang", "cargo" ] }
          }
        }.to change(Topic, :count).by(1)
        expect(Topic.last.created_by).to eq(admin)
        expect(response).to redirect_to(admin_topics_path)
      end

      it "renders new on invalid params" do
        post "/admin/topics", params: { topic: { name: "", keywords: [] } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("admin/topics/new")
      end

      it "surfaces unique name conflicts" do
        create(:topic, name: "Dupe")
        post "/admin/topics", params: { topic: { name: "dupe", keywords: [ "x" ] } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("admin/topics/new")
      end
    end

    describe "GET /admin/topics/:id/edit" do
      it "renders the edit form" do
        topic = create(:topic)
        get "/admin/topics/#{topic.id}/edit"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("admin/topics/edit")
      end
    end

    describe "PATCH /admin/topics/:id" do
      it "updates a topic" do
        topic = create(:topic, name: "Old")
        patch "/admin/topics/#{topic.id}", params: {
          topic: { name: "New", keywords: [ "kw" ], active: false }
        }
        expect(response).to redirect_to(admin_topics_path)
        topic.reload
        expect(topic.name).to eq("New")
        expect(topic.active).to eq(false)
      end

      it "re-renders edit on validation failure" do
        topic = create(:topic)
        patch "/admin/topics/#{topic.id}", params: {
          topic: { name: "", keywords: [] }
        }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("admin/topics/edit")
      end
    end
  end
end
