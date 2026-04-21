# Task 11 — Admin topic CRUD (`Admin::TopicsController`)

**Status:** pending (replaces the old per-user "topic edit" task)
**Depends on:** Task 10.

Admins manage the shared topic catalog at `/admin/topics`. Actions: `index`, `new`, `create`, `edit`, `update` — explicitly no `destroy` (soft-disable via `active: false`). Gated by `require_admin!` (Task 7b).

Routes are already declared in Task 9:
```ruby
namespace :admin do
  root "topics#index"
  resources :topics, except: [:destroy, :show]
end
```

## Files

- Create: `app/controllers/admin/topics_controller.rb`
- Create: `app/frontend/pages/admin/topics/index.tsx`
- Create: `app/frontend/pages/admin/topics/new.tsx`
- Create: `app/frontend/pages/admin/topics/edit.tsx`
- Create: `spec/requests/admin/topics_spec.rb`

## Steps

1. Write failing request spec. Create `spec/requests/admin/topics_spec.rb`:
   ```ruby
   require "rails_helper"

   RSpec.describe "Admin::Topics", type: :request do
     let(:admin) { create(:user, admin: true) }
     let(:regular) { create(:user) }

     describe "access control" do
       it "redirects non-admins off /admin/topics" do
         sign_in regular
         get "/admin/topics"
         expect(response).to redirect_to(root_path)
         follow_redirect!
         expect(flash[:alert]).to match(/admins only/i)
       end

       it "allows admins through" do
         sign_in admin
         get "/admin/topics"
         expect(response).to have_http_status(:ok)
         expect(response.body).to include("admin/topics/index")
       end
     end

     describe "GET /admin/topics/new" do
       before { sign_in admin }

       it "renders the new form" do
         get "/admin/topics/new"
         expect(response).to have_http_status(:ok)
         expect(response.body).to include("admin/topics/new")
       end
     end

     describe "POST /admin/topics" do
       before { sign_in admin }

       context "with valid params" do
         it "creates a topic with this admin as creator" do
           expect {
             post "/admin/topics", params: {
               topic: { name: "Rust", keywords: ["rust", "cargo"], active: true }
             }
           }.to change(Topic, :count).by(1)
           expect(Topic.last.created_by).to eq(admin)
           expect(response).to redirect_to(admin_topics_path)
         end
       end

       context "with a duplicate name" do
         it "re-renders with uniqueness error" do
           create(:topic, name: "Rust")
           post "/admin/topics", params: {
             topic: { name: "Rust", keywords: ["rust"], active: true }
           }
           expect(response).to have_http_status(:unprocessable_content)
           expect(response.body).to include("admin/topics/new")
         end
       end

       context "with invalid keywords" do
         it "re-renders with error" do
           post "/admin/topics", params: {
             topic: { name: "Empty", keywords: [], active: true }
           }
           expect(response).to have_http_status(:unprocessable_content)
         end
       end
     end

     describe "PATCH /admin/topics/:id" do
       before { sign_in admin }
       let!(:topic) { create(:topic, name: "Old") }

       it "updates valid params" do
         patch "/admin/topics/#{topic.id}", params: {
           topic: { name: "New", keywords: ["a", "b"], active: false }
         }
         expect(topic.reload.name).to eq("New")
         expect(topic.active).to be false
         expect(response).to redirect_to(admin_topics_path)
       end
     end
   end
   ```

2. Run → **FAIL** (controller missing).

3. Create `app/controllers/admin/topics_controller.rb`:
   ```ruby
   class Admin::TopicsController < ApplicationController
     before_action :require_admin!
     before_action :set_topic, only: [:edit, :update]

     def index
       topics = Topic.order(:name)
       render inertia: "admin/topics/index", props: {
         topics: topics.map { |t| topic_props(t) }
       }
     end

     def new
       render inertia: "admin/topics/new", props: {
         topic: { name: "", keywords: [], active: true },
         errors: {},
       }
     end

     def create
       topic = Topic.new(topic_params.merge(created_by: current_user))
       if topic.save
         redirect_to admin_topics_path, notice: "Topic created."
       else
         render inertia: "admin/topics/new", props: {
           topic: topic.attributes.slice("name", "keywords", "active"),
           errors: topic.errors.to_hash,
         }, status: :unprocessable_content
       end
     end

     def edit
       render inertia: "admin/topics/edit", props: {
         topic: topic_props(@topic),
         errors: {},
       }
     end

     def update
       if @topic.update(topic_params)
         redirect_to admin_topics_path, notice: "Topic updated."
       else
         render inertia: "admin/topics/edit", props: {
           topic: topic_props(@topic),
           errors: @topic.errors.to_hash,
         }, status: :unprocessable_content
       end
     end

     private

     def set_topic
       @topic = Topic.find(params[:id])
     end

     def topic_params
       params.require(:topic).permit(:name, :active, keywords: [])
     end

     def topic_props(topic)
       {
         id: topic.id,
         name: topic.name,
         keywords: topic.keywords,
         active: topic.active,
         subscriber_count: topic.topic_subscriptions.count,
       }
     end
   end
   ```

4. Create `app/frontend/pages/admin/topics/index.tsx`:
   ```tsx
   import { Head, Link } from "@inertiajs/react";

   type Topic = {
     id: number;
     name: string;
     keywords: string[];
     active: boolean;
     subscriber_count: number;
   };

   export default function Index({ topics }: { topics: Topic[] }) {
     return (
       <>
         <Head title="Admin · Topics" />
         <div className="flex justify-between items-center mb-4">
           <h1 className="text-2xl font-semibold">Topics (admin)</h1>
           <Link
             href="/admin/topics/new"
             className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm"
           >
             New topic
           </Link>
         </div>
         {topics.length === 0 ? (
           <p className="text-gray-600">No topics yet.</p>
         ) : (
           <ul className="bg-white rounded border border-gray-200 divide-y">
             {topics.map((t) => (
               <li key={t.id} className="p-3 flex justify-between items-center">
                 <div>
                   <div className="font-medium">
                     {t.name}
                     {!t.active && (
                       <span className="ml-2 text-xs text-gray-500">(inactive)</span>
                     )}
                   </div>
                   <div className="text-xs text-gray-500">
                     {t.keywords.join(", ")} · {t.subscriber_count} subscriber
                     {t.subscriber_count === 1 ? "" : "s"}
                   </div>
                 </div>
                 <Link
                   href={`/admin/topics/${t.id}/edit`}
                   className="text-blue-600 text-sm"
                 >
                   Edit
                 </Link>
               </li>
             ))}
           </ul>
         )}
       </>
     );
   }
   ```

5. Create `app/frontend/pages/admin/topics/new.tsx`:
   ```tsx
   import { Head, useForm } from "@inertiajs/react";
   import { FormEvent } from "react";

   type Form = { name: string; keywords: string[]; active: boolean };
   type Props = { topic: Form; errors: Record<string, string[]> };

   export default function New({ topic, errors }: Props) {
     const form = useForm<Form>({
       name: topic.name,
       keywords: topic.keywords,
       active: topic.active ?? true,
     });

     const submit = (e: FormEvent) => {
       e.preventDefault();
       form.post("/admin/topics");
     };

     const setKeywordsFromString = (s: string) =>
       form.setData(
         "keywords",
         s.split(",").map((k) => k.trim()).filter(Boolean)
       );

     return (
       <>
         <Head title="Admin · New topic" />
         <h1 className="text-2xl font-semibold mb-4">New topic</h1>
         <form
           onSubmit={submit}
           className="max-w-lg space-y-4 bg-white p-4 rounded border"
         >
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
           <label className="flex items-center gap-2 text-sm">
             <input
               type="checkbox"
               checked={form.data.active}
               onChange={(e) => form.setData("active", e.target.checked)}
             />
             Active
           </label>
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

   function Field({
     label,
     error,
     children,
   }: {
     label: string;
     error?: string[];
     children: React.ReactNode;
   }) {
     return (
       <label className="block">
         <span className="text-sm font-medium">{label}</span>
         <div className="mt-1">{children}</div>
         {error && <div className="text-red-600 text-xs mt-1">{error.join(", ")}</div>}
       </label>
     );
   }
   ```

6. Create `app/frontend/pages/admin/topics/edit.tsx`:
   ```tsx
   import { Head, useForm } from "@inertiajs/react";
   import { FormEvent } from "react";

   type Form = {
     id: number;
     name: string;
     keywords: string[];
     active: boolean;
     subscriber_count: number;
   };
   type Props = { topic: Form; errors: Record<string, string[]> };

   export default function Edit({ topic, errors }: Props) {
     const form = useForm({
       name: topic.name,
       keywords: topic.keywords,
       active: topic.active,
     });

     const submit = (e: FormEvent) => {
       e.preventDefault();
       form.patch(`/admin/topics/${topic.id}`);
     };

     const setKeywordsFromString = (s: string) =>
       form.setData(
         "keywords",
         s.split(",").map((k) => k.trim()).filter(Boolean)
       );

     return (
       <>
         <Head title={`Admin · Edit: ${topic.name}`} />
         <h1 className="text-2xl font-semibold mb-4">Edit topic</h1>
         <p className="text-xs text-gray-500 mb-4">
           {topic.subscriber_count} subscriber
           {topic.subscriber_count === 1 ? "" : "s"}
         </p>
         <form
           onSubmit={submit}
           className="max-w-lg space-y-4 bg-white p-4 rounded border"
         >
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
           <label className="flex items-center gap-2 text-sm">
             <input
               type="checkbox"
               checked={form.data.active}
               onChange={(e) => form.setData("active", e.target.checked)}
             />
             Active (disabled topics are skipped by the pipeline)
           </label>
           <button
             type="submit"
             disabled={form.processing}
             className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm"
           >
             Save
           </button>
         </form>
       </>
     );
   }

   function Field({
     label,
     error,
     children,
   }: {
     label: string;
     error?: string[];
     children: React.ReactNode;
   }) {
     return (
       <label className="block">
         <span className="text-sm font-medium">{label}</span>
         <div className="mt-1">{children}</div>
         {error && <div className="text-red-600 text-xs mt-1">{error.join(", ")}</div>}
       </label>
     );
   }
   ```

7. Run `bin/rspec spec/requests/admin/topics_spec.rb` → **PASS**.

8. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add Admin::TopicsController with index/new/create/edit/update"
   ```
