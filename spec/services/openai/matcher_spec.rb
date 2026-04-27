require "rails_helper"

RSpec.describe Openai::Matcher do
  let(:story) { build(:story, title: "OpenAI releases agent framework", url: "https://openai.com/x") }
  let(:topic) { build(:topic, name: "AI agents", keywords: [ "agent", "LLM" ]) }

  def stub_openai(responses)
    client = instance_double(OpenAI::Client)
    allow(OpenAI::Client).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(*responses)
    client
  end

  def valid_response(score:, reason:)
    {
      "choices" => [
        { "message" => { "content" => { score: score, reason: reason }.to_json } }
      ]
    }
  end

  it "returns the parsed result on first success" do
    stub_openai([ valid_response(score: 0.8, reason: "Directly about agents") ])

    result = described_class.new.call(story: story, topic: topic)

    expect(result[:score]).to eq(0.8)
    expect(result[:reason]).to eq("Directly about agents")
  end

  it "retries up to 3 times when response is not valid JSON" do
    bad = { "choices" => [ { "message" => { "content" => "Sure, here's..." } } ] }
    stub_openai([ bad, bad, valid_response(score: 0.7, reason: "ok") ])

    result = described_class.new.call(story: story, topic: topic)

    expect(result[:score]).to eq(0.7)
  end

  it "returns score 0 after retries exhausted on invalid JSON" do
    bad = { "choices" => [ { "message" => { "content" => "not json" } } ] }
    stub_openai([ bad, bad, bad, bad ])

    result = described_class.new.call(story: story, topic: topic)

    expect(result[:score]).to eq(0.0)
    expect(result[:reason]).to include("invalid")
  end

  it "returns score 0 when JSON is parseable but missing keys" do
    wrong_shape = { "choices" => [ { "message" => { "content" => '{"foo":1}' } } ] }
    stub_openai([ wrong_shape ] * 4)

    result = described_class.new.call(story: story, topic: topic)

    expect(result[:score]).to eq(0.0)
  end

  it "returns score 0 when score is outside the 0..1 range" do
    out_of_range = {
      "choices" => [ { "message" => { "content" => '{"score": 1.7, "reason": "off"}' } } ]
    }
    stub_openai([ out_of_range ] * 4)

    result = described_class.new.call(story: story, topic: topic)

    expect(result[:score]).to eq(0.0)
  end
end
