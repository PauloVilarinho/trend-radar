# Task 11 — Topic edit + update flow

**Status:** pending
**Depends on:** Task 10.

## Files

- Modify: `app/controllers/topics_controller.rb`, `spec/requests/topics_spec.rb`
- Create: `app/frontend/Pages/Topics/Edit.tsx`

## Steps

1. Append to `spec/requests/topics_spec.rb`:
   ```ruby
   describe "GET /topics/:id/edit" do
     let!(:topic) { create(:topic, user: user) }
     before { sign_in user }

     it "renders edit for own topic" do
       get "/topics/#{topic.id}/edit"
       expect(response).to have_http_status(:ok)
       expect(response.body).to include("Topics/Edit")
     end

     it "404s for other user's topic" do
       other = create(:topic)
       expect { get "/topics/#{other.id}/edit" }.to raise_error(ActiveRecord::RecordNotFound)
     end
   end

   describe "PATCH /topics/:id" do
     let!(:topic) { create(:topic, user: user, name: "Old") }
     before { sign_in user }

     it "updates valid params" do
       patch "/topics/#{topic.id}", params: { topic: { name: "New", keywords: ["a", "b"] } }
       expect(topic.reload.name).to eq("New")
       expect(response).to redirect_to(topics_path)
     end

     it "re-renders edit on invalid" do
       patch "/topics/#{topic.id}", params: { topic: { name: "", keywords: [] } }
       expect(response).to have_http_status(:unprocessable_entity)
       expect(response.body).to include("Topics/Edit")
     end
   end
   ```

2. Run → **FAIL**.

3. Add to `TopicsController` (between `create` and `private`):
   ```ruby
   def edit
     render inertia: "Topics/Edit", props: {
       topic: full_topic_form(@topic),
       errors: {},
     }
   end

   def update
     if @topic.update(topic_params)
       redirect_to topics_path, notice: "Topic updated."
     else
       render inertia: "Topics/Edit", props: {
         topic: full_topic_form(@topic),
         errors: @topic.errors.to_hash,
       }, status: :unprocessable_entity
     end
   end
   ```

   In `private`:
   ```ruby
   def full_topic_form(topic)
     {
       id: topic.id,
       name: topic.name,
       keywords: topic.keywords,
       discord_webhook: topic.discord_webhook || "",
       active: topic.active,
     }
   end
   ```

4. `app/frontend/Pages/Topics/Edit.tsx`:
   ```tsx
   import { Head, useForm } from "@inertiajs/react";
   import { FormEvent } from "react";

   type Form = { id: number; name: string; keywords: string[]; discord_webhook: string; active: boolean };
   type Props = { topic: Form; errors: Record<string, string[]> };

   export default function Edit({ topic, errors }: Props) {
     const form = useForm<Omit<Form, "id">>({
       name: topic.name,
       keywords: topic.keywords,
       discord_webhook: topic.discord_webhook,
       active: topic.active,
     });

     const submit = (e: FormEvent) => {
       e.preventDefault();
       form.patch(`/topics/${topic.id}`);
     };

     const setKeywordsFromString = (s: string) => {
       form.setData("keywords", s.split(",").map((k) => k.trim()).filter(Boolean));
     };

     const destroy = () => {
       if (confirm("Delete this topic?")) form.delete(`/topics/${topic.id}`);
     };

     return (
       <>
         <Head title={`Edit: ${topic.name}`} />
         <h1 className="text-2xl font-semibold mb-4">Edit topic</h1>
         <form onSubmit={submit} className="max-w-lg space-y-4 bg-white p-4 rounded border">
           <Field label="Name" error={errors.name}>
             <input className="border rounded px-2 py-1 w-full" value={form.data.name}
               onChange={(e) => form.setData("name", e.target.value)} />
           </Field>
           <Field label="Keywords (comma-separated)" error={errors.keywords}>
             <input className="border rounded px-2 py-1 w-full" defaultValue={form.data.keywords.join(", ")}
               onBlur={(e) => setKeywordsFromString(e.target.value)} />
           </Field>
           <Field label="Discord webhook URL (optional)" error={errors.discord_webhook}>
             <input className="border rounded px-2 py-1 w-full" value={form.data.discord_webhook}
               onChange={(e) => form.setData("discord_webhook", e.target.value)} />
           </Field>
           <label className="flex items-center gap-2 text-sm">
             <input type="checkbox" checked={form.data.active}
               onChange={(e) => form.setData("active", e.target.checked)} />
             Active (receive notifications)
           </label>
           <div className="flex gap-2">
             <button type="submit" disabled={form.processing}
               className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm">Save</button>
             <button type="button" onClick={destroy}
               className="bg-red-600 text-white px-3 py-1.5 rounded text-sm">Delete</button>
           </div>
         </form>
       </>
     );
   }

   function Field({ label, error, children }: { label: string; error?: string[]; children: React.ReactNode }) {
     return (
       <label className="block">
         <span className="text-sm font-medium">{label}</span>
         <div className="mt-1">{children}</div>
         {error && <div className="text-red-600 text-xs mt-1">{error.join(", ")}</div>}
       </label>
     );
   }
   ```

5. `bin/rspec spec/requests/topics_spec.rb` → **PASS**.

6. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add topic edit/update flow"
   ```
