# Task 12 — Topic destroy

**Status:** pending
**Depends on:** Task 11.

## Files

- Modify: `app/controllers/topics_controller.rb`, `spec/requests/topics_spec.rb`

## Steps

1. Append to `spec/requests/topics_spec.rb`:
   ```ruby
   describe "DELETE /topics/:id" do
     let!(:topic) { create(:topic, user: user) }
     before { sign_in user }

     it "deletes own topic" do
       expect { delete "/topics/#{topic.id}" }.to change(Topic, :count).by(-1)
       expect(response).to redirect_to(topics_path)
     end
   end
   ```

2. Run → **FAIL**.

3. Add to `TopicsController` (between `update` and `private`):
   ```ruby
   def destroy
     @topic.destroy
     redirect_to topics_path, notice: "Topic deleted."
   end
   ```

4. `bin/rspec spec/requests/topics_spec.rb` → **PASS**.

5. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add topic destroy"
   ```
