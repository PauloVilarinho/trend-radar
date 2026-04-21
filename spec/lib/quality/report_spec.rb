require "rails_helper"

RSpec.describe Quality::Report do
  let(:passing_measurements) do
    {
      coverage: { line: 96.2, branch: 91.4 },
      rubocop: {
        class_length_max: 87,
        method_length_max: 9,
        abc_size_max: 13,
        cyclomatic_complexity_max: 5,
        perceived_complexity_max: 6
      },
      flog: { method_max: 12.0, class_max: 38.0 },
      mutation: { kill_ratio: 92.1 }
    }
  end

  let(:thresholds) do
    {
      "coverage" => { "line_min" => 95.0, "branch_min" => 90.0 },
      "flog" => { "method_max" => 15, "class_max" => 40 },
      "rubocop_metrics" => {
        "class_length_max" => 100,
        "method_length_max" => 15,
        "abc_size_max" => 15,
        "cyclomatic_complexity_max" => 6,
        "perceived_complexity_max" => 7
      },
      "mutation" => { "kill_ratio_min" => 92.0 }
    }
  end

  it "passes when every measurement respects its threshold" do
    report = described_class.new(measurements: passing_measurements, thresholds: thresholds)

    expect(report.passed?).to be true
    expect(report.gate_results.count(&:passed?)).to eq(report.gate_results.size)
  end

  it "fails when any single measurement breaches its threshold" do
    bad = passing_measurements.deep_dup
    bad[:rubocop][:class_length_max] = 142

    report = described_class.new(measurements: bad, thresholds: thresholds)

    expect(report.passed?).to be false
    failing = report.gate_results.reject(&:passed?)
    expect(failing.map(&:name)).to eq([ "Class length max" ])
  end

  it "treats the ratcheted mutation threshold as passing when still unset" do
    open_thresholds = thresholds.deep_dup
    open_thresholds["mutation"]["kill_ratio_min"] = nil

    report = described_class.new(measurements: passing_measurements, thresholds: open_thresholds)

    expect(report.passed?).to be true
    mutation_row = report.gate_results.find { |r| r.name == "Mutation kill ratio" }
    expect(mutation_row.to_row).to include("(unset)")
  end

  it "skips gates whose measurement is missing (e.g. no branch coverage)" do
    no_branch = passing_measurements.deep_dup
    no_branch[:coverage][:branch] = nil

    report = described_class.new(measurements: no_branch, thresholds: thresholds)

    expect(report.gate_results.map(&:name)).not_to include("Branch coverage")
  end

  it "renders a human-readable multi-line summary" do
    report = described_class.new(measurements: passing_measurements, thresholds: thresholds)

    output = report.to_s

    expect(output).to include("Quality gates", "Line coverage")
    expect(output).to include("#{report.gate_results.size}/#{report.gate_results.size} gates passed")
  end
end
