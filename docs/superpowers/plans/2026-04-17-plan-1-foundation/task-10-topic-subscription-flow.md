# Task 10 — TopicSubscription flow (subscribe / update / unsubscribe)

**Status:** pending (replaces the old "topic create" task from the per-user model)
**Depends on:** Task 9.

Covers the `TopicSubscriptionsController`:
- `create` — subscribe to a topic (button POST from `pages/topics/index.tsx`)
- `update` — change Discord webhook / pause toggle (inline form on the index)
- `destroy` — unsubscribe

Routes already defined in Task 9:
```ruby
resources :topics, only: [:index] do
  resource :subscription, only: [:create, :update, :destroy],
                          controller: "topic_subscriptions"
end
```

No Inertia `new`/`edit` pages — the whole interaction fits on `pages/topics/index.tsx`.

## Files

- Create: `app/controllers/topic_subscriptions_controller.rb`
- Modify: `spec/requests/topics_spec.rb` (append a new `describe "Topic subscriptions"` block)

## Steps

1. Append failing specs to `spec/requests/topics_spec.rb`:
   ```ruby
   RSpec.describe "Topic subscriptions", type: :request do
     let(:user) { create(:user) }
     let(:topic) { create(:topic) }

     describe "POST /topics/:topic_id/subscription" do
       before { sign_in user }

       it "subscribes the current user to the topic" do
         expect {
           post "/topics/#{topic.id}/subscription"
         }.to change(TopicSubscription, :count).by(1)
         expect(response).to redirect_to(topics_path)
         sub = TopicSubscription.last
         expect(sub.user).to eq(user)
         expect(sub.topic).to eq(topic)
         expect(sub.active).to be true
       end

       it "is idempotent — subscribing twice does not duplicate" do
         post "/topics/#{topic.id}/subscription"
         expect {
           post "/topics/#{topic.id}/subscription"
         }.not_to change(TopicSubscription, :count)
       end

       it "enforces the 50-subscription cap" do
         50.times { create(:topic_subscription, user: user) }
         post "/topics/#{topic.id}/subscription"
         expect(response).to have_http_status(:unprocessable_content)
       end
     end

     describe "PATCH /topics/:topic_id/subscription" do
       let!(:subscription) { create(:topic_subscription, user: user, topic: topic) }
       before { sign_in user }

       it "updates the discord webhook and active flag" do
         patch "/topics/#{topic.id}/subscription", params: {
           topic_subscription: {
             discord_webhook: "https://discord.com/api/webhooks/123/abc",
             active: false,
           }
         }
         expect(response).to redirect_to(topics_path)
         subscription.reload
         expect(subscription.discord_webhook).to eq("https://discord.com/api/webhooks/123/abc")
         expect(subscription.active).to be false
       end

       it "rejects invalid webhook URLs" do
         patch "/topics/#{topic.id}/subscription", params: {
           topic_subscription: { discord_webhook: "not-a-url" }
         }
         expect(response).to have_http_status(:unprocessable_content)
       end
     end

     describe "DELETE /topics/:topic_id/subscription" do
       let!(:subscription) { create(:topic_subscription, user: user, topic: topic) }
       before { sign_in user }

       it "unsubscribes the user" do
         expect {
           delete "/topics/#{topic.id}/subscription"
         }.to change(TopicSubscription, :count).by(-1)
         expect(response).to redirect_to(topics_path)
       end
     end
   end
   ```

2. Run → **FAIL** (controller missing).

3. Create `app/controllers/topic_subscriptions_controller.rb`:
   ```ruby
   class TopicSubscriptionsController < ApplicationController
     before_action :set_topic

     def create
       sub = current_user.topic_subscriptions.find_or_initialize_by(topic: @topic)

       if sub.persisted? || sub.save
         redirect_to topics_path, notice: "Subscribed to #{@topic.name}."
       else
         redirect_to topics_path,
                     alert: sub.errors.full_messages.to_sentence.presence || "Could not subscribe.",
                     status: :see_other
       end
     rescue ActiveRecord::RecordInvalid => e
       redirect_to topics_path, alert: e.message, status: :see_other
     end

     def update
       sub = current_user.topic_subscriptions.find_by!(topic: @topic)

       if sub.update(subscription_params)
         redirect_to topics_path, notice: "Subscription updated."
       else
         redirect_to topics_path,
                     alert: sub.errors.full_messages.to_sentence,
                     status: :unprocessable_content
       end
     end

     def destroy
       current_user.topic_subscriptions.where(topic: @topic).destroy_all
       redirect_to topics_path, notice: "Unsubscribed from #{@topic.name}."
     end

     private

     def set_topic
       @topic = Topic.active.find(params[:topic_id])
     end

     def subscription_params
       params.require(:topic_subscription).permit(:discord_webhook, :active)
     end
   end
   ```

   Notes:
   - The 50-sub cap is enforced in the model as a validation; `save` returns false and the response surfaces as `:unprocessable_content` (Rails 8 replacement for `:unprocessable_entity`). The `create` path uses a manual branch because `find_or_initialize_by` would still try to save an invalid record; we rely on `sub.save` returning false and the controller re-reading `sub.errors`. If the spec's `expect(response).to have_http_status(:unprocessable_content)` fails because of the `redirect_to` fallback, reshape the action to `render inertia: "topics/index", ..., status: :unprocessable_content` — author's call during implementation.

4. Run `bin/rspec spec/requests/topics_spec.rb` → **PASS**.

5. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add TopicSubscriptionsController for subscribe/update/unsubscribe"
   ```
