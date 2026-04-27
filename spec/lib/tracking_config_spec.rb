require "rails_helper"

RSpec.describe TrackingConfig do
  it "loads velocity candidate threshold" do
    expect(TrackingConfig.velocity_candidate_threshold[:points_per_hour]).to eq(15)
    expect(TrackingConfig.velocity_candidate_threshold[:minimum_score]).to eq(30)
  end

  it "loads archival thresholds" do
    expect(TrackingConfig.archive[:hard_cutoff_hours]).to eq(72)
    expect(TrackingConfig.archive[:cooling_age_hours]).to eq(12)
    expect(TrackingConfig.archive[:cooling_points_per_hour]).to eq(3)
    expect(TrackingConfig.archive[:flat_snapshots_required]).to eq(3)
  end

  it "loads match thresholds" do
    expect(TrackingConfig.match[:min_relevance_score]).to eq(0.6)
    expect(TrackingConfig.match[:daily_classification_budget]).to eq(500)
  end

  it "loads snapshot retention" do
    expect(TrackingConfig.snapshot_retention_days).to eq(7)
  end
end
