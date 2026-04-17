# Task 8 — PushSubscription model (TDD)

**Status:** pending
**Depends on:** Task 7.

## Files

- Create: `db/migrate/*_create_push_subscriptions.rb`, `app/models/push_subscription.rb`, `spec/models/push_subscription_spec.rb`, `spec/factories/push_subscriptions.rb`
- Modify: `app/models/user.rb` (add `has_many :push_subscriptions`)

## Steps

1. Create `spec/models/push_subscription_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe PushSubscription, type: :model do
     let(:user) { create(:user) }

     it "is valid with all required fields" do
       expect(build(:push_subscription, user: user)).to be_valid
     end

     it "requires endpoint" do
       expect(build(:push_subscription, user: user, endpoint: nil)).not_to be_valid
     end

     it "requires p256dh_key" do
       expect(build(:push_subscription, user: user, p256dh_key: nil)).not_to be_valid
     end

     it "requires auth_key" do
       expect(build(:push_subscription, user: user, auth_key: nil)).not_to be_valid
     end

     it "rejects duplicate endpoints for same user" do
       create(:push_subscription, user: user, endpoint: "https://push.example/abc")
       dup = build(:push_subscription, user: user, endpoint: "https://push.example/abc")
       expect(dup).not_to be_valid
     end
   end
   ```

2. Create `spec/factories/push_subscriptions.rb`:
   ```ruby
   FactoryBot.define do
     factory :push_subscription do
       user
       sequence(:endpoint) { |n| "https://push.example.com/#{n}" }
       p256dh_key { "sample-p256dh-key" }
       auth_key { "sample-auth-key" }
       user_agent { "Mozilla/5.0" }
     end
   end
   ```

3. Run → **FAIL**.

4. Migration:
   ```bash
   bin/rails generate migration CreatePushSubscriptions user:references endpoint:string p256dh_key:string auth_key:string user_agent:string
   ```
   Edit to enforce presence + unique composite index:
   ```ruby
   class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
     def change
       create_table :push_subscriptions do |t|
         t.references :user, null: false, foreign_key: true
         t.string :endpoint, null: false
         t.string :p256dh_key, null: false
         t.string :auth_key, null: false
         t.string :user_agent
         t.timestamps
       end
       add_index :push_subscriptions, [:user_id, :endpoint], unique: true
     end
   end
   ```
   `bin/rails db:migrate`.

5. `app/models/push_subscription.rb`:
   ```ruby
   class PushSubscription < ApplicationRecord
     belongs_to :user
     validates :endpoint, presence: true, uniqueness: { scope: :user_id }
     validates :p256dh_key, :auth_key, presence: true
   end
   ```

6. Update `app/models/user.rb`:
   ```ruby
   has_many :push_subscriptions, dependent: :destroy
   ```

7. `bin/rspec spec/models/push_subscription_spec.rb` → **PASS**.

8. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add PushSubscription model"
   ```
