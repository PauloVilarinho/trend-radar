class Notification < ApplicationRecord
  CHANNELS = %w[web_push discord].freeze
  STATUSES = %w[pending sent failed].freeze
  TARGET_TYPES = %w[PushSubscription TopicSubscription].freeze

  belongs_to :match
  belongs_to :target, polymorphic: true

  validates :channel, inclusion: { in: CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :target_id, uniqueness: { scope: [ :match_id, :channel, :target_type ] }
end
