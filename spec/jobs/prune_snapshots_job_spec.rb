require "rails_helper"

RSpec.describe PruneSnapshotsJob, type: :job do
  it "deletes snapshots older than retention window, keeps recent" do
    story = create(:story)
    old = create(:story_snapshot, story: story, captured_at: 10.days.ago)
    fresh = create(:story_snapshot, story: story, captured_at: 1.day.ago)

    PruneSnapshotsJob.new.perform

    expect { old.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect { fresh.reload }.not_to raise_error
  end
end
