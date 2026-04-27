require "rails_helper"

RSpec.describe BackfillSubscriptionJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let!(:topic) { create(:topic, keywords: [ "agent" ]) }
  let!(:subscription) { create(:topic_subscription, user: user, topic: topic) }

  before { clear_enqueued_jobs }

  it "enqueues MatchJob for each active story from last 24 hours" do
    recent = create_list(:story, 3, hn_created_at: 2.hours.ago)
    create(:story, hn_created_at: 3.days.ago)

    BackfillSubscriptionJob.new.perform(subscription.id)

    recent.each do |story|
      expect(MatchJob).to have_been_enqueued.with(story.id)
    end
  end

  it "does nothing when the topic is inactive" do
    topic.update!(active: false)
    create(:story, hn_created_at: 1.hour.ago)

    BackfillSubscriptionJob.new.perform(subscription.id)

    expect(MatchJob).not_to have_been_enqueued
  end

  it "no-ops when the subscription has been deleted" do
    id = subscription.id
    subscription.destroy

    expect {
      BackfillSubscriptionJob.new.perform(id)
    }.not_to raise_error
  end

  it "skips archived stories" do
    create(:story, hn_created_at: 1.hour.ago, tracking_status: "archived")
    BackfillSubscriptionJob.new.perform(subscription.id)
    expect(MatchJob).not_to have_been_enqueued
  end
end
