require "rails_helper"

RSpec.describe KeywordMatcher do
  describe ".matches?" do
    let(:story) do
      build(:story,
            title: "OpenAI releases GPT-4o agent framework",
            url: "https://openai.com/blog/agents",
            text: nil)
    end

    it "matches when keyword appears in title (case-insensitive)" do
      expect(KeywordMatcher.matches?(story, [ "agent" ])).to be true
      expect(KeywordMatcher.matches?(story, [ "AGENT" ])).to be true
    end

    it "matches against URL host and path" do
      expect(KeywordMatcher.matches?(story, [ "openai" ])).to be true
    end

    it "matches against Ask HN text body" do
      ask = build(:story, title: "Ask HN", url: nil, text: "Using Rust for embedded systems")
      expect(KeywordMatcher.matches?(ask, [ "rust" ])).to be true
    end

    it "returns false when no keyword matches" do
      expect(KeywordMatcher.matches?(story, [ "kubernetes" ])).to be false
    end

    it "is safe against SQL-like special chars" do
      s = build(:story, title: "Story with 100% improvement")
      expect(KeywordMatcher.matches?(s, [ "100%" ])).to be true
    end

    it "treats whole-keyword-substring (no word boundary)" do
      s = build(:story, title: "Rustacean unite!")
      expect(KeywordMatcher.matches?(s, [ "rust" ])).to be true
    end

    it "ignores blank keywords" do
      expect(KeywordMatcher.matches?(story, [ "", " " ])).to be false
    end

    it "returns false when story has no searchable text" do
      blank = build(:story, title: nil, url: nil, text: nil)
      expect(KeywordMatcher.matches?(blank, [ "agent" ])).to be false
    end
  end

  describe ".matching_topics" do
    let(:story) { create(:story, title: "Rust 2024 roadmap") }

    it "returns active topics whose keywords match (no user scoping)" do
      rust = create(:topic, name: "Rust", keywords: [ "rust" ], active: true)
      create(:topic, name: "AI", keywords: [ "gpt", "llm" ], active: true)
      create(:topic, name: "Rust paused", keywords: [ "rust" ], active: false)

      result = KeywordMatcher.matching_topics(story, Topic.all)
      expect(result).to contain_exactly(rust)
    end
  end
end
