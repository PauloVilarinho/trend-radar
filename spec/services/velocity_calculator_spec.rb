require "rails_helper"

RSpec.describe VelocityCalculator do
  describe ".rolling_points_per_hour" do
    it "returns [] when fewer than 2 snapshots" do
      snap = build_snaps([ [ Time.current, 10 ] ])
      expect(VelocityCalculator.rolling_points_per_hour(snap)).to eq([])
    end

    it "computes points/hour between consecutive snapshots" do
      t0 = Time.current - 3.hours
      snaps = build_snaps([ [ t0, 0 ], [ t0 + 1.hour, 10 ], [ t0 + 2.hours, 25 ] ])
      result = VelocityCalculator.rolling_points_per_hour(snaps)
      expect(result).to eq([ 10.0, 15.0 ])
    end

    it "handles fractional hours" do
      t0 = Time.current - 2.hours
      snaps = build_snaps([ [ t0, 0 ], [ t0 + 30.minutes, 20 ] ])
      expect(VelocityCalculator.rolling_points_per_hour(snaps)).to eq([ 40.0 ])
    end

    it "returns 0 for zero-duration gaps (dedup safety)" do
      t = Time.current
      snaps = build_snaps([ [ t, 10 ], [ t, 20 ] ])
      expect(VelocityCalculator.rolling_points_per_hour(snaps)).to eq([ 0.0 ])
    end
  end

  describe ".current_velocity" do
    it "returns the most recent rolling velocity" do
      t0 = Time.current - 3.hours
      snaps = build_snaps([ [ t0, 0 ], [ t0 + 1.hour, 10 ], [ t0 + 2.hours, 25 ] ])
      expect(VelocityCalculator.current_velocity(snaps)).to eq(15.0)
    end

    it "returns nil when insufficient data" do
      expect(VelocityCalculator.current_velocity([])).to be_nil
    end
  end

  def build_snaps(pairs)
    pairs.map do |captured_at, score|
      Struct.new(:captured_at, :score).new(captured_at, score)
    end
  end
end
