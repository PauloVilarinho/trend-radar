# Task 9 — Topics index page (list user's topics)

**Status:** pending
**Depends on:** Task 8.

## Files

- Create: `app/controllers/topics_controller.rb`, `app/frontend/Pages/Topics/Index.tsx`, `spec/requests/topics_spec.rb`
- Modify: `config/routes.rb` (add `resources :topics`)

## Steps

1. `spec/requests/topics_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe "Topics", type: :request do
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

         it "renders the topics index with user's topics only" do
           create(:topic, user: user, name: "Mine")
           create(:topic, name: "NotMine")

           get "/topics"

           expect(response).to have_http_status(:ok)
           expect(response.body).to include("Topics/Index")
           expect(response.body).to include("Mine")
           expect(response.body).not_to include("NotMine")
         end
       end
     end
   end
   ```

2. Run → **FAIL**.

3. `config/routes.rb`:
   ```ruby
   Rails.application.routes.draw do
     devise_for :users
     root to: "dashboard#index"
     resources :topics
     get "up" => "rails/health#show", as: :rails_health_check
   end
   ```

4. `app/controllers/topics_controller.rb`:
   ```ruby
   class TopicsController < ApplicationController
     def index
       topics = current_user.topics.order(created_at: :desc)
       render inertia: "Topics/Index", props: {
         topics: topics.map { |t| topic_props(t) }
       }
     end

     private

     def topic_props(topic)
       {
         id: topic.id,
         name: topic.name,
         keywords: topic.keywords,
         active: topic.active,
         has_discord: topic.discord_webhook.present?,
       }
     end
   end
   ```

5. `app/frontend/Pages/Topics/Index.tsx`:
   ```tsx
   import { Head, Link } from "@inertiajs/react";

   type Topic = {
     id: number;
     name: string;
     keywords: string[];
     active: boolean;
     has_discord: boolean;
   };

   export default function Index({ topics }: { topics: Topic[] }) {
     return (
       <>
         <Head title="Topics" />
         <div className="flex justify-between items-center mb-4">
           <h1 className="text-2xl font-semibold">Topics</h1>
           <Link href="/topics/new" className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm">
             New topic
           </Link>
         </div>
         {topics.length === 0 ? (
           <p className="text-gray-600">No topics yet. Create one to start monitoring.</p>
         ) : (
           <ul className="bg-white rounded border border-gray-200 divide-y">
             {topics.map((t) => (
               <li key={t.id} className="p-3 flex justify-between items-center">
                 <div>
                   <div className="font-medium">{t.name}</div>
                   <div className="text-xs text-gray-500">
                     {t.keywords.join(", ")}
                     {t.has_discord && " · Discord"}
                     {!t.active && " · paused"}
                   </div>
                 </div>
                 <Link href={`/topics/${t.id}/edit`} className="text-blue-600 text-sm">Edit</Link>
               </li>
             ))}
           </ul>
         )}
       </>
     );
   }
   ```

6. `bin/rspec spec/requests/topics_spec.rb` → **PASS**.

7. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add topics index page"
   ```
