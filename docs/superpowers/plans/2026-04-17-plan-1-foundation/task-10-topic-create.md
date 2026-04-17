# Task 10 — Topic create flow (new + create)

**Status:** pending
**Depends on:** Task 9.

## Files

- Modify: `app/controllers/topics_controller.rb`, `spec/requests/topics_spec.rb`
- Create: `app/frontend/Pages/Topics/New.tsx`

## Steps

1. Append to `spec/requests/topics_spec.rb` inside the main describe block:
   ```ruby
   describe "GET /topics/new" do
     before { sign_in user }

     it "renders the new topic form" do
       get "/topics/new"
       expect(response).to have_http_status(:ok)
       expect(response.body).to include("Topics/New")
     end
   end

   describe "POST /topics" do
     before { sign_in user }

     context "with valid params" do
       it "creates a topic and redirects to index" do
         expect {
           post "/topics", params: {
             topic: { name: "Rust", keywords: ["rust lang", "cargo"], discord_webhook: "" }
           }
         }.to change(Topic, :count).by(1)
         expect(response).to redirect_to(topics_path)
       end
     end

     context "with invalid params" do
       it "renders new with errors" do
         post "/topics", params: { topic: { name: "", keywords: [] } }
         expect(response).to have_http_status(:unprocessable_entity)
         expect(response.body).to include("Topics/New")
       end
     end
   end
   ```

2. Run → **FAIL**.

3. Replace `app/controllers/topics_controller.rb`:
   ```ruby
   class TopicsController < ApplicationController
     before_action :set_topic, only: [:edit, :update, :destroy]

     def index
       topics = current_user.topics.order(created_at: :desc)
       render inertia: "Topics/Index", props: {
         topics: topics.map { |t| topic_props(t) }
       }
     end

     def new
       render inertia: "Topics/New", props: {
         topic: empty_topic_form,
         errors: {},
       }
     end

     def create
       topic = current_user.topics.build(topic_params)
       if topic.save
         redirect_to topics_path, notice: "Topic created."
       else
         render inertia: "Topics/New", props: {
           topic: topic.attributes.slice("name", "keywords", "discord_webhook", "active"),
           errors: topic.errors.to_hash,
         }, status: :unprocessable_entity
       end
     end

     private

     def set_topic
       @topic = current_user.topics.find(params[:id])
     end

     def topic_params
       params.require(:topic).permit(:name, :discord_webhook, :active, keywords: [])
     end

     def topic_props(topic)
       {
         id: topic.id,
         name: topic.name,
         keywords: topic.keywords,
         active: topic.active,
         has_discord: topic.discord_webhook.present?,
       }
     end

     def empty_topic_form
       { name: "", keywords: [], discord_webhook: "", active: true }
     end
   end
   ```

4. `app/frontend/Pages/Topics/New.tsx`:
   ```tsx
   import { Head, useForm } from "@inertiajs/react";
   import { FormEvent } from "react";

   type Form = { name: string; keywords: string[]; discord_webhook: string; active: boolean };
   type Props = { topic: Form; errors: Record<string, string[]> };

   export default function New({ topic, errors }: Props) {
     const form = useForm<Form>({
       name: topic.name,
       keywords: topic.keywords,
       discord_webhook: topic.discord_webhook,
       active: topic.active ?? true,
     });

     const submit = (e: FormEvent) => {
       e.preventDefault();
       form.post("/topics");
     };

     const setKeywordsFromString = (s: string) => {
       form.setData("keywords", s.split(",").map((k) => k.trim()).filter(Boolean));
     };

     return (
       <>
         <Head title="New topic" />
         <h1 className="text-2xl font-semibold mb-4">New topic</h1>
         <form onSubmit={submit} className="max-w-lg space-y-4 bg-white p-4 rounded border">
           <Field label="Name" error={errors.name}>
             <input
               className="border rounded px-2 py-1 w-full"
               value={form.data.name}
               onChange={(e) => form.setData("name", e.target.value)}
             />
           </Field>
           <Field label="Keywords (comma-separated)" error={errors.keywords}>
             <input
               className="border rounded px-2 py-1 w-full"
               defaultValue={form.data.keywords.join(", ")}
               onBlur={(e) => setKeywordsFromString(e.target.value)}
             />
           </Field>
           <Field label="Discord webhook URL (optional)" error={errors.discord_webhook}>
             <input
               className="border rounded px-2 py-1 w-full"
               value={form.data.discord_webhook}
               onChange={(e) => form.setData("discord_webhook", e.target.value)}
             />
           </Field>
           <button
             type="submit"
             disabled={form.processing}
             className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm"
           >
             Create
           </button>
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
   git commit -m "feat: add topic new/create flow"
   ```
