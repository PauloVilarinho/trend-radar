# Task 17 — System smoke test for topic management

**Status:** pending
**Depends on:** Task 16 (or Task 12 — it just needs the full CRUD working).

## Files

- Create: `spec/system/topic_management_spec.rb`

## Steps

1. Create `spec/system/topic_management_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe "Topic management", type: :system do
     before do
       driven_by(:rack_test)  # headless, no JS — sufficient for Inertia initial render
     end

     let(:user) { create(:user) }

     it "allows a user to create, edit, and delete a topic" do
       sign_in user

       visit "/topics"
       expect(page).to have_content("No topics yet")

       # rack_test can't drive client-side Inertia — hit the endpoints directly.
       page.driver.post "/topics", topic: { name: "AI", keywords: ["AI", "LLM"] }
       expect(Topic.count).to eq(1)

       visit "/topics"
       expect(page).to have_content("AI")

       topic = Topic.first
       page.driver.patch "/topics/#{topic.id}", topic: { name: "AI agents", keywords: ["AI", "LLM", "agent"] }
       expect(topic.reload.name).to eq("AI agents")

       page.driver.delete "/topics/#{topic.id}"
       expect(Topic.count).to eq(0)
     end
   end
   ```

2. `bin/rspec spec/system/topic_management_spec.rb` → **PASS**.

3. **Commit.**
   ```bash
   git add -A
   git commit -m "test: add system smoke test for topic management"
   ```

## Plan 1 — Done

At the end of Task 17 the app should:
- Boot locally (`bin/rails server` + `bin/vite dev`).
- Let a user sign up, log in, sign out via Devise ERB views.
- Let a signed-in user view their topics list, create, edit, and delete topics.
- Reject invalid topic data with inline errors.
- Have SolidQueue installed and ready (no jobs yet).
- Pass `bin/rspec` end-to-end.
- Pass CI on GitHub Actions (with any Ruby-version CI workaround noted in Task 15).

Plan 2 (HN ingestion + matching) picks up here.
