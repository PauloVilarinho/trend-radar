require "rails_helper"

RSpec.describe MatchJob, type: :job do
  include ActiveJob::TestHelper

  let(:story) { create(:story, title: "OpenAI ships new agent SDK") }

  before do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  def stub_matcher(score:, reason: "ok")
    matcher = instance_double(Openai::Matcher)
    allow(Openai::Matcher).to receive(:new).and_return(matcher)
    allow(matcher).to receive(:call).and_return({ score: score, reason: reason })
    matcher
  end

  context "with matching topic" do
    let!(:topic) { create(:topic, keywords: [ "agent", "llm" ]) }

    before do
      create(:story_snapshot, story: story, score: 60, captured_at: 30.minutes.ago)
      create(:story_snapshot, story: story, score: 90, captured_at: Time.current)
    end

    it "creates a Match (per story, topic) when score >= threshold" do
      stub_matcher(score: 0.8, reason: "Directly about agents")

      expect { MatchJob.new.perform(story.id) }.to change(Match, :count).by(1)

      match = Match.last
      expect(match.topic).to eq(topic)
      expect(match.relevance_score).to eq(0.8)
      expect(match.reason).to eq("Directly about agents")
      expect(match.velocity_score).to be > 0
    end

    it "still creates a Match when score below threshold but does NOT enqueue NotifyJob" do
      stub_matcher(score: 0.4, reason: "Tangentially related")

      expect { MatchJob.new.perform(story.id) }.to change(Match, :count).by(1)
      expect(NotifyJob).not_to have_been_enqueued

      match = Match.last
      expect(match.relevance_score).to eq(0.4)
    end

    it "is idempotent — does not re-classify or duplicate a match on re-run" do
      matcher = stub_matcher(score: 0.8)
      MatchJob.new.perform(story.id)

      expect { MatchJob.new.perform(story.id) }.not_to change(Match, :count)
      expect(matcher).to have_received(:call).once
    end

    it "does not re-classify a (story, topic) that was previously rejected" do
      matcher = stub_matcher(score: 0.4)
      MatchJob.new.perform(story.id)

      expect { MatchJob.new.perform(story.id) }.not_to change(Match, :count)
      expect(matcher).to have_received(:call).once
    end

    it "classifies once per topic regardless of subscriber count" do
      create_list(:topic_subscription, 3, topic: topic)
      matcher = stub_matcher(score: 0.8)

      MatchJob.new.perform(story.id)

      expect(matcher).to have_received(:call).once
      expect(Match.where(story: story, topic: topic).count).to eq(1)
    end

    it "enqueues NotifyJob for new matches above threshold" do
      stub_matcher(score: 0.8)
      expect { MatchJob.new.perform(story.id) }.to have_enqueued_job(NotifyJob)
    end
  end

  context "with no matching topic" do
    let!(:topic) { create(:topic, keywords: [ "kubernetes" ]) }

    it "does not call OpenAI" do
      expect(Openai::Matcher).not_to receive(:new)
      MatchJob.new.perform(story.id)
    end
  end

  context "inactive topics" do
    let!(:_inactive) { create(:topic, keywords: [ "agent" ], active: false) }

    it "is skipped by the prefilter" do
      expect(Openai::Matcher).not_to receive(:new)
      MatchJob.new.perform(story.id)
    end
  end

  context "archived story" do
    it "is a no-op" do
      story.archive!
      create(:topic, keywords: [ "agent" ])
      expect(Openai::Matcher).not_to receive(:new)
      MatchJob.new.perform(story.id)
    end
  end

  context "daily budget exceeded" do
    let!(:topic) { create(:topic, keywords: [ "agent" ]) }

    it "skips classification when today's classification count is at the budget" do
      allow(TrackingConfig).to receive(:match).and_return(
        min_relevance_score: 0.6, daily_classification_budget: 0
      )
      stub_matcher(score: 0.8)
      expect { MatchJob.new.perform(story.id) }.not_to change(Match, :count)
    end
  end
end
