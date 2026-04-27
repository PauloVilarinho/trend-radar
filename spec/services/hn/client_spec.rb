require "rails_helper"

RSpec.describe Hn::Client do
  let(:client) { described_class.new }

  describe "#top_story_ids" do
    it "returns array of IDs from /topstories.json" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/topstories.json")
        .to_return(status: 200, body: "[1, 2, 3]", headers: { "Content-Type" => "application/json" })

      expect(client.top_story_ids).to eq([ 1, 2, 3 ])
    end
  end

  describe "#new_story_ids" do
    it "returns array of IDs from /newstories.json" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/newstories.json")
        .to_return(status: 200, body: "[10, 11]", headers: { "Content-Type" => "application/json" })

      expect(client.new_story_ids).to eq([ 10, 11 ])
    end
  end

  describe "#best_story_ids" do
    it "returns array of IDs from /beststories.json" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/beststories.json")
        .to_return(status: 200, body: "[20]", headers: { "Content-Type" => "application/json" })

      expect(client.best_story_ids).to eq([ 20 ])
    end
  end

  describe "#item" do
    it "returns a parsed hash for a live story" do
      body = {
        id: 44_000_001, type: "story", by: "alice", title: "Hello",
        url: "https://example.com", score: 42, descendants: 7, time: 1_700_000_000
      }.to_json
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/44000001.json")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      expect(client.item(44_000_001)).to include(id: 44_000_001, title: "Hello", score: 42)
    end

    it "returns nil for deleted stories" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/999.json")
        .to_return(status: 200, body: '{"id":999,"deleted":true}',
                   headers: { "Content-Type" => "application/json" })

      expect(client.item(999)).to be_nil
    end

    it "returns nil for dead stories" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/998.json")
        .to_return(status: 200, body: '{"id":998,"dead":true}',
                   headers: { "Content-Type" => "application/json" })

      expect(client.item(998)).to be_nil
    end

    it "returns nil for null response (unknown id)" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/0.json")
        .to_return(status: 200, body: "null", headers: { "Content-Type" => "application/json" })

      expect(client.item(0)).to be_nil
    end

    it "raises RequestError on 5xx after retries" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/1.json")
        .to_return(status: 503)

      expect { client.item(1) }.to raise_error(Hn::Client::RequestError)
    end

    it "raises RequestError on invalid JSON" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/2.json")
        .to_return(status: 200, body: "not json{", headers: { "Content-Type" => "application/json" })

      expect { client.item(2) }.to raise_error(Hn::Client::RequestError, /Invalid JSON/)
    end
  end
end
