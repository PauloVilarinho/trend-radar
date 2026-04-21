class Topic < ApplicationRecord
  MAX_KEYWORDS = 20

  belongs_to :created_by, class_name: "User", optional: true
  has_many :topic_subscriptions, dependent: :destroy
  has_many :subscribers, through: :topic_subscriptions, source: :user

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :keywords, presence: true
  validate :validate_keywords

  private

  def validate_keywords
    validate_keywords_presence
    validate_keywords_no_blanks
    validate_keywords_count
  end

  def validate_keywords_presence
    return unless keywords.empty? || keywords.all? { |k| k.to_s.strip.empty? }

    errors.add(:keywords, "must have at least one non-blank entry")
  end

  def validate_keywords_no_blanks
    return unless keywords.any? { |k| k.to_s.strip.empty? }

    errors.add(:keywords, "contains blank entries")
  end

  def validate_keywords_count
    return unless keywords.length > MAX_KEYWORDS

    errors.add(:keywords, "too many (max #{MAX_KEYWORDS})")
  end
end
