require "rails_helper"
require "tempfile"

RSpec.describe Quality::BrakemanParser do
  it "returns zero warnings when the report has none" do
    path = Rails.root.join("spec/fixtures/quality/brakeman_zero.json")

    parsed = described_class.new(path).parse

    expect(parsed).to eq(warnings: 0)
  end

  it "counts warnings in the report" do
    path = Rails.root.join("spec/fixtures/quality/brakeman_one_warning.json")

    parsed = described_class.new(path).parse

    expect(parsed).to eq(warnings: 1)
  end

  it "raises on malformed JSON" do
    bad = Tempfile.new([ "brakeman", ".json" ])
    bad.write("not json")
    bad.close

    expect { described_class.new(bad.path).parse }.to raise_error(JSON::ParserError)
  ensure
    bad&.unlink
  end
end
