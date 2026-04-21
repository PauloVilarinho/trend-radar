# Task 9 — Topics catalog index page (read-only for regular users)

**Status:** pending (redone for shared-topics model)
**Depends on:** Task 8b.

`/topics` is now a read-only catalog of all `active: true` topics, with each row showing the current user's subscription state (subscribed? webhook? paused?). Subscribe / unsubscribe / edit-webhook happen via `TopicSubscriptionsController` (Task 10). Admin CRUD moves to `/admin/topics` (Task 11).

## Files

- Create: `app/controllers/topics_controller.rb`, `app/frontend/pages/topics/index.tsx`, `spec/requests/topics_spec.rb`
- Modify: `config/routes.rb`

## Steps

1. Create `spec/requests/topics_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe "Topics catalog", type: :request do
     let(:user) { create(:user) }

     describe "GET /topics" do
       context "unauthenticated" do
         it "redirects to sign in" do
           get "/topics"
           expect(response).to redirect_to(new_user_session_path)
         end
       end

       context "authenticated" do
         before { sign_in user }

         it "lists active topics with this user's subscription state" do
           ai = create(:topic, name: "AI", active: true)
           rust = create(:topic, name: "Rust", active: true)
           inactive = create(:topic, name: "Hidden", active: false)
           create(:topic_subscription, user: user, topic: ai,
                  discord_webhook: "https://discord.com/api/webhooks/1/abc", active: true)

           get "/topics"

           expect(response).to have_http_status(:ok)
           expect(response.body).to include("topics/index")
           expect(response.body).to include("AI")
           expect(response.body).to include("Rust")
           expect(response.body).not_to include("Hidden")
         end
       end
     end
   end
   ```

2. Run → **FAIL**.

3. Routes. Edit `config/routes.rb`:
   ```ruby
   Rails.application.routes.draw do
     devise_for :users
     root to: "dashboard#index"

     resources :topics, only: [:index] do
       resource :subscription, only: [:create, :update, :destroy],
                               controller: "topic_subscriptions"
     end

     namespace :admin do
       root "topics#index"
       resources :topics, except: [:destroy, :show]
     end

     get "up" => "rails/health#show", as: :rails_health_check
   end
   ```

   (The `namespace :admin` block lands here so `/topics` and `/admin/topics` are both wired in one pass. The Admin controller itself ships in Task 11.)

4. `app/controllers/topics_controller.rb`:
   ```ruby
   class TopicsController < ApplicationController
     def index
       topics = Topic.active.order(:name).includes(:topic_subscriptions)
       subs_by_topic = current_user.topic_subscriptions.index_by(&:topic_id)

       render inertia: "topics/index", props: {
         topics: topics.map { |t| topic_props(t, subs_by_topic[t.id]) }
       }
     end

     private

     def topic_props(topic, subscription)
       {
         id: topic.id,
         name: topic.name,
         keywords: topic.keywords,
         subscription: subscription && {
           id: subscription.id,
           active: subscription.active,
           discord_webhook: subscription.discord_webhook || "",
         },
       }
     end
   end
   ```

5. `app/frontend/pages/topics/index.tsx`:
   ```tsx
   import { Head, useForm, router } from "@inertiajs/react";
   import { FormEvent } from "react";

   type Subscription = {
     id: number;
     active: boolean;
     discord_webhook: string;
   };

   type Topic = {
     id: number;
     name: string;
     keywords: string[];
     subscription: Subscription | null;
   };

   export default function Index({ topics }: { topics: Topic[] }) {
     return (
       <>
         <Head title="Topics" />
         <h1 className="text-2xl font-semibold mb-4">Topics</h1>
         {topics.length === 0 ? (
           <p className="text-gray-600">No topics yet. Check back soon.</p>
         ) : (
           <ul className="bg-white rounded border border-gray-200 divide-y">
             {topics.map((t) => (
               <li key={t.id} className="p-4">
                 <div className="flex justify-between items-start gap-4">
                   <div className="flex-1">
                     <div className="font-medium">{t.name}</div>
                     <div className="text-xs text-gray-500 mt-1">
                       {t.keywords.join(", ")}
                     </div>
                   </div>
                   {t.subscription ? (
                     <span className="text-xs text-green-700">
                       {t.subscription.active ? "Subscribed" : "Paused"}
                     </span>
                   ) : (
                     <SubscribeButton topicId={t.id} />
                   )}
                 </div>
                 {t.subscription && (
                   <SubscriptionForm topicId={t.id} subscription={t.subscription} />
                 )}
               </li>
             ))}
           </ul>
         )}
       </>
     );
   }

   function SubscribeButton({ topicId }: { topicId: number }) {
     const subscribe = () =>
       router.post(`/topics/${topicId}/subscription`, {}, { preserveScroll: true });
     return (
       <button
         onClick={subscribe}
         className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm"
       >
         Subscribe
       </button>
     );
   }

   function SubscriptionForm({
     topicId,
     subscription,
   }: {
     topicId: number;
     subscription: Subscription;
   }) {
     const form = useForm({
       discord_webhook: subscription.discord_webhook,
       active: subscription.active,
     });

     const submit = (e: FormEvent) => {
       e.preventDefault();
       form.patch(`/topics/${topicId}/subscription`, { preserveScroll: true });
     };

     const unsubscribe = () => {
       if (confirm("Unsubscribe from this topic?")) {
         router.delete(`/topics/${topicId}/subscription`, { preserveScroll: true });
       }
     };

     return (
       <form onSubmit={submit} className="mt-3 space-y-2 text-sm">
         <label className="block">
           <span className="text-xs text-gray-600">
             Discord webhook URL (optional)
           </span>
           <input
             className="border rounded px-2 py-1 w-full mt-1"
             value={form.data.discord_webhook}
             onChange={(e) => form.setData("discord_webhook", e.target.value)}
           />
         </label>
         <label className="flex items-center gap-2 text-xs">
           <input
             type="checkbox"
             checked={form.data.active}
             onChange={(e) => form.setData("active", e.target.checked)}
           />
           Active (receive notifications)
         </label>
         <div className="flex gap-2">
           <button
             type="submit"
             disabled={form.processing}
             className="bg-blue-600 text-white px-3 py-1 rounded text-xs"
           >
             Save
           </button>
           <button
             type="button"
             onClick={unsubscribe}
             className="bg-gray-200 text-gray-800 px-3 py-1 rounded text-xs"
           >
             Unsubscribe
           </button>
         </div>
       </form>
     );
   }
   ```

6. `bin/rspec spec/requests/topics_spec.rb` → **PASS**.

7. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add read-only topics catalog with subscription state"
   ```
