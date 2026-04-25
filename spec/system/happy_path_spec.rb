require "rails_helper"

RSpec.describe "Happy path: admin creates topic, user subscribes", type: :system do
  before { driven_by(:rack_test) }

  let(:admin) { create(:user, admin: true) }
  let(:user) { create(:user) }

  it "admin creates a topic and a regular user subscribes" do
    sign_in admin
    page.driver.post "/admin/topics", topic: {
      name: "Kubernetes", keywords: [ "k8s", "kubernetes" ], active: true
    }
    expect(Topic.where(name: "Kubernetes")).to exist

    Warden.test_reset!

    sign_in user
    topic = Topic.find_by!(name: "Kubernetes")

    visit "/topics"
    expect(page.body).to include("Kubernetes")

    page.driver.post "/topics/#{topic.id}/subscription"
    expect(TopicSubscription.where(user: user, topic: topic)).to exist

    if defined?(Story) && defined?(Match)
      story = create(:story, title: "Kubernetes 2.0 announced")
      create(:match, story: story, topic: topic, reason: "Kubernetes release")

      visit "/"
      expect(page).to have_content("Kubernetes 2.0 announced")
    end

    page.driver.delete "/topics/#{topic.id}/subscription"
    expect(TopicSubscription.where(user: user, topic: topic)).not_to exist
  end
end
