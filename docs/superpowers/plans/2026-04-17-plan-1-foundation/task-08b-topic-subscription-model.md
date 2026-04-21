# Task 8b — TopicSubscription model (TDD)

**Status:** pending
**Depends on:** Task 8 (and the Topic model from Task 7).

Join table between `users` and `topics` carrying per-user settings: Discord webhook (encrypted, optional), `active` flag for pausing without unsubscribing. Enforces a 50-subscriptions-per-user cap.

## Files

- Create: `db/migrate/*_create_topic_subscriptions.rb`
- Create: `app/models/topic_subscription.rb`
- Create: `spec/models/topic_subscription_spec.rb`
- Create: `spec/factories/topic_subscriptions.rb`
- Modify: `app/models/user.rb` — `has_many :topic_subscriptions, dependent: :destroy`; `has_many :subscribed_topics, through: :topic_subscriptions, source: :topic`
- Modify: `app/models/topic.rb` — `has_many :topic_subscriptions, dependent: :destroy`; `has_many :subscribers, through: :topic_subscriptions, source: :user`

## Steps

1. Create `spec/models/topic_subscription_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe TopicSubscription, type: :model do
     let(:user) { create(:user) }
     let(:topic) { create(:topic) }

     describe "validations" do
       it "is valid with minimum required attributes" do
         expect(build(:topic_subscription, user: user, topic: topic)).to be_valid
       end

       it "is unique per (user, topic)" do
         create(:topic_subscription, user: user, topic: topic)
         dup = build(:topic_subscription, user: user, topic: topic)
         expect(dup).not_to be_valid
       end

       it "allows nil discord_webhook" do
         expect(build(:topic_subscription, user: user, topic: topic, discord_webhook: nil)).to be_valid
       end

       it "validates discord_webhook format when present" do
         sub = build(:topic_subscription, user: user, topic: topic,
                                          discord_webhook: "https://example.com/webhook")
         expect(sub).not_to be_valid
         expect(sub.errors[:discord_webhook]).to be_present
       end

       it "accepts valid Discord webhook URLs" do
         sub = build(:topic_subscription, user: user, topic: topic,
                                          discord_webhook: "https://discord.com/api/webhooks/123/abc")
         expect(sub).to be_valid
       end
     end

     describe "per-user subscription limit" do
       it "rejects the 51st subscription for a user" do
         50.times { create(:topic_subscription, user: user) }
         over = build(:topic_subscription, user: user)
         expect(over).not_to be_valid
         expect(over.errors[:base]).to include(/limit/i)
       end
     end

     describe "associations" do
       it "User#subscribed_topics returns joined topics" do
         sub = create(:topic_subscription, user: user, topic: topic)
         expect(user.subscribed_topics).to include(topic)
       end

       it "Topic#subscribers returns joined users" do
         sub = create(:topic_subscription, user: user, topic: topic)
         expect(topic.subscribers).to include(user)
       end
     end
   end
   ```

2. Create `spec/factories/topic_subscriptions.rb`:
   ```ruby
   FactoryBot.define do
     factory :topic_subscription do
       user
       topic
       discord_webhook { nil }
       active { true }
     end
   end
   ```

3. Run → **FAIL** (model undefined).

4. Migration:
   ```bash
   bin/rails generate migration CreateTopicSubscriptions user:references topic:references discord_webhook:string active:boolean
   ```
   Edit to:
   ```ruby
   class CreateTopicSubscriptions < ActiveRecord::Migration[8.0]
     def change
       create_table :topic_subscriptions do |t|
         t.references :user, null: false, foreign_key: { on_delete: :cascade }
         t.references :topic, null: false, foreign_key: { on_delete: :cascade }
         t.string :discord_webhook
         t.boolean :active, null: false, default: true
         t.timestamps
       end
       add_index :topic_subscriptions, [:user_id, :topic_id], unique: true
     end
   end
   ```
   Run `bin/rails db:migrate`.

5. Create `app/models/topic_subscription.rb`:
   ```ruby
   class TopicSubscription < ApplicationRecord
     MAX_SUBSCRIPTIONS_PER_USER = 50
     DISCORD_WEBHOOK_REGEX = %r{\Ahttps://(?:discord\.com|discordapp\.com)/api/webhooks/\d+/[\w-]+\z}

     belongs_to :user
     belongs_to :topic

     encrypts :discord_webhook if respond_to?(:encrypts)

     validates :user_id, uniqueness: { scope: :topic_id }
     validate :validate_discord_webhook
     validate :validate_subscription_limit, on: :create

     scope :active, -> { where(active: true) }

     private

     def validate_discord_webhook
       return if discord_webhook.blank?
       return if DISCORD_WEBHOOK_REGEX.match?(discord_webhook)

       errors.add(:discord_webhook, "must be a valid Discord webhook URL")
     end

     def validate_subscription_limit
       return unless user

       if user.topic_subscriptions.count >= MAX_SUBSCRIPTIONS_PER_USER
         errors.add(:base, "subscription limit of #{MAX_SUBSCRIPTIONS_PER_USER} reached")
       end
     end
   end
   ```

   Note: `encrypts :discord_webhook` requires Rails encryption keys. If Task 7's encryption bootstrap wasn't run yet, run it now:
   ```bash
   bin/rails db:encryption:init
   EDITOR=vim bin/rails credentials:edit   # paste active_record_encryption block
   ```

6. Update `app/models/user.rb` — add:
   ```ruby
   has_many :topic_subscriptions, dependent: :destroy
   has_many :subscribed_topics, through: :topic_subscriptions, source: :topic
   ```

7. Update `app/models/topic.rb` — add:
   ```ruby
   has_many :topic_subscriptions, dependent: :destroy
   has_many :subscribers, through: :topic_subscriptions, source: :user
   ```

8. Run `bin/rspec spec/models/topic_subscription_spec.rb` → **PASS**.

9. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add TopicSubscription join model with encrypted webhook and 50-cap"
   ```
