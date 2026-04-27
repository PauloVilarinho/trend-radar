class Story < ApplicationRecord
  TRACKING_STATUSES = %w[active archived].freeze

  has_many :story_snapshots, dependent: :destroy
  has_many :matches, dependent: :destroy

  validates :hn_id, presence: true, uniqueness: true
  validates :tracking_status, inclusion: { in: TRACKING_STATUSES }

  scope :active, -> { where(tracking_status: "active") }
  scope :archived, -> { where(tracking_status: "archived") }

  def age_hours
    return nil unless hn_created_at

    (Time.current - hn_created_at) / 1.hour
  end

  def active?
    tracking_status == "active"
  end

  def archived?
    tracking_status == "archived"
  end

  def archive!
    update!(tracking_status: "archived", archived_at: Time.current)
  end
end
