class StoryArchiver
  class << self
    def archive_if_stale!(story)
      story.archive! if stale?(story)
    end

    private

    def stale?(story)
      cfg = TrackingConfig.archive
      return true if past_hard_cutoff?(story, cfg)

      snapshots = recent_snapshots(story, cfg)
      cooled_off?(story, snapshots, cfg) || StoryFlatlineDetector.flat?(snapshots, cfg)
    end

    def recent_snapshots(story, cfg)
      story.story_snapshots.order(:captured_at).last(cfg[:flat_snapshots_required] + 1)
    end

    def past_hard_cutoff?(story, cfg)
      age = story.age_hours
      age && age > cfg[:hard_cutoff_hours]
    end

    def cooled_off?(story, snapshots, cfg)
      return false unless cooling_age_reached?(story, cfg)

      velocities = VelocityCalculator.rolling_points_per_hour(snapshots)
      required = cfg[:flat_snapshots_required]
      return false if velocities.size < required

      velocities.last(required).all? { |v| v < cfg[:cooling_points_per_hour] }
    end

    def cooling_age_reached?(story, cfg)
      age = story.age_hours
      age && age > cfg[:cooling_age_hours]
    end
  end
end
