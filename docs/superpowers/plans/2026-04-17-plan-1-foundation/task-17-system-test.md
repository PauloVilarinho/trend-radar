# Task 17 — System smoke test for the admin + subscription flow

**Status:** pending
**Depends on:** Task 16 (or Task 12 — it just needs admin CRUD + subscriptions wired up).

Happy-path smoke: admin signs in → creates topic → regular user signs up → subscribes → a matching `Match` triggers → dashboard shows it.

Plan 1's pipeline doesn't exist yet (no `Story`, `Match`, `MatchJob` — those land in Plan 2), so the "matching story triggers" part is stubbed by creating a `Match` row directly against a `Story` factory. If those models don't exist at the time Plan 1 is executed, scope the test to just admin-creates / user-subscribes and leave the dashboard assertion for Plan 2's end-to-end.

## Files

- Create: `spec/system/happy_path_spec.rb`

## Steps

1. Create `spec/system/happy_path_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe "Happy path: admin creates topic, user subscribes", type: :system do
     before { driven_by(:rack_test) }

     let(:admin) { create(:user, admin: true) }
     let(:user) { create(:user) }

     it "admin creates a topic and a regular user subscribes" do
       # ---- Admin creates a topic ----
       sign_in admin
       page.driver.post "/admin/topics", topic: {
         name: "Kubernetes", keywords: ["k8s", "kubernetes"], active: true
       }
       expect(Topic.where(name: "Kubernetes")).to exist

       Warden.test_reset!

       # ---- Regular user subscribes ----
       sign_in user
       topic = Topic.find_by!(name: "Kubernetes")

       visit "/topics"
       expect(page).to have_content("Kubernetes")

       page.driver.post "/topics/#{topic.id}/subscription"
       expect(TopicSubscription.where(user: user, topic: topic)).to exist

       # ---- (Plan 2) match shows on dashboard — skipped if Story/Match don't exist yet ----
       if defined?(Story) && defined?(Match)
         story = create(:story, title: "Kubernetes 2.0 announced")
         create(:match, story: story, topic: topic, reason: "Kubernetes release")

         visit "/"
         expect(page).to have_content("Kubernetes 2.0 announced")
       end

       # ---- Unsubscribe ----
       page.driver.delete "/topics/#{topic.id}/subscription"
       expect(TopicSubscription.where(user: user, topic: topic)).not_to exist
     end
   end
   ```

2. `bin/rspec spec/system/happy_path_spec.rb` → **PASS**.

3. **Commit.**
   ```bash
   git add -A
   git commit -m "test: add happy-path system smoke for admin + subscription flow"
   ```

## Plan 1 — Done

At the end of Task 17 the app should:
- Boot locally (`bin/rails server` + `bin/vite dev`).
- Let a user sign up, log in, sign out via Devise ERB views.
- Let an admin curate the shared `Topic` catalog under `/admin/topics`.
- Let signed-in users browse `/topics` and subscribe / unsubscribe / configure their Discord webhook.
- Gate `/admin/topics` behind `require_admin!` — non-admins redirected.
- Show an "Admin" nav link only to admins.
- Have SolidQueue installed and ready (no jobs yet).
- Pass `bin/rspec` end-to-end.
- Pass CI on GitHub Actions (with any Ruby-version CI workaround noted in Task 15).

Plan 2 (HN ingestion + matching) picks up here.
