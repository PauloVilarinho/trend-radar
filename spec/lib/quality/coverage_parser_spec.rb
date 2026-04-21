require "rails_helper"
require "tempfile"

RSpec.describe Quality::CoverageParser do
  let(:fixture) { Rails.root.join("spec/fixtures/quality/coverage_last_run.json") }

  it "reads line and branch coverage from SimpleCov's last_run.json" do
    parsed = described_class.new(fixture).parse

    expect(parsed).to eq(line: 96.25, branch: 90.5)
  end

  it "returns nil branch coverage when SimpleCov did not record it" do
    tmp = Tempfile.new(["last_run", ".json"])
    tmp.write('{"result":{"line":88.0}}')
    tmp.close

    parsed = described_class.new(tmp.path).parse

    expect(parsed).to eq(line: 88.0, branch: nil)
  ensure
    tmp&.unlink
  end
end
