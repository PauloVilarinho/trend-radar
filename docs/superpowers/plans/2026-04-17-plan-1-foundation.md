# Trend Radar — Plan 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**2026-04-20 amendment:** topics flipped to a shared, admin-curated catalog. Per-user ownership moved to a `topic_subscriptions` join table. A `users.admin` boolean and a new `/admin/topics` namespace gate CRUD to admins; regular users only subscribe. Tasks 7–12 were redesigned; tasks 7b and 8b were inserted.

**Goal:** Bootstrap a Rails 8 + Inertia/React + Devise application with a shared `Topic` catalog (admin-curated), a `TopicSubscription` join that carries per-user Discord webhooks, a `PushSubscription` model, Kamal deployment config, and CI. Produces a working web app where admins curate topics and regular users subscribe — no data ingestion yet.

**Architecture:** Single Rails 8 monolith. Authentication via Devise with plain ERB views. Rest of app uses Inertia.js to render React pages from Rails controllers. PostgreSQL for data. SolidQueue for background jobs (used by later plans; configured here). Deploy via Kamal 2 to a single VPS.

**Tech Stack:** Ruby 3.3+, Rails 8.0+, PostgreSQL 16+, Devise, inertia_rails gem, React 18, Vite (vite_rails), TailwindCSS 3, RSpec, FactoryBot, WebMock, VCR, Kamal 2.

---

## File Structure

New files created in this plan:

| File | Purpose |
|---|---|
| `Gemfile`, `Gemfile.lock` | Ruby dependencies |
| `config/database.yml` | Postgres config |
| `config/routes.rb` | Route definitions |
| `config/initializers/devise.rb` | Devise config |
| `config/initializers/inertia_rails.rb` | Inertia SSR/version config |
| `config/deploy.yml` | Kamal deploy config |
| `app/frontend/entrypoints/application.tsx` | Vite entrypoint, Inertia bootstrap |
| `app/frontend/layouts/AppLayout.tsx` | Shared React layout |
| `app/frontend/pages/dashboard/index.tsx` | Dashboard placeholder |
| `app/frontend/pages/topics/index.tsx` | Topics catalog (read-only) with inline subscription form |
| `app/frontend/pages/admin/topics/index.tsx` | Admin catalog listing |
| `app/frontend/pages/admin/topics/new.tsx` | Admin: new topic form |
| `app/frontend/pages/admin/topics/edit.tsx` | Admin: edit topic form |
| `app/models/user.rb` | Devise User with `admin` flag |
| `app/models/topic.rb` | Topic (shared catalog, admin-curated) |
| `app/models/topic_subscription.rb` | Per-user subscription join record |
| `app/models/push_subscription.rb` | Push subscription record |
| `app/controllers/application_controller.rb` | Base controller with Inertia helpers and `require_admin!` |
| `app/controllers/dashboard_controller.rb` | Dashboard landing |
| `app/controllers/topics_controller.rb` | Topics catalog (read-only index for regular users) |
| `app/controllers/topic_subscriptions_controller.rb` | Subscribe / update / unsubscribe |
| `app/controllers/admin/topics_controller.rb` | Admin topic CRUD (no destroy) |
| `lib/tasks/admin.rake` | `rake admin:promote[email]` promotes a user |
| `db/migrate/*_devise_create_users.rb` | Users table |
| `db/migrate/*_add_admin_to_users.rb` | `admin` boolean on users |
| `db/migrate/*_create_topics.rb` | Topics table (shared catalog) |
| `db/migrate/*_create_topic_subscriptions.rb` | Per-user subscription join |
| `db/migrate/*_create_push_subscriptions.rb` | Push subscriptions table |
| `spec/rails_helper.rb`, `spec/spec_helper.rb` | RSpec config |
| `spec/factories/*.rb` | FactoryBot factories |
| `spec/models/topic_spec.rb` | Topic model tests |
| `spec/requests/topics_spec.rb` | Topics controller tests |
| `spec/support/inertia_helpers.rb` | Test helpers for Inertia |
| `.github/workflows/ci.yml` | CI pipeline |

---

## Task 1: Bootstrap Rails 8 application

**Files:**
- Create: full Rails app skeleton in project root

- [ ] **Step 1: Verify Ruby version**

Run: `ruby -v`
Expected: Ruby 3.3.0 or newer. If not, install via rbenv/asdf.

- [ ] **Step 2: Generate Rails 8 app**

Run from `/Users/paulotarso/codeminer42/trend-radar`:
```bash
gem install rails -v "~> 8.0.0"
rails new . --database=postgresql --css=tailwind --javascript=vite --skip-test --force
```

The `--force` overwrites the existing empty dir. `--skip-test` because we'll use RSpec.

- [ ] **Step 3: Verify app boots**

Run:
```bash
bin/rails db:create
bin/rails server
```
Expected: server starts on `localhost:3000`, default Rails welcome page loads. Stop with Ctrl-C.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: bootstrap Rails 8 app with postgres, tailwind, vite"
```

---

## Task 2: Add core gems (Devise, Inertia, RSpec, testing tools)

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gems to Gemfile**

Append to `Gemfile`:
```ruby
gem "devise"
gem "inertia_rails"
gem "pg_search" # useful later; include now to avoid bundle churn

group :development, :test do
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails"
  gem "faker"
  gem "dotenv-rails"
end

group :test do
  gem "webmock"
  gem "vcr"
  gem "capybara"
  gem "selenium-webdriver"
  gem "rails-controller-testing"
end
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: bundle completes without errors.

- [ ] **Step 3: Initialize RSpec**

Run: `bin/rails generate rspec:install`
Expected: creates `spec/spec_helper.rb`, `spec/rails_helper.rb`, `.rspec`.

- [ ] **Step 4: Configure RSpec for FactoryBot, WebMock, VCR**

Edit `spec/rails_helper.rb`. After `require 'rspec/rails'` line, add:

```ruby
require "webmock/rspec"
require "vcr"

VCR.configure do |c|
  c.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.filter_sensitive_data("<OPENAI_API_KEY>") { ENV["OPENAI_API_KEY"] }
  c.default_cassette_options = { record: :new_episodes }
end

WebMock.disable_net_connect!(allow_localhost: true)
```

Inside the `RSpec.configure` block, add:
```ruby
  config.include FactoryBot::Syntax::Methods
```

- [ ] **Step 5: Smoke-test RSpec**

Run: `bin/rspec`
Expected: "No examples found." with exit 0.

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock .rspec spec/
git commit -m "chore: add devise, inertia, rspec, webmock, vcr, factory_bot"
```

---

## Task 3: Install and configure Devise

**Files:**
- Create: `config/initializers/devise.rb`
- Create: `app/models/user.rb`
- Create: `db/migrate/*_devise_create_users.rb`

- [ ] **Step 1: Run Devise generator**

```bash
bin/rails generate devise:install
```

- [ ] **Step 2: Configure default URL options**

Edit `config/environments/development.rb`. Add inside the `config` block:
```ruby
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
```

- [ ] **Step 3: Generate User model**

```bash
bin/rails generate devise User
bin/rails db:migrate
```

- [ ] **Step 4: Generate Devise views**

```bash
bin/rails generate devise:views
```

These are plain ERB views — intentionally not Inertia. They will render with a minimal layout.

- [ ] **Step 5: Write user factory**

Create `spec/factories/users.rb`:
```ruby
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
  end
end
```

- [ ] **Step 6: Verify sign-up works manually**

Run `bin/rails server`, visit `http://localhost:3000/users/sign_up`, create a user. Expected: redirect to `/` (root not yet defined — will be added in Task 6; a "no route matches" error is acceptable here). Stop server.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add devise user model and auth views"
```

---

## Task 4: Install and configure Inertia.js + React

**Files:**
- Create: `app/frontend/entrypoints/application.tsx`
- Create: `app/frontend/layouts/AppLayout.tsx`
- Create: `app/views/layouts/application.html.erb` (modify to host Inertia root)
- Create: `config/initializers/inertia_rails.rb`

- [ ] **Step 1: Install inertia-rails generator + React dependencies**

```bash
bin/rails generate inertia:install --framework=react --typescript --vite
```

This generator installs npm packages (@inertiajs/react, react, react-dom, typescript, @vitejs/plugin-react), configures `vite.config.ts`, and creates an initial `application.tsx`.

- [ ] **Step 2: Verify the generator's scaffolding**

Confirm these exist:
- `app/frontend/entrypoints/application.tsx`
- `app/frontend/pages/` (generator default; keep lowercase)
- `vite.config.ts` has React plugin configured
- `package.json` has `react`, `react-dom`, `@inertiajs/react`

- [ ] **Step 3: Ensure `pages/` and `layouts/` exist (lowercase)**

```bash
mkdir -p app/frontend/pages app/frontend/layouts
```

- [ ] **Step 4: Create shared layout**

Create `app/frontend/layouts/AppLayout.tsx`:
```tsx
import { ReactNode } from "react";
import { Link, usePage } from "@inertiajs/react";

type PageProps = {
  current_user: { email: string } | null;
  flash: { notice?: string; alert?: string };
};

export default function AppLayout({ children }: { children: ReactNode }) {
  const { current_user, flash } = usePage<PageProps>().props;

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b border-gray-200">
        <div className="mx-auto max-w-6xl px-4 py-3 flex justify-between items-center">
          <Link href="/" className="font-semibold text-lg">Trend Radar</Link>
          <nav className="flex gap-4 text-sm">
            {current_user ? (
              <>
                <Link href="/topics">Topics</Link>
                <Link href="/users/sign_out" method="delete" as="button">Sign out</Link>
              </>
            ) : (
              <>
                <Link href="/users/sign_in">Sign in</Link>
                <Link href="/users/sign_up">Sign up</Link>
              </>
            )}
          </nav>
        </div>
      </header>
      {flash.notice && (
        <div className="bg-green-50 text-green-800 px-4 py-2 text-sm">{flash.notice}</div>
      )}
      {flash.alert && (
        <div className="bg-red-50 text-red-800 px-4 py-2 text-sm">{flash.alert}</div>
      )}
      <main className="mx-auto max-w-6xl px-4 py-6">{children}</main>
    </div>
  );
}
```

- [ ] **Step 5: Wire AppLayout as default in entrypoint**

Edit `app/frontend/entrypoints/application.tsx` to use the layout by default. Replace the `resolve` function body with:
```tsx
import AppLayout from "../layouts/AppLayout";

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob("../pages/**/*.tsx", { eager: true });
    const page = pages[`../pages/${name}.tsx`] as { default: React.FC & { layout?: unknown } };
    page.default.layout ||= (page: React.ReactNode) => <AppLayout>{page}</AppLayout>;
    return page;
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />);
  },
});
```

(Imports for `createInertiaApp`, `createRoot`, `React` stay as generated.)

- [ ] **Step 6: Add shared Inertia props**

Create `app/controllers/application_controller.rb`, replacing generator content:
```ruby
class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :authenticate_user!

  inertia_share do
    {
      current_user: current_user && { id: current_user.id, email: current_user.email },
      flash: { notice: flash[:notice], alert: flash[:alert] }.compact,
    }
  end
end
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: configure inertia + react with shared AppLayout"
```

---

## Task 5: Configure TailwindCSS for Inertia pages

**Files:**
- Modify: `app/frontend/entrypoints/application.css` (or create)
- Verify: `vite.config.ts` includes Tailwind

- [ ] **Step 1: Verify Tailwind is already wired**

Check `app/assets/tailwind/application.css` exists (from `--css=tailwind`). Check `app/views/layouts/application.html.erb` has `<%= stylesheet_link_tag "tailwind", "inter-font", "data-turbo-track": "reload" %>`.

- [ ] **Step 2: Ensure Tailwind scans React files**

Edit `config/tailwind.config.js` (or `tailwind.config.js`). In `content:`, add `./app/frontend/**/*.{js,jsx,ts,tsx}`:
```js
module.exports = {
  content: [
    "./public/*.html",
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.js",
    "./app/views/**/*.{erb,haml,html,slim}",
    "./app/frontend/**/*.{js,jsx,ts,tsx}",
  ],
  // ... rest unchanged
}
```

- [ ] **Step 3: Verify styling works**

Create a temporary test page: run `bin/rails server` + `bin/vite dev` (two terminals) and visit a page. Expected: Tailwind utility classes render correctly. Stop servers.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: configure tailwind to scan frontend/**"
```

---

## Task 6: Dashboard placeholder page + routes

**Files:**
- Create: `app/controllers/dashboard_controller.rb`
- Create: `app/frontend/pages/dashboard/index.tsx`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write failing request spec**

Create `spec/requests/dashboard_spec.rb`:
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

- [ ] **Step 2: Add Devise test helpers**

Edit `spec/rails_helper.rb`, add inside `RSpec.configure`:
```ruby
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
```

- [ ] **Step 3: Run test — expect FAIL**

Run: `bin/rspec spec/requests/dashboard_spec.rb`
Expected: FAIL — no route for `/`.

- [ ] **Step 4: Add route, controller, page**

Edit `config/routes.rb`:
```ruby
Rails.application.routes.draw do
  devise_for :users
  root to: "dashboard#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
```

Create `app/controllers/dashboard_controller.rb`:
```ruby
class DashboardController < ApplicationController
  def index
    render inertia: "dashboard/index", props: {}
  end
end
```

Create `app/frontend/pages/dashboard/index.tsx`:
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

- [ ] **Step 5: Run test — expect PASS**

Run: `bin/rspec spec/requests/dashboard_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add dashboard placeholder page at root"
```

---

## Task 7: Topic model (shared catalog) with validations (TDD)

See [`2026-04-17-plan-1-foundation/task-07-topic-model.md`](2026-04-17-plan-1-foundation/task-07-topic-model.md) for the full step-by-step. Summary:

- `topics` is a **shared** table (no `user_id`). Column `created_by_id` (nullable fk users, `on_delete: nullify`) records the admin who added the row.
- Columns: `created_by_id`, `name`, `keywords` (text[]), `active` (default true), timestamps. No `discord_webhook` column — per-user webhooks live on `topic_subscriptions`.
- Index: `add_index :topics, "LOWER(name)", unique: true` (globally unique, case-insensitive).
- Validations: name presence + uniqueness (case-insensitive), keywords ≥1 and ≤20, no blank keyword strings. **No** per-user cap on this model (lives on the subscription, Task 8b).
- `User` gains `has_many :created_topics, class_name: "Topic", foreign_key: :created_by_id, dependent: :nullify`. No `has_many :topics`.

## Task 7b: Add `admin` flag to users + `require_admin!` gate (TDD)

See [`2026-04-17-plan-1-foundation/task-07b-add-admin-to-users.md`](2026-04-17-plan-1-foundation/task-07b-add-admin-to-users.md). Summary:

- Migration: `add_column :users, :admin, :boolean, null: false, default: false`.
- `lib/tasks/admin.rake` adds `rake admin:promote[email]`.
- `ApplicationController#require_admin!` redirects non-admins to root with an "Admins only." alert; the shared `inertia_share` exposes `current_user.admin` so the layout can render the admin nav link.

---

## Task 8: PushSubscription model (TDD)

**Files:**
- Create: `db/migrate/*_create_push_subscriptions.rb`
- Create: `app/models/push_subscription.rb`
- Create: `spec/models/push_subscription_spec.rb`
- Create: `spec/factories/push_subscriptions.rb`

- [ ] **Step 1: Write failing spec**

Create `spec/models/push_subscription_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe PushSubscription, type: :model do
  let(:user) { create(:user) }

  it "is valid with all required fields" do
    sub = build(:push_subscription, user: user)
    expect(sub).to be_valid
  end

  it "requires endpoint" do
    sub = build(:push_subscription, user: user, endpoint: nil)
    expect(sub).not_to be_valid
  end

  it "requires p256dh_key" do
    sub = build(:push_subscription, user: user, p256dh_key: nil)
    expect(sub).not_to be_valid
  end

  it "requires auth_key" do
    sub = build(:push_subscription, user: user, auth_key: nil)
    expect(sub).not_to be_valid
  end

  it "rejects duplicate endpoints for same user" do
    existing = create(:push_subscription, user: user, endpoint: "https://push.example/abc")
    dup = build(:push_subscription, user: user, endpoint: "https://push.example/abc")
    expect(dup).not_to be_valid
  end
end
```

- [ ] **Step 2: Create factory**

Create `spec/factories/push_subscriptions.rb`:
```ruby
FactoryBot.define do
  factory :push_subscription do
    user
    sequence(:endpoint) { |n| "https://push.example.com/#{n}" }
    p256dh_key { "sample-p256dh-key" }
    auth_key { "sample-auth-key" }
    user_agent { "Mozilla/5.0" }
  end
end
```

- [ ] **Step 3: Run test — expect FAIL**

Run: `bin/rspec spec/models/push_subscription_spec.rb`
Expected: FAIL — class not defined.

- [ ] **Step 4: Migration**

```bash
bin/rails generate migration CreatePushSubscriptions user:references endpoint:string p256dh_key:string auth_key:string user_agent:string
```

Edit migration:
```ruby
class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.string :user_agent
      t.timestamps
    end
    add_index :push_subscriptions, [:user_id, :endpoint], unique: true
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 5: Model**

Create `app/models/push_subscription.rb`:
```ruby
class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true,
                       uniqueness: { scope: :user_id }
  validates :p256dh_key, :auth_key, presence: true
end
```

Add `has_many :push_subscriptions, dependent: :destroy` to `User`:
```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :created_topics,
           class_name: "Topic",
           foreign_key: :created_by_id,
           dependent: :nullify
  has_many :topic_subscriptions, dependent: :destroy
  has_many :subscribed_topics, through: :topic_subscriptions, source: :topic
  has_many :push_subscriptions, dependent: :destroy
end
```

(The `topic_subscriptions` / `subscribed_topics` associations are wired in Task 8b; listed here for the complete User shape at end-of-Plan-1.)

- [ ] **Step 6: Run tests — expect PASS**

Run: `bin/rspec spec/models/push_subscription_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add PushSubscription model"
```

---

## Task 8b: TopicSubscription join model (TDD)

See [`2026-04-17-plan-1-foundation/task-08b-topic-subscription-model.md`](2026-04-17-plan-1-foundation/task-08b-topic-subscription-model.md). Summary:

- Migration creates `topic_subscriptions (user_id, topic_id, discord_webhook, active, timestamps)` with cascade deletes on both fks and a unique `(user_id, topic_id)` index.
- Model: `belongs_to :user`, `belongs_to :topic`, `encrypts :discord_webhook`, webhook format validation, 50-subscriptions-per-user cap.
- `User` adds `has_many :topic_subscriptions` + `has_many :subscribed_topics, through: ..., source: :topic`.
- `Topic` adds `has_many :topic_subscriptions` + `has_many :subscribers, through: ..., source: :user`.

## Task 9: Topics catalog index page (read-only)

See [`2026-04-17-plan-1-foundation/task-09-topics-index.md`](2026-04-17-plan-1-foundation/task-09-topics-index.md). Summary:

- Routes:
  ```ruby
  resources :topics, only: [:index] do
    resource :subscription, only: [:create, :update, :destroy],
                            controller: "topic_subscriptions"
  end

  namespace :admin do
    root "topics#index"
    resources :topics, except: [:destroy, :show]
  end
  ```
- `TopicsController#index` — lists `Topic.active.order(:name)` with each row's subscription state for `current_user`.
- `pages/topics/index.tsx` — each row shows a Subscribe button if unsubscribed, or an inline form (discord webhook + active checkbox + unsubscribe button) if subscribed. No `topics/new` / `topics/edit` pages under `/topics` — those live under `/admin/topics` (Task 11).

## Task 10: TopicSubscription flow (subscribe / update / unsubscribe)

See [`2026-04-17-plan-1-foundation/task-10-topic-subscription-flow.md`](2026-04-17-plan-1-foundation/task-10-topic-subscription-flow.md). Summary:

- `TopicSubscriptionsController#create` — `find_or_initialize_by(topic:)` → save. Idempotent; enforces the 50-cap; redirects back to `/topics`.
- `#update` — permits `discord_webhook` and `active`. Uses `status: :unprocessable_content` on validation failure (Rails 8 naming).
- `#destroy` — removes the subscription.

## Task 11: Admin topic CRUD (`Admin::TopicsController`)

See [`2026-04-17-plan-1-foundation/task-11-topic-edit.md`](2026-04-17-plan-1-foundation/task-11-topic-edit.md). Summary:

- `before_action :require_admin!`.
- Actions: `index`, `new`, `create`, `edit`, `update`. No `destroy` (soft-disable via `active: false`).
- On create, assigns `created_by: current_user`.
- Pages: `pages/admin/topics/{index,new,edit}.tsx` (all lowercase).

## Task 12: AppLayout admin nav link

See [`2026-04-17-plan-1-foundation/task-12-topic-destroy.md`](2026-04-17-plan-1-foundation/task-12-topic-destroy.md) (file name kept for stability; content is now the AppLayout nav link task). Summary:

- `app/frontend/layouts/AppLayout.tsx` renders `<Link href="/admin/topics">Admin</Link>` when `current_user.admin`. The admin flag is already on `current_user` via `inertia_share` (Task 7b).

> **Note (2026-04-20 amendment):** Tasks 9–12's previous inline step-by-step bodies (per-user Topics CRUD) were removed when the design shifted to the shared catalog + subscription model. Recover the pre-amendment text from git history if needed; the linked per-task files are authoritative.

---

## Task 13: SolidQueue setup

**Files:**
- Modify: `config/database.yml`
- Create: `config/queue.yml`
- Modify: `config/application.rb`

- [ ] **Step 1: Install SolidQueue**

```bash
bin/rails solid_queue:install
bin/rails db:migrate
```

This generates `db/queue_schema.rb` and the queue database config.

- [ ] **Step 2: Verify queue connection**

Check `config/database.yml` has a `queue` entry (the installer adds it). Production config should include it too.

- [ ] **Step 3: Set Active Job adapter**

Edit `config/application.rb`, inside the `Application` class:
```ruby
    config.active_job.queue_adapter = :solid_queue
```

- [ ] **Step 4: Verify with a trivial job**

Run `bin/rails console`:
```ruby
class SmokeJob < ApplicationJob
  def perform; Rails.logger.info("smoke"); end
end
SmokeJob.perform_later
```
Then run: `bin/jobs start` (in another terminal, briefly) — expected: log shows "smoke". Stop with Ctrl-C. Remove SmokeJob from memory (exit console).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: install solid_queue for background jobs"
```

---

## Task 14: Kamal deployment config

**Files:**
- Modify: `config/deploy.yml`
- Create: `.kamal/secrets`

- [ ] **Step 1: Review generated Kamal config**

Rails 8 generates `config/deploy.yml`. Edit it for your VPS:
```yaml
service: trend-radar
image: trend-radar

servers:
  web:
    hosts:
      - <YOUR_VPS_IP>  # ← fill in with actual IP
  worker:
    hosts:
      - <YOUR_VPS_IP>
    cmd: bin/jobs start
  scheduler:
    hosts:
      - <YOUR_VPS_IP>
    cmd: bin/jobs start --recurring-schedule-file=config/recurring.yml

proxy:
  ssl: true
  host: <YOUR_DOMAIN>  # ← fill in

registry:
  server: ghcr.io
  username: <YOUR_GITHUB_USERNAME>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    RAILS_LOG_TO_STDOUT: "1"
    RAILS_SERVE_STATIC_FILES: "1"
  secret:
    - RAILS_MASTER_KEY
    - POSTGRES_PASSWORD
    - OPENAI_API_KEY
    - VAPID_PUBLIC_KEY
    - VAPID_PRIVATE_KEY
    - VAPID_SUBJECT

accessories:
  postgres:
    image: postgres:16
    host: <YOUR_VPS_IP>
    port: 5432
    env:
      clear:
        POSTGRES_USER: trend_radar
        POSTGRES_DB: trend_radar_production
      secret:
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data
```

Note: the `<PLACEHOLDER>` values must be filled by the deployer before first deploy. This is expected configuration, not a plan placeholder.

- [ ] **Step 2: Create secrets file**

Create `.kamal/secrets`:
```
KAMAL_REGISTRY_PASSWORD=$(cat ~/.kamal/github_token)
RAILS_MASTER_KEY=$(cat config/master.key)
POSTGRES_PASSWORD=$KAMAL_POSTGRES_PASSWORD
OPENAI_API_KEY=$KAMAL_OPENAI_API_KEY
VAPID_PUBLIC_KEY=$KAMAL_VAPID_PUBLIC_KEY
VAPID_PRIVATE_KEY=$KAMAL_VAPID_PRIVATE_KEY
VAPID_SUBJECT=$KAMAL_VAPID_SUBJECT
```

Add to `.gitignore` (Kamal generator already does this):
```
.kamal/secrets
```

- [ ] **Step 3: Dockerfile sanity check**

Rails 8 generates a working `Dockerfile`. Verify it exists; build locally to confirm:
```bash
docker build -t trend-radar-test .
```
Expected: build succeeds. Delete image: `docker rmi trend-radar-test`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: configure kamal deployment for single-VPS setup"
```

---

## Task 15: CI pipeline

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create CI workflow**

Create `.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready --health-interval 10s
          --health-timeout 5s --health-retries 5

    env:
      RAILS_ENV: test
      DATABASE_URL: postgres://postgres:postgres@localhost:5432
      OPENAI_API_KEY: dummy-for-vcr

    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: bin/rails db:create db:schema:load
      - run: bin/rspec
      - run: bin/vite build

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bundle exec rubocop || true  # soft-fail for MVP
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "ci: add github actions workflow for rspec + vite build"
```

---

## Task 16: Seed data for manual verification

See [`2026-04-17-plan-1-foundation/task-16-seeds.md`](2026-04-17-plan-1-foundation/task-16-seeds.md). Summary:

```ruby
if Rails.env.development?
  admin = User.find_or_create_by!(email: "admin@example.com") do |u|
    u.password = "password123"
    u.password_confirmation = "password123"
  end
  admin.update!(admin: true) unless admin.admin?

  user = User.find_or_create_by!(email: "dev@example.com") do |u|
    u.password = "password123"
    u.password_confirmation = "password123"
  end

  ai = Topic.find_or_create_by!(name: "AI agents") do |t|
    t.keywords = ["AI agent", "LLM agent", "agentic", "autonomous agent"]
    t.active = true
    t.created_by = admin
  end

  Topic.find_or_create_by!(name: "Rust") do |t|
    t.keywords = ["rust lang", "rustlang", "cargo"]
    t.active = true
    t.created_by = admin
  end

  TopicSubscription.find_or_create_by!(user: user, topic: ai) do |s|
    s.active = true
  end
end
```

Run `bin/rails db:seed`; commit.

---

## Task 17: Integration smoke — admin + subscription happy path (system test)

See [`2026-04-17-plan-1-foundation/task-17-system-test.md`](2026-04-17-plan-1-foundation/task-17-system-test.md). Summary:

- `spec/system/happy_path_spec.rb` drives `rack_test`:
  1. Admin signs in → `POST /admin/topics` creates a topic.
  2. Regular user signs in → `POST /topics/:topic_id/subscription` subscribes.
  3. If `Story`/`Match` are defined (Plan 2), seed a match and assert it appears on dashboard.
  4. `DELETE /topics/:topic_id/subscription` unsubscribes.

---

## Plan 1 Done — State of the Application

At the end of Plan 1 the app should:

- Boot locally (`bin/rails server` + `bin/vite dev`).
- Let a user sign up, log in, and sign out via Devise ERB views.
- Let an admin curate the shared `Topic` catalog at `/admin/topics` (CRUD minus destroy).
- Let regular users browse `/topics`, subscribe, set a per-subscription Discord webhook, pause, or unsubscribe.
- Gate `/admin/topics` behind `require_admin!` — non-admins redirected to root with an "Admins only." flash.
- Show an "Admin" nav link only when `current_user.admin`.
- Have SolidQueue installed and ready (no jobs yet).
- Have a Kamal config ready to deploy (IP/domain fill-in required).
- Pass `bin/rspec` (all model, request, system tests green).
- Pass CI on GitHub Actions.

Plan 2 picks up from here and adds the HN ingestion pipeline and matching logic.
