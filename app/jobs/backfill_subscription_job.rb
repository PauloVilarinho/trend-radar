class BackfillSubscriptionJob < ApplicationJob
  queue_as :default

  BACKFILL_WINDOW = 24.hours

  def perform(topic_subscription_id)
    subscription = TopicSubscription.find_by(id: topic_subscription_id)
    return unless subscription
    return unless subscription.topic.active?

    Story.active.where("hn_created_at > ?", BACKFILL_WINDOW.ago).find_each do |story|
      MatchJob.perform_later(story.id)
    end
  end
end
