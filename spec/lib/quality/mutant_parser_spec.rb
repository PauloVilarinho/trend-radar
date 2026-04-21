require "rails_helper"
require "tempfile"

RSpec.describe Quality::MutantParser do
  let(:fixture) { Rails.root.join("spec/fixtures/quality/mutant_output.txt") }

  it "extracts the kill ratio as a float percentage" do
    parsed = described_class.new(fixture).parse

    expect(parsed[:kill_ratio]).to eq(90.83)
    expect(parsed[:mutations]).to eq(240)
    expect(parsed[:kills]).to eq(218)
  end

  it "raises ParseError when the summary block is missing" do
    garbage = Tempfile.new([ "mutant", ".txt" ])
    garbage.write("nothing to see here\n")
    garbage.close

    expect { described_class.new(garbage.path).parse }
      .to raise_error(Quality::MutantParser::ParseError)
  ensure
    garbage&.unlink
  end
end
