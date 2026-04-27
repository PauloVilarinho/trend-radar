class PruneSnapshotsJob < ApplicationJob
  queue_as :low

  def perform
    cutoff = TrackingConfig.snapshot_retention_days.days.ago
    StorySnapshot.where("captured_at < ?", cutoff).delete_all
  end
end
