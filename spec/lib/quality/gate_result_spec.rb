require "rails_helper"

RSpec.describe Quality::GateResult do
  it "passes when the measured value respects the comparator" do
    result = described_class.new(
      name: "Line coverage",
      measured: 96.2,
      threshold: 95.0,
      comparator: :>=,
      unit: "%"
    )

    expect(result.passed?).to be true
    expect(result.to_row).to include("Line coverage", "96.2%", ">=", "95.0%", "✓")
  end

  it "fails when the measured value violates the comparator" do
    result = described_class.new(
      name: "Flog max method",
      measured: 22,
      threshold: 15,
      comparator: :<=
    )

    expect(result.passed?).to be false
    expect(result.to_row).to include("Flog max method", "22", "<=", "15", "✗")
  end

  it "treats a nil threshold as a passing, unset ratchet" do
    result = described_class.new(
      name: "Mutation kill ratio",
      measured: 88.0,
      threshold: nil,
      comparator: :>=,
      unit: "%"
    )

    expect(result.passed?).to be true
    expect(result.to_row).to include("Mutation kill ratio", "88.0%", "(unset)", "ratchet pending")
  end
end
