class FetchStoryJob < ApplicationJob
  queue_as :default

  def perform(hn_id)
    data = Hn::Client.new.item(hn_id)

    if data.nil?
      handle_missing(hn_id)
      return
    end

    story, was_new = upsert_story(hn_id, data)
    capture_snapshot(story)

    return unless story.active?

    StoryArchiver.archive_if_stale!(story)
    return unless story.active?

    MatchJob.perform_later(story.id) if was_new || velocity_candidate?(story)
  end

  private

  def handle_missing(hn_id)
    existing = Story.find_by(hn_id: hn_id)
    existing.archive! if existing&.active?
  end

  def upsert_story(hn_id, data)
    story = Story.find_or_initialize_by(hn_id: hn_id)
    was_new = story.new_record?
    apply_item_attributes(story, data)
    story.save!
    [ story, was_new ]
  end

  COPY_ATTRIBUTES = {
    title: :title, url: :url, by: :by, story_type: :type, text: :text
  }.freeze

  def apply_item_attributes(story, data)
    COPY_ATTRIBUTES.each { |attr, key| story[attr] = data[key] }
    story.score = data[:score] || 0
    story.descendants = data[:descendants] || 0
    apply_timestamps(story, data)
  end

  def apply_timestamps(story, data)
    story.hn_created_at ||= Time.zone.at(data[:time]) if data[:time]
    story.first_seen_at ||= Time.current
    story.last_polled_at = Time.current
  end

  def capture_snapshot(story)
    story.story_snapshots.create!(
      score: story.score,
      descendants: story.descendants,
      captured_at: Time.current
    )
  end

  def velocity_candidate?(story)
    cfg = TrackingConfig.velocity_candidate_threshold
    velocity = VelocityCalculator.current_velocity(story.story_snapshots.order(:captured_at).last(2))
    return false if velocity.nil?

    velocity >= cfg[:points_per_hour] && story.score >= cfg[:minimum_score]
  end
end
