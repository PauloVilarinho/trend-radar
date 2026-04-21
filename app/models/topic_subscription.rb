class TopicSubscription < ApplicationRecord
  MAX_SUBSCRIPTIONS_PER_USER = 50
  DISCORD_WEBHOOK_REGEX = %r{\Ahttps://(?:discord\.com|discordapp\.com)/api/webhooks/\d+/[\w-]+\z}

  belongs_to :user
  belongs_to :topic

  validates :topic_id, uniqueness: { scope: :user_id }
  validate :validate_discord_webhook
  validate :validate_per_user_limit, on: :create

  # Guarded to avoid requiring active_record_encryption credentials in test/dev.
  # Specs do not cover encryption; enable once credentials are configured.
  if respond_to?(:encrypts) && Rails.application.credentials.dig(:active_record_encryption).present?
    encrypts :discord_webhook
  end

  private

  def validate_discord_webhook
    return if discord_webhook.blank?
    return if DISCORD_WEBHOOK_REGEX.match?(discord_webhook)

    errors.add(:discord_webhook, "must be a valid Discord webhook URL")
  end

  def validate_per_user_limit
    return unless user
    if user.topic_subscriptions.count >= MAX_SUBSCRIPTIONS_PER_USER
      errors.add(:base, "subscription limit of #{MAX_SUBSCRIPTIONS_PER_USER} reached")
    end
  end
end
