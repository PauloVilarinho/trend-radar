class MatchJob < ApplicationJob
  queue_as :default

  def perform(story_id)
    story = Story.find(story_id)
    return if story.archived?
    return unless within_daily_budget?

    candidate_topics = KeywordMatcher.matching_topics(story, Topic.where(active: true))
    return if candidate_topics.empty?

    classify_each(story, candidate_topics)
  end

  private

  def classify_each(story, candidate_topics)
    matcher = Openai::Matcher.new
    threshold = TrackingConfig.match[:min_relevance_score]

    candidate_topics.each do |topic|
      next if Match.exists?(story_id: story.id, topic_id: topic.id)

      result = matcher.call(story: story, topic: topic)
      record_classification

      match = create_match!(story, topic, result)
      NotifyJob.perform_later(match.id) if match && result[:score] >= threshold
    end
  end

  def create_match!(story, topic, result)
    Match.create!(
      story: story,
      topic: topic,
      relevance_score: result[:score],
      reason: result[:reason],
      velocity_score: current_velocity(story),
      matched_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def current_velocity(story)
    snapshots = story.story_snapshots.order(:captured_at).last(2)
    VelocityCalculator.current_velocity(snapshots) || 0.0
  end

  def within_daily_budget?
    today_count < TrackingConfig.match[:daily_classification_budget]
  end

  def record_classification
    Rails.cache.increment(classification_cache_key, 1, expires_in: 36.hours)
  end

  def today_count
    (Rails.cache.read(classification_cache_key) || 0).to_i
  end

  def classification_cache_key
    "openai:classifications:#{Date.current}"
  end
end
