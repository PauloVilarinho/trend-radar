# Task 7 — Topic model with validations (TDD)

**Status:** pending (redone for shared-topics model)
**Depends on:** Task 6.

Topics are a **shared, admin-curated catalog** — not owned per-user. There is no `user_id` on the Topic table; instead, an audit column `created_by_id` (nullable fk users) records which admin added the row. Per-user settings (subscribe, pause, Discord webhook) move to `topic_subscriptions` in Task 8b.

## Files

- Create: `db/migrate/*_create_topics.rb`, `app/models/topic.rb`, `spec/models/topic_spec.rb`, `spec/factories/topics.rb`
- Modify: `app/models/user.rb` (add `has_many :created_topics, class_name: "Topic", foreign_key: :created_by_id, dependent: :nullify`)

## Steps

1. Create `spec/models/topic_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe Topic, type: :model do
     describe "validations" do
       let(:admin) { create(:user) }

       it "is valid with minimum required attributes" do
         expect(build(:topic, created_by: admin)).to be_valid
       end

       it "requires a name" do
         t = build(:topic, name: nil)
         expect(t).not_to be_valid
         expect(t.errors[:name]).to be_present
       end

       it "requires a globally unique name (case-insensitive)" do
         create(:topic, created_by: admin, name: "AI")
         expect(build(:topic, created_by: admin, name: "AI")).not_to be_valid
         expect(build(:topic, created_by: admin, name: "ai")).not_to be_valid
         expect(build(:topic, created_by: admin, name: "Ai")).not_to be_valid
       end

       it "requires at least one keyword" do
         t = build(:topic, created_by: admin, keywords: [])
         expect(t).not_to be_valid
         expect(t.errors[:keywords]).to be_present
       end

       it "rejects more than 20 keywords" do
         t = build(:topic, created_by: admin, keywords: Array.new(21) { |i| "kw#{i}" })
         expect(t).not_to be_valid
         expect(t.errors[:keywords]).to include(/too many/i)
       end

       it "rejects blank keyword strings" do
         expect(build(:topic, created_by: admin, keywords: ["valid", "", "  "])).not_to be_valid
       end
     end

     describe "creator association" do
       it "nullifies created_by_id when the admin user is destroyed" do
         admin = create(:user)
         topic = create(:topic, created_by: admin)
         admin.destroy
         expect(topic.reload.created_by_id).to be_nil
       end
     end
   end
   ```

   Note: webhook validation and per-user subscription count live on `TopicSubscription` (Task 8b), not on Topic.

2. Create `spec/factories/topics.rb`:
   ```ruby
   FactoryBot.define do
     factory :topic do
       association :created_by, factory: :user
       sequence(:name) { |n| "Topic #{n}" }
       keywords { ["AI", "machine learning"] }
       active { true }
     end
   end
   ```

3. Run → **FAIL** (`Topic` undefined).

4. Migration:
   ```bash
   bin/rails generate migration CreateTopics
   ```
   Edit to:
   ```ruby
   class CreateTopics < ActiveRecord::Migration[8.0]
     def change
       create_table :topics do |t|
         t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
         t.string :name, null: false
         t.text :keywords, array: true, null: false, default: []
         t.boolean :active, null: false, default: true
         t.timestamps
       end
       add_index :topics, "LOWER(name)", unique: true
     end
   end
   ```
   Run `bin/rails db:migrate`.

5. Create `app/models/topic.rb`:
   ```ruby
   class Topic < ApplicationRecord
     MAX_KEYWORDS = 20

     belongs_to :created_by, class_name: "User", optional: true

     validates :name, presence: true,
                      uniqueness: { case_sensitive: false }
     validates :keywords, presence: true
     validate :validate_keywords

     scope :active, -> { where(active: true) }

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
   end
   ```

6. Update `app/models/user.rb`:
   ```ruby
   class User < ApplicationRecord
     devise :database_authenticatable, :registerable,
            :recoverable, :rememberable, :validatable

     has_many :created_topics,
              class_name: "Topic",
              foreign_key: :created_by_id,
              dependent: :nullify
   end
   ```

   (`has_many :topic_subscriptions` and `has_many :push_subscriptions` are added in their own tasks.)

7. `bin/rspec spec/models/topic_spec.rb` → **PASS**.

8. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add shared Topic catalog with admin audit column"
   ```
