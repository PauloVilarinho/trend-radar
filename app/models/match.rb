class Match < ApplicationRecord
  CHANNELS = %w[web_push discord].freeze

  belongs_to :story
  belongs_to :topic
  has_many :notifications, dependent: :destroy

  validates :matched_at, presence: true
  validates :story_id, uniqueness: { scope: :topic_id }

  scope :visible, lambda {
    threshold = TrackingConfig.match[:min_relevance_score]
    where(dismissed_at: nil, posted_at: nil)
      .where("relevance_score >= ?", threshold)
  }
  scope :recent, -> { order(matched_at: :desc) }
end
