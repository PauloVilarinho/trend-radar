require "rails_helper"

RSpec.describe FetchStoryJob, type: :job do
  let(:hn_id) { 44_000_123 }
  let(:item_url) { "https://hacker-news.firebaseio.com/v0/item/#{hn_id}.json" }

  def stub_item(attrs = {})
    defaults = {
      id: hn_id, type: "story", by: "alice", title: "Hello",
      url: "https://example.com", score: 42, descendants: 7,
      time: 30.minutes.ago.to_i
    }
    stub_request(:get, item_url).to_return(
      status: 200,
      body: defaults.merge(attrs).to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  describe "on first fetch of a new story" do
    before { stub_item }

    it "creates story + snapshot and enqueues MatchJob (new story is always candidate)" do
      expect {
        FetchStoryJob.new.perform(hn_id)
      }.to change(Story, :count).by(1)
       .and change(StorySnapshot, :count).by(1)

      expect(MatchJob).to have_been_enqueued.with(Story.last.id)
    end
  end

  describe "on subsequent fetch of an existing story" do
    let!(:story) do
      create(:story, hn_id: hn_id, score: 20, descendants: 3,
                     hn_created_at: 2.hours.ago, first_seen_at: 2.hours.ago,
                     last_polled_at: 1.hour.ago)
    end

    before do
      create(:story_snapshot, story: story, score: 20, descendants: 3, captured_at: 1.hour.ago)
    end

    it "updates score + inserts snapshot + does not enqueue when velocity below threshold" do
      stub_item(score: 22, descendants: 4)

      expect { FetchStoryJob.new.perform(hn_id) }.not_to have_enqueued_job(MatchJob)
      expect(story.reload.score).to eq(22)
      expect(story.story_snapshots.count).to eq(2)
    end

    it "enqueues MatchJob when velocity crosses threshold" do
      stub_item(score: 60, descendants: 10)
      expect { FetchStoryJob.new.perform(hn_id) }.to have_enqueued_job(MatchJob).with(story.id)
    end
  end

  describe "archival decisions" do
    let!(:story) do
      create(:story, hn_id: hn_id,
                     hn_created_at: 80.hours.ago,
                     first_seen_at: 80.hours.ago,
                     last_polled_at: 30.minutes.ago,
                     score: 100)
    end

    before { stub_item(score: 100, time: 80.hours.ago.to_i) }

    it "archives stories older than hard cutoff" do
      FetchStoryJob.new.perform(hn_id)
      expect(story.reload).to be_archived
    end
  end

  describe "items missing the time field" do
    it "leaves hn_created_at nil and uses first_seen_at as the timeline" do
      stub_request(:get, item_url).to_return(
        status: 200,
        body: { id: hn_id, type: "story", title: "Hello", score: 1, descendants: 0 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      FetchStoryJob.new.perform(hn_id)
      story = Story.find_by(hn_id: hn_id)
      expect(story.hn_created_at).to be_nil
      expect(story.first_seen_at).to be_present
    end
  end

  describe "deleted stories" do
    it "archives if already tracked, otherwise no-op" do
      create(:story, hn_id: hn_id)
      stub_request(:get, item_url).to_return(
        status: 200, body: '{"id":44000123,"deleted":true}',
        headers: { "Content-Type" => "application/json" }
      )
      FetchStoryJob.new.perform(hn_id)
      expect(Story.find_by(hn_id: hn_id)).to be_archived
    end

    it "no-ops on a deleted story we never tracked" do
      stub_request(:get, item_url).to_return(
        status: 200, body: '{"id":44000123,"deleted":true}',
        headers: { "Content-Type" => "application/json" }
      )
      expect { FetchStoryJob.new.perform(hn_id) }.not_to change(Story, :count)
    end
  end
end
