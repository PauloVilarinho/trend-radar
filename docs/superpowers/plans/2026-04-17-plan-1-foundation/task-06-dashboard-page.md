# Task 6 — Dashboard placeholder page + routes (TDD)

**Status:** pending
**Depends on:** Task 5.

## Files

- Create: `app/controllers/dashboard_controller.rb`, `app/frontend/pages/dashboard/index.tsx`, `spec/requests/dashboard_spec.rb`
- Modify: `config/routes.rb`, `spec/rails_helper.rb` (Devise test helpers)

**Naming deviation:** page path uses lowercase `dashboard/index` to match the existing `inertia_example/index` generator convention (and the Task 4 decision to keep `pages/` lowercase). Controller renders `inertia: "dashboard/index"`.

## Steps

1. Create `spec/requests/dashboard_spec.rb` (failing spec):
   ```ruby
   require "rails_helper"

   RSpec.describe "Dashboard", type: :request do
     describe "GET /" do
       context "unauthenticated" do
         it "redirects to sign in" do
           get "/"
           expect(response).to redirect_to(new_user_session_path)
         end
       end

       context "authenticated" do
         let(:user) { create(:user) }
         before { sign_in user }

         it "renders the dashboard inertia page" do
           get "/"
           expect(response).to have_http_status(:ok)
           expect(response.body).to include("dashboard/index")
         end
       end
     end
   end
   ```

2. Add Devise test helpers in `spec/rails_helper.rb` inside `RSpec.configure`:
   ```ruby
   config.include Devise::Test::IntegrationHelpers, type: :request
   config.include Devise::Test::IntegrationHelpers, type: :system
   ```

3. Run `bin/rspec spec/requests/dashboard_spec.rb` → **FAIL** (no route).

4. `config/routes.rb`:
   ```ruby
   Rails.application.routes.draw do
     devise_for :users
     root to: "dashboard#index"
     get "up" => "rails/health#show", as: :rails_health_check
   end
   ```

5. `app/controllers/dashboard_controller.rb`:
   ```ruby
   class DashboardController < ApplicationController
     def index
       render inertia: "dashboard/index", props: {}
     end
   end
   ```

6. `app/frontend/pages/dashboard/index.tsx`:
   ```tsx
   import { Head } from "@inertiajs/react";

   export default function Index() {
     return (
       <>
         <Head title="Dashboard" />
         <h1 className="text-2xl font-semibold">Dashboard</h1>
         <p className="mt-2 text-gray-600">Matches will appear here once topics are set up.</p>
       </>
     );
   }
   ```

7. `bin/rspec spec/requests/dashboard_spec.rb` → **PASS**.

8. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add dashboard placeholder page at root"
   ```
