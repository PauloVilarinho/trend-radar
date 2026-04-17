# Task 7 — Topic model with validations (TDD)

**Status:** pending
**Depends on:** Task 6.

## Files

- Create: `db/migrate/*_create_topics.rb`, `app/models/topic.rb`, `spec/models/topic_spec.rb`, `spec/factories/topics.rb`
- Modify: `app/models/user.rb` (add `has_many :topics`)

## Steps

1. Create `spec/models/topic_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe Topic, type: :model do
     describe "validations" do
       let(:user) { create(:user) }

       it "is valid with minimum required attributes" do
         expect(build(:topic, user: user)).to be_valid
       end

       it "requires a name" do
         t = build(:topic, name: nil)
         expect(t).not_to be_valid
         expect(t.errors[:name]).to be_present
       end

       it "requires a unique name per user" do
         create(:topic, user: user, name: "AI")
         expect(build(:topic, user: user, name: "AI")).not_to be_valid
       end

       it "allows same name for different users" do
         user2 = create(:user)
         create(:topic, user: user, name: "AI")
         expect(build(:topic, user: user2, name: "AI")).to be_valid
       end

       it "requires at least one keyword" do
         t = build(:topic, user: user, keywords: [])
         expect(t).not_to be_valid
         expect(t.errors[:keywords]).to be_present
       end

       it "rejects more than 20 keywords" do
         t = build(:topic, user: user, keywords: Array.new(21) { |i| "kw#{i}" })
         expect(t).not_to be_valid
         expect(t.errors[:keywords]).to include(/too many/i)
       end

       it "rejects blank keyword strings" do
         expect(build(:topic, user: user, keywords: ["valid", "", "  "])).not_to be_valid
       end

       it "validates discord_webhook format when present" do
         t = build(:topic, user: user, discord_webhook: "https://example.com/webhook")
         expect(t).not_to be_valid
         expect(t.errors[:discord_webhook]).to be_present
       end

       it "accepts valid discord webhook URLs" do
         expect(build(:topic, user: user, discord_webhook: "https://discord.com/api/webhooks/123/abc")).to be_valid
       end

       it "allows nil discord_webhook" do
         expect(build(:topic, user: user, discord_webhook: nil)).to be_valid
       end
     end

     describe "user topic limit" do
       let(:user) { create(:user) }

       it "rejects creating a 51st topic for a user" do
         50.times { |i| create(:topic, user: user, name: "topic#{i}") }
         over = build(:topic, user: user, name: "too_many")
         expect(over).not_to be_valid
         expect(over.errors[:base]).to include(/limit/i)
       end
     end
   end
   ```

2. Create `spec/factories/topics.rb`:
   ```ruby
   FactoryBot.define do
     factory :topic do
       user
       sequence(:name) { |n| "Topic #{n}" }
       keywords { ["AI", "machine learning"] }
       discord_webhook { nil }
       active { true }
     end
   end
   ```

3. Run → **FAIL** (`Topic` undefined).

4. Migration:
   ```bash
   bin/rails generate migration CreateTopics user:references name:string keywords:text discord_webhook:string active:boolean
   ```
   Edit to:
   ```ruby
   class CreateTopics < ActiveRecord::Migration[8.0]
     def change
       create_table :topics do |t|
         t.references :user, null: false, foreign_key: true
         t.string :name, null: false
         t.text :keywords, array: true, null: false, default: []
         t.string :discord_webhook
         t.boolean :active, null: false, default: true
         t.timestamps
       end
       add_index :topics, [:user_id, :name], unique: true
     end
   end
   ```
   Run `bin/rails db:migrate`.

5. Create `app/models/topic.rb`:
   ```ruby
   class Topic < ApplicationRecord
     belongs_to :user

     MAX_KEYWORDS = 20
     MAX_TOPICS_PER_USER = 50
     DISCORD_WEBHOOK_REGEX = %r{\Ahttps://(?:discord\.com|discordapp\.com)/api/webhooks/\d+/[\w-]+\z}

     validates :name, presence: true, uniqueness: { scope: :user_id }
     validates :keywords, presence: true
     validate :validate_keywords
     validate :validate_discord_webhook
     validate :validate_user_topic_limit, on: :create

     encrypts :discord_webhook if respond_to?(:encrypts)

     private

     def validate_keywords
       return unless keywords.is_a?(Array)
       if keywords.empty? || keywords.all? { |k| k.to_s.strip.empty? }
         errors.add(:keywords, "must have at least one non-blank entry")
       end
       if keywords.any? { |k| k.to_s.strip.empty? }
         errors.add(:keywords, "contains blank entries")
       end
       if keywords.length > MAX_KEYWORDS
         errors.add(:keywords, "too many (max #{MAX_KEYWORDS})")
       end
     end

     def validate_discord_webhook
       return if discord_webhook.blank?
       return if DISCORD_WEBHOOK_REGEX.match?(discord_webhook)
       errors.add(:discord_webhook, "must be a valid Discord webhook URL")
     end

     def validate_user_topic_limit
       return unless user
       if user.topics.count >= MAX_TOPICS_PER_USER
         errors.add(:base, "topic limit of #{MAX_TOPICS_PER_USER} reached")
       end
     end
   end
   ```

6. Update `app/models/user.rb`:
   ```ruby
   class User < ApplicationRecord
     devise :database_authenticatable, :registerable,
            :recoverable, :rememberable, :validatable
     has_many :topics, dependent: :destroy
   end
   ```

7. Set up Rails encryption (needed for `encrypts :discord_webhook`):
   ```bash
   bin/rails db:encryption:init
   ```
   Open credentials and paste the `active_record_encryption` block from the output:
   ```bash
   EDITOR=vim bin/rails credentials:edit
   ```

8. `bin/rspec spec/models/topic_spec.rb` → **PASS**.

9. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add Topic model with validations and keyword array"
   ```
