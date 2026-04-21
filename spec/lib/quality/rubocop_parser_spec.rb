require "rails_helper"
require "tempfile"

RSpec.describe Quality::RubocopParser do
  let(:fixture) { Rails.root.join("spec/fixtures/quality/rubocop.json") }

  it "returns the max measured value per Metrics cop" do
    parsed = described_class.new(fixture).parse

    expect(parsed[:class_length_max]).to eq(143)
    expect(parsed[:method_length_max]).to eq(14)
    expect(parsed[:abc_size_max]).to eq(19.55)
    expect(parsed[:cyclomatic_complexity_max]).to be_nil
    expect(parsed[:perceived_complexity_max]).to be_nil
  end

  it "returns nil for a cop with no reported offenses" do
    empty_file = Tempfile.new([ "rubocop", ".json" ])
    empty_file.write('{"files":[],"summary":{}}')
    empty_file.close

    parsed = described_class.new(empty_file.path).parse

    expect(parsed[:class_length_max]).to be_nil
  ensure
    empty_file&.unlink
  end
end
