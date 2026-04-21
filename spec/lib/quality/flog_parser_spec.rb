require "rails_helper"
require "tempfile"

RSpec.describe Quality::FlogParser do
  let(:fixture) { Rails.root.join("spec/fixtures/quality/flog_sample.rb") }

  it "returns max per-method score and max per-class (aggregated) score" do
    parsed = described_class.new([ fixture.to_s ]).parse

    expect(parsed[:method_max]).to be > 5.0
    expect(parsed[:class_max]).to be >= parsed[:method_max]
  end

  it "returns zeros when the target path has no methods" do
    empty = Tempfile.new([ "empty", ".rb" ])
    empty.close

    parsed = described_class.new([ empty.path ]).parse

    expect(parsed).to eq(method_max: 0.0, class_max: 0.0)
  ensure
    empty&.unlink
  end
end
