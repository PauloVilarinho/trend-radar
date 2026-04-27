class VelocityCalculator
  class << self
    def rolling_points_per_hour(snapshots)
      return [] if snapshots.size < 2

      snapshots.each_cons(2).map { |prev, current| pair_velocity(prev, current) }
    end

    def current_velocity(snapshots)
      rolling_points_per_hour(snapshots).last
    end

    private

    def pair_velocity(prev, current)
      elapsed_seconds = current.captured_at - prev.captured_at
      return 0.0 if elapsed_seconds <= 0

      (current.score - prev.score) / (elapsed_seconds / 3600.0)
    end
  end
end
