require "rails_helper"

RSpec.describe StoryArchiver do
  describe ".archive_if_stale!" do
    it "archives a story past the hard cutoff" do
      story = create(:story, hn_created_at: 80.hours.ago)
      described_class.archive_if_stale!(story)
      expect(story).to be_archived
    end

    it "archives a story that has cooled off (low velocity over the recent window)" do
      story = create(:story, hn_created_at: 24.hours.ago)
      base_time = 4.hours.ago
      [ [ base_time, 100 ], [ base_time + 30.minutes, 101 ], [ base_time + 1.hour, 102 ],
       [ base_time + 1.5.hours, 103 ] ].each do |captured_at, score|
        create(:story_snapshot, story: story, score: score, captured_at: captured_at)
      end
      described_class.archive_if_stale!(story)
      expect(story).to be_archived
    end

    it "archives a story that has flatlined (identical recent snapshots)" do
      story = create(:story, hn_created_at: 2.hours.ago)
      base_time = 1.hour.ago
      4.times do |i|
        create(:story_snapshot, story: story, score: 50, descendants: 5,
                                captured_at: base_time + (i * 10).minutes)
      end
      described_class.archive_if_stale!(story)
      expect(story).to be_archived
    end

    it "does not archive a young, climbing story" do
      story = create(:story, hn_created_at: 30.minutes.ago)
      base_time = 25.minutes.ago
      [ [ base_time, 10 ], [ base_time + 5.minutes, 30 ], [ base_time + 10.minutes, 60 ] ].each do |t, s|
        create(:story_snapshot, story: story, score: s, captured_at: t)
      end
      described_class.archive_if_stale!(story)
      expect(story).to be_active
    end

    it "does not archive when there are too few snapshots to judge" do
      story = create(:story, hn_created_at: 2.hours.ago)
      create(:story_snapshot, story: story, score: 50, captured_at: 1.hour.ago)
      described_class.archive_if_stale!(story)
      expect(story).to be_active
    end
  end
end
