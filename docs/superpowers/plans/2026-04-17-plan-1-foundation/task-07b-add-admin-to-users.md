# Task 7b — Add `admin` flag to users + `require_admin!` gate (TDD)

**Status:** pending
**Depends on:** Task 7.

Gates the forthcoming `/admin/topics` namespace. A boolean `admin` on `users` defaults to `false`; promotion happens out-of-band via a rake task. A `require_admin!` before-action helper lands in `ApplicationController` for the admin controllers (wired in Task 11).

## Files

- Create: `db/migrate/*_add_admin_to_users.rb`
- Create: `lib/tasks/admin.rake`
- Modify: `app/models/user.rb` (no new code needed, just the column)
- Modify: `app/controllers/application_controller.rb` (add `require_admin!` helper)
- Modify: `spec/models/user_spec.rb` (new file if missing) — `admin` defaults to false
- Create: `spec/requests/admin_gate_spec.rb` — non-admin redirected

## Steps

1. Write failing model spec. Create or append to `spec/models/user_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe User, type: :model do
     describe "#admin" do
       it "defaults to false" do
         user = create(:user)
         expect(user.admin).to eq(false)
       end
     end
   end
   ```

2. Write failing request spec. Create `spec/requests/admin_gate_spec.rb`:
   ```ruby
   require "rails_helper"

   # Probe controller only exists during this spec to exercise the before_action helper.
   RSpec.describe "require_admin!", type: :request do
     before(:all) do
       Rails.application.routes.disable_clear_and_finalize = true
       Rails.application.routes.draw do
         devise_for :users
         root to: "dashboard#index"
         get "admin_probe" => "admin_probe#show"
       end

       Object.const_set(:AdminProbeController, Class.new(ApplicationController) do
         before_action :require_admin!
         def show
           render plain: "ok"
         end
       end)
     end

     after(:all) do
       Object.send(:remove_const, :AdminProbeController) if defined?(AdminProbeController)
       Rails.application.reload_routes!
       Rails.application.routes.disable_clear_and_finalize = false
     end

     context "as a non-admin" do
       let(:user) { create(:user) }
       before { sign_in user }

       it "redirects to root with an Admins only alert" do
         get "/admin_probe"
         expect(response).to redirect_to(root_path)
         follow_redirect!
         expect(flash[:alert]).to match(/admins only/i)
       end
     end

     context "as an admin" do
       let(:user) { create(:user, admin: true) }
       before { sign_in user }

       it "allows through" do
         get "/admin_probe"
         expect(response).to have_http_status(:ok)
         expect(response.body).to eq("ok")
       end
     end
   end
   ```

   Note: the dynamic route/controller override avoids coupling this spec to `Admin::TopicsController` (which ships in Task 11). If the override gymnastics feel brittle, an equivalent alternative is to skip this spec here and cover the gate via the `Admin::TopicsController` request spec in Task 11 only — flag to reviewer either way.

3. Run → **FAIL** (no `admin` column, no helper method).

4. Migration:
   ```bash
   bin/rails generate migration AddAdminToUsers admin:boolean
   ```
   Edit to:
   ```ruby
   class AddAdminToUsers < ActiveRecord::Migration[8.0]
     def change
       add_column :users, :admin, :boolean, null: false, default: false
     end
   end
   ```
   Run `bin/rails db:migrate`.

5. Add the gate helper to `app/controllers/application_controller.rb`:
   ```ruby
   class ApplicationController < ActionController::Base
     allow_browser versions: :modern
     before_action :authenticate_user!

     inertia_share do
       {
         current_user: current_user && {
           id: current_user.id,
           email: current_user.email,
           admin: current_user.admin,
         },
         flash: { notice: flash[:notice], alert: flash[:alert] }.compact,
       }
     end

     private

     def require_admin!
       return if current_user&.admin?

       redirect_to root_path, alert: "Admins only."
     end
   end
   ```

   The `admin` flag is added to the shared `current_user` Inertia prop so `AppLayout.tsx` can conditionally show the admin nav link (Task 12).

6. Rake task for promotion. Create `lib/tasks/admin.rake`:
   ```ruby
   namespace :admin do
     desc "Promote a user to admin by email. Usage: rake admin:promote[user@example.com]"
     task :promote, [:email] => :environment do |_, args|
       email = args[:email] or abort("Usage: rake admin:promote[user@example.com]")
       user = User.find_by(email: email) or abort("No user with email #{email.inspect}")
       user.update!(admin: true)
       puts "Promoted #{email} to admin."
     end
   end
   ```

7. Run both specs → **PASS**.
   ```bash
   bin/rspec spec/models/user_spec.rb spec/requests/admin_gate_spec.rb
   ```

8. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add admin flag to users with promote rake task and require_admin! gate"
   ```
