class FetchFeedsJob < ApplicationJob
  queue_as :default

  YOUNG_AGE_HOURS = 6
  YOUNG_REPOLL_MINUTES = 5
  DEFAULT_REPOLL_MINUTES = 30

  def perform(mode = "frequent")
    enqueue_feed_ids(mode)
    enqueue_young_repolls
    enqueue_default_repolls
  end

  private

  def enqueue_feed_ids(mode)
    client = Hn::Client.new
    ids = Set.new
    ids.merge(client.top_story_ids)
    ids.merge(client.new_story_ids)
    ids.merge(client.best_story_ids) if mode == "full"
    ids.each { |id| FetchStoryJob.perform_later(id) }
  end

  def enqueue_young_repolls
    Story.active
         .where("hn_created_at > ?", YOUNG_AGE_HOURS.hours.ago)
         .where("last_polled_at < ?", YOUNG_REPOLL_MINUTES.minutes.ago)
         .find_each { |s| FetchStoryJob.perform_later(s.hn_id) }
  end

  def enqueue_default_repolls
    Story.active
         .where("hn_created_at <= ?", YOUNG_AGE_HOURS.hours.ago)
         .where("last_polled_at < ?", DEFAULT_REPOLL_MINUTES.minutes.ago)
         .find_each { |s| FetchStoryJob.perform_later(s.hn_id) }
  end
end
