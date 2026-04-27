class StoryFlatlineDetector
  def self.flat?(snapshots, cfg)
    needed = cfg[:flat_snapshots_required] + 1
    return false if snapshots.size < needed

    snapshots.last(needed).each_cons(2).all? { |a, b| same_metrics?(a, b) }
  end

  def self.same_metrics?(left, right)
    left.score == right.score && left.descendants == right.descendants
  end
end
