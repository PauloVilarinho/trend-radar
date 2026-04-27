require "rails_helper"

RSpec.describe StoryFlatlineDetector do
  let(:cfg) { { flat_snapshots_required: 3 } }

  def snap(score:, descendants: 0)
    Struct.new(:score, :descendants).new(score, descendants)
  end

  describe ".flat?" do
    it "is true when the last N+1 snapshots are identical in score and comments" do
      snaps = Array.new(4) { snap(score: 50, descendants: 5) }
      expect(described_class.flat?(snaps, cfg)).to be true
    end

    it "is false when score moves at any point in the window" do
      snaps = [ snap(score: 50), snap(score: 50), snap(score: 51), snap(score: 51) ]
      expect(described_class.flat?(snaps, cfg)).to be false
    end

    it "is false when comments move even if score is steady" do
      snaps = [
        snap(score: 50, descendants: 1), snap(score: 50, descendants: 1),
        snap(score: 50, descendants: 2), snap(score: 50, descendants: 2)
      ]
      expect(described_class.flat?(snaps, cfg)).to be false
    end

    it "is false when there are too few snapshots" do
      snaps = Array.new(2) { snap(score: 50) }
      expect(described_class.flat?(snaps, cfg)).to be false
    end
  end
end
