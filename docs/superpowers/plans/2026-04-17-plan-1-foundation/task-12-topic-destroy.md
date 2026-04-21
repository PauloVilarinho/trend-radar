# Task 12 — AppLayout admin nav link

**Status:** pending (replaces the old "topic destroy" task; destroy action is no longer part of the design)
**Depends on:** Task 11.

The shared-topics design has no Topic destroy action (soft-disable via `active: false` only), so the old task-12 slot is reused for a small but necessary piece of polish: showing an "Admin" nav link in `AppLayout.tsx` when `current_user.admin`.

**Why this over the subscription-backfill-job alternative:** the backfill job (`BackfillSubscriptionJob`) is part of the ingestion pipeline; it belongs to Plan 2, not Plan 1. Carrying it in Plan 1 would force Plan 1 to depend on Plan 2's `Match`/`Story` models, which don't exist yet. Keeping that job in Plan 2 keeps the plan boundary clean. The nav link, by contrast, is a 10-line change that ships here with zero new dependencies.

## Files

- Modify: `app/frontend/layouts/AppLayout.tsx`
- Create: `spec/system/admin_nav_spec.rb` (optional smoke test — see Step 2)

## Steps

1. Edit `app/frontend/layouts/AppLayout.tsx`. The `current_user` Inertia prop already includes `admin` (wired in Task 7b via `inertia_share`). Add the conditional link next to the existing "Topics" entry:
   ```tsx
   type PageProps = {
     current_user: { id: number; email: string; admin: boolean } | null;
     flash: { notice?: string; alert?: string };
   };

   // inside the <nav> block, replace the authenticated branch:
   {current_user ? (
     <>
       <Link href="/topics">Topics</Link>
       {current_user.admin && <Link href="/admin/topics">Admin</Link>}
       <Link href="/users/sign_out" method="delete" as="button">
         Sign out
       </Link>
     </>
   ) : (
     <>
       <Link href="/users/sign_in">Sign in</Link>
       <Link href="/users/sign_up">Sign up</Link>
     </>
   )}
   ```

2. (Optional) Smoke test. Rack-test strips JS so the link renders from the SSR-ish Inertia initial render. Create `spec/system/admin_nav_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe "Admin nav link", type: :request do
     it "is present in the Inertia props for admins" do
       admin = create(:user, admin: true)
       sign_in admin
       get "/"
       expect(response.body).to include('"admin":true')
     end

     it "is absent for regular users" do
       sign_in create(:user)
       get "/"
       expect(response.body).to include('"admin":false')
     end
   end
   ```

   (Testing that the link itself renders is a JS concern — rack_test can't see React output. The prop check is a reasonable proxy.)

3. `bin/rspec spec/system/admin_nav_spec.rb` → **PASS**.

4. Manually verify in the browser: log in as the seeded admin (Task 16), confirm "Admin" link appears; log in as a non-admin, confirm it doesn't.

5. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: show Admin nav link in AppLayout for admin users"
   ```
