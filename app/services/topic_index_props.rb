# Builds the props payload for the topics catalog page. Shared between
# TopicsController#index and TopicSubscriptionsController re-render on error.
class TopicIndexProps
  def self.call(user, errors: {})
    new(user, errors: errors).call
  end

  def initialize(user, errors: {})
    @user = user
    @errors = errors
  end

  def call
    subscriptions_by_topic = @user.topic_subscriptions.index_by(&:topic_id)
    {
      topics: Topic.where(active: true).order(:name).map { |t|
        topic_props(t, subscriptions_by_topic[t.id])
      },
      errors: @errors
    }
  end

  private

  def topic_props(topic, subscription)
    {
      id: topic.id,
      name: topic.name,
      keywords: topic.keywords,
      subscribed: subscription.present?,
      paused: subscription.present? && !subscription.active,
      discord_webhook: subscription&.discord_webhook
    }
  end
end
