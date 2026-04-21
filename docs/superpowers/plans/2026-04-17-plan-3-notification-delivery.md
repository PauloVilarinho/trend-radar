# Trend Radar — Plan 3: Notification Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**2026-04-20 amendment:** `NotifyJob` now fans out per `TopicSubscription` (not per topic owner). The `notifications` table gains `target_type` + `target_id`; uniqueness is `(match_id, channel, target_type, target_id)`. The "last Discord failure" banner moves from `pages/topics/edit.tsx` (which no longer exists for regular users) to the inline subscription form on `pages/topics/index.tsx`.

**Goal:** Deliver matches to subscribers via two fast channels — browser Web Push and per-subscription Discord webhooks — with idempotency, failure logging, and failure surfacing on the topics catalog page. Completes the MVP.

**Architecture:** `NotifyJob` loads a `Match` + its topic + all active `topic_subscriptions`, then for each subscriber dispatches one delivery per push_subscription (Web Push) and one delivery per subscription (Discord, if `discord_webhook` is present). Each send creates a `notifications` row for idempotency and audit. Failed Discord deliveries surface on the subscription's row in `pages/topics/index.tsx`. The frontend ships a service worker and a "Enable notifications" UI in the dashboard to capture `PushSubscription` objects.

**Tech Stack:** `web-push` gem (Ruby), VAPID keys, browser Service Worker API, Faraday (for Discord POSTs — already added in Plan 2), RSpec + WebMock.

---

## File Structure

New files in this plan:

| File | Purpose |
|---|---|
| `app/services/discord/webhook_client.rb` | Discord webhook POST |
| `app/services/web_push/sender.rb` | Wrap `web-push` gem |
| `app/controllers/push_subscriptions_controller.rb` | Subscribe/unsubscribe endpoints |
| `app/frontend/service-worker.ts` | Browser service worker for push |
| `app/frontend/lib/push.ts` | Browser helpers: subscribe, unsubscribe |
| `app/frontend/components/PushToggle.tsx` | Dashboard UI for enabling push |
| `app/views/layouts/application.html.erb` | Modify: register SW |
| `config/initializers/web_push.rb` | VAPID config |
| `app/jobs/notify_job.rb` | Implement (stub in Plan 2) |
| `spec/services/discord/webhook_client_spec.rb` | Discord client tests |
| `spec/services/web_push/sender_spec.rb` | Web push sender tests |
| `spec/jobs/notify_job_spec.rb` | Fan-out tests |
| `spec/requests/push_subscriptions_spec.rb` | Subscribe/unsubscribe tests |

Files modified:

| File | Change |
|---|---|
| `app/controllers/topics_controller.rb` | Expose each subscription's last Discord failure in the catalog index props |
| `app/frontend/pages/topics/index.tsx` | Show last Discord failure banner inline above each subscription form |
| `app/frontend/pages/dashboard/index.tsx` | Add PushToggle |
| `app/controllers/application_controller.rb` | Shared props include VAPID public key |

---

## Task 1: Add web-push gem + VAPID config

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/web_push.rb`
- Create: `lib/tasks/vapid.rake`

- [ ] **Step 1: Add gem**

Append to `Gemfile`:
```ruby
gem "web-push"
```

Run: `bundle install`.

- [ ] **Step 2: Rake task to generate VAPID keypair**

Create `lib/tasks/vapid.rake`:
```ruby
namespace :vapid do
  desc "Generate a VAPID keypair and print it. Store in Rails credentials."
  task generate: :environment do
    vapid_key = WebPush.generate_key
    puts "VAPID_PUBLIC_KEY=#{vapid_key.public_key}"
    puts "VAPID_PRIVATE_KEY=#{vapid_key.private_key}"
    puts
    puts "Add to Rails credentials under 'web_push:' namespace."
  end
end
```

- [ ] **Step 3: Generate keys for development**

Run: `bin/rails vapid:generate`
Copy the output. Edit credentials:
```bash
EDITOR=vim bin/rails credentials:edit
```
Add:
```yaml
web_push:
  vapid_public_key: <paste public>
  vapid_private_key: <paste private>
  vapid_subject: mailto:dev@example.com
```

- [ ] **Step 4: Initializer**

Create `config/initializers/web_push.rb`:
```ruby
Rails.application.configure do
  config.x.web_push = ActiveSupport::OrderedOptions.new.tap do |cfg|
    cfg.public_key  = ENV["VAPID_PUBLIC_KEY"]  || Rails.application.credentials.dig(:web_push, :vapid_public_key)
    cfg.private_key = ENV["VAPID_PRIVATE_KEY"] || Rails.application.credentials.dig(:web_push, :vapid_private_key)
    cfg.subject     = ENV["VAPID_SUBJECT"]     || Rails.application.credentials.dig(:web_push, :vapid_subject) || "mailto:admin@example.com"
  end
end
```

- [ ] **Step 5: Expose public key to frontend via shared Inertia props**

Edit `app/controllers/application_controller.rb`, extend `inertia_share` (the `admin` key was added in Plan 1 Task 7b):
```ruby
  inertia_share do
    {
      current_user: current_user && {
        id: current_user.id,
        email: current_user.email,
        admin: current_user.admin,
      },
      flash: { notice: flash[:notice], alert: flash[:alert] }.compact,
      vapid_public_key: Rails.configuration.x.web_push.public_key,
    }
  end
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: add web-push gem, VAPID keys, and rake task"
```

---

## Task 2: PushSubscriptionsController — subscribe/unsubscribe

**Files:**
- Create: `app/controllers/push_subscriptions_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/push_subscriptions_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/requests/push_subscriptions_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "PushSubscriptions", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  let(:sub_params) do
    {
      endpoint: "https://fcm.googleapis.com/fcm/send/abc",
      keys: { p256dh: "p256dh-sample", auth: "auth-sample" },
      user_agent: "Mozilla/5.0"
    }
  end

  describe "POST /push_subscriptions" do
    it "creates a subscription" do
      expect {
        post "/push_subscriptions", params: sub_params, as: :json
      }.to change(PushSubscription, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "is idempotent for the same endpoint" do
      post "/push_subscriptions", params: sub_params, as: :json
      expect {
        post "/push_subscriptions", params: sub_params, as: :json
      }.not_to change(PushSubscription, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /push_subscriptions" do
    it "removes a subscription by endpoint" do
      create(:push_subscription, user: user, endpoint: sub_params[:endpoint])
      expect {
        delete "/push_subscriptions", params: { endpoint: sub_params[:endpoint] }, as: :json
      }.to change(PushSubscription, :count).by(-1)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/requests/push_subscriptions_spec.rb`

- [ ] **Step 3: Routes**

Edit `config/routes.rb`, add inside `draw do`:
```ruby
  resource :push_subscriptions, only: [:create, :destroy]
```

(Note: singular `resource`, will give `POST /push_subscriptions` and `DELETE /push_subscriptions`.)

- [ ] **Step 4: Controller**

Create `app/controllers/push_subscriptions_controller.rb`:
```ruby
class PushSubscriptionsController < ApplicationController
  skip_forgery_protection only: [:create, :destroy]

  def create
    sub = current_user.push_subscriptions.find_or_initialize_by(endpoint: params[:endpoint])
    was_new = sub.new_record?

    sub.assign_attributes(
      p256dh_key: params.dig(:keys, :p256dh),
      auth_key:   params.dig(:keys, :auth),
      user_agent: params[:user_agent]
    )

    if sub.save
      render json: { ok: true }, status: (was_new ? :created : :ok)
    else
      render json: { errors: sub.errors }, status: :unprocessable_content
    end
  end

  def destroy
    current_user.push_subscriptions.where(endpoint: params[:endpoint]).destroy_all
    head :no_content
  end
end
```

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rspec spec/requests/push_subscriptions_spec.rb`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add push subscriptions controller (create/destroy)"
```

---

## Task 3: Service worker + browser subscribe flow

**Files:**
- Create: `app/frontend/service-worker.ts`
- Create: `app/frontend/lib/push.ts`
- Create: `app/frontend/components/PushToggle.tsx`
- Modify: `vite.config.ts` (ensure SW is built as a standalone asset)
- Modify: `app/views/layouts/application.html.erb` (register SW)
- Modify: `app/frontend/pages/dashboard/index.tsx`

- [ ] **Step 1: Service worker**

Create `app/frontend/service-worker.ts`:
```ts
/// <reference lib="webworker" />
declare const self: ServiceWorkerGlobalScope;

self.addEventListener("push", (event: PushEvent) => {
  const payload = event.data?.json() ?? {};
  const title = payload.title || "Trend Radar";
  const body = payload.body || "New match";
  const url = payload.url || "/";

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      data: { url },
      badge: "/icon.png",
      icon: "/icon.png",
    })
  );
});

self.addEventListener("notificationclick", (event: NotificationEvent) => {
  event.notification.close();
  const url = event.notification.data?.url || "/";
  event.waitUntil(self.clients.openWindow(url));
});

export {};
```

- [ ] **Step 2: Vite config — build SW as separate entrypoint**

Edit `vite.config.ts`. Add `service-worker.ts` to inputs:
```ts
import { defineConfig } from "vite";
import RubyPlugin from "vite-plugin-ruby";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [RubyPlugin(), react()],
  build: {
    rollupOptions: {
      input: {
        application: "app/frontend/entrypoints/application.tsx",
        "service-worker": "app/frontend/service-worker.ts",
      },
    },
  },
});
```

And register the SW in `config/vite.json` entrypoints (vite-plugin-ruby convention):
```json
{
  "all": {
    "sourceCodeDir": "app/frontend",
    "watchAdditionalPaths": []
  },
  "development": {
    "autoBuild": true,
    "publicOutputDir": "vite-dev",
    "port": 3036
  },
  "test": {
    "autoBuild": true,
    "publicOutputDir": "vite-test",
    "port": 3037
  }
}
```

(vite_rails uses `app/frontend/entrypoints/` as the default; the service-worker needs to be in entrypoints to be served. Move it.)

Actually, simpler: move `service-worker.ts` into `app/frontend/entrypoints/`:
```bash
git mv app/frontend/service-worker.ts app/frontend/entrypoints/service-worker.ts
```

Remove the explicit rollupOptions override — vite-plugin-ruby handles entrypoints automatically. Revert `vite.config.ts` to the generator default.

- [ ] **Step 3: Push helpers**

Create `app/frontend/lib/push.ts`:
```ts
function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padding = "=".repeat((4 - (base64.length % 4)) % 4);
  const base64Safe = (base64 + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64Safe);
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)));
}

export async function isPushSupported(): Promise<boolean> {
  return "serviceWorker" in navigator && "PushManager" in window;
}

export async function getExistingSubscription(): Promise<PushSubscription | null> {
  if (!(await isPushSupported())) return null;
  const reg = await navigator.serviceWorker.ready;
  return reg.pushManager.getSubscription();
}

export async function subscribe(vapidPublicKey: string): Promise<PushSubscription> {
  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
  });

  const subJson = sub.toJSON();
  await fetch("/push_subscriptions", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
    credentials: "same-origin",
    body: JSON.stringify({
      endpoint: subJson.endpoint,
      keys: subJson.keys,
      user_agent: navigator.userAgent,
    }),
  });

  return sub;
}

export async function unsubscribe(): Promise<void> {
  const sub = await getExistingSubscription();
  if (!sub) return;

  await fetch("/push_subscriptions", {
    method: "DELETE",
    headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
    credentials: "same-origin",
    body: JSON.stringify({ endpoint: sub.endpoint }),
  });

  await sub.unsubscribe();
}

function csrfToken(): string {
  const meta = document.querySelector<HTMLMetaElement>("meta[name=csrf-token]");
  return meta?.content || "";
}
```

- [ ] **Step 4: PushToggle component**

Create `app/frontend/components/PushToggle.tsx`:
```tsx
import { useEffect, useState } from "react";
import { usePage } from "@inertiajs/react";
import { getExistingSubscription, isPushSupported, subscribe, unsubscribe } from "../lib/push";

export default function PushToggle() {
  const { vapid_public_key } = usePage<{ vapid_public_key: string }>().props;
  const [supported, setSupported] = useState(false);
  const [enabled, setEnabled] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    (async () => {
      const ok = await isPushSupported();
      setSupported(ok);
      if (ok) {
        const existing = await getExistingSubscription();
        setEnabled(Boolean(existing));
      }
    })();
  }, []);

  if (!supported) {
    return <div className="text-xs text-gray-500">Push notifications not supported by this browser.</div>;
  }

  const toggle = async () => {
    setBusy(true);
    try {
      if (enabled) {
        await unsubscribe();
        setEnabled(false);
      } else {
        const perm = await Notification.requestPermission();
        if (perm !== "granted") {
          alert("Notification permission denied.");
          return;
        }
        await subscribe(vapid_public_key);
        setEnabled(true);
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <button
      onClick={toggle}
      disabled={busy}
      className={`text-xs px-2 py-1 rounded ${enabled ? "bg-green-100 text-green-800" : "bg-gray-200 text-gray-700"}`}
    >
      {busy ? "…" : enabled ? "Push notifications ON" : "Enable push notifications"}
    </button>
  );
}
```

- [ ] **Step 5: Add PushToggle to Dashboard**

Edit `app/frontend/pages/dashboard/index.tsx`, add at top of the returned JSX (before the `<h1>`):
```tsx
import PushToggle from "../../components/PushToggle";
// ... existing imports

// inside component return, before h1:
<div className="flex justify-end mb-2">
  <PushToggle />
</div>
```

- [ ] **Step 6: Register service worker in Rails layout**

Edit `app/views/layouts/application.html.erb`. Inside `<head>`, add:
```erb
<script>
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("<%= vite_asset_path 'entrypoints/service-worker.ts' %>", { scope: "/" })
      .catch(err => console.warn("SW registration failed", err));
  }
</script>
```

- [ ] **Step 7: Manual browser check**

Run: `bin/rails server` + `bin/vite dev`. Visit dashboard. Click **Enable push notifications**. Accept OS permission prompt. Expect:
- `PushSubscription.count` == 1 (Rails console).
- Service worker visible in Chrome DevTools → Application → Service Workers.
- Toggle flips to "ON".
- Clicking again unsubscribes; DB row deleted.

Stop servers.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add service worker, push subscribe UI, and vapid public key prop"
```

---

## Task 4: Web Push sender service

**Files:**
- Create: `app/services/web_push/sender.rb`
- Create: `spec/services/web_push/sender_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/services/web_push/sender_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe WebPush::Sender do
  let(:user) { create(:user) }
  let(:subscription) { create(:push_subscription, user: user, endpoint: "https://push.example/x") }

  let(:payload) { { title: "hi", body: "match", url: "/" }.to_json }

  describe "#deliver" do
    it "returns :sent on success" do
      expect(::WebPush).to receive(:payload_send).and_return(Net::HTTPCreated.new("1.1", "201", "Created"))

      result = described_class.new.deliver(subscription: subscription, payload: payload)

      expect(result).to eq(:sent)
    end

    it "deletes the subscription and returns :expired on 404" do
      error = ::WebPush::ExpiredSubscription.new(double(code: "404", message: "Not Found"), "https://push.example/x")
      expect(::WebPush).to receive(:payload_send).and_raise(error)

      result = described_class.new.deliver(subscription: subscription, payload: payload)

      expect(result).to eq(:expired)
      expect(PushSubscription.find_by(id: subscription.id)).to be_nil
    end

    it "returns :failed on other errors" do
      expect(::WebPush).to receive(:payload_send).and_raise(::WebPush::Error.new("boom"))

      result = described_class.new.deliver(subscription: subscription, payload: payload)

      expect(result).to eq(:failed)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/services/web_push/sender_spec.rb`

- [ ] **Step 3: Implement**

Create `app/services/web_push/sender.rb`:
```ruby
module WebPush
  class Sender
    def deliver(subscription:, payload:)
      ::WebPush.payload_send(
        message: payload,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh_key,
        auth: subscription.auth_key,
        vapid: {
          subject: Rails.configuration.x.web_push.subject,
          public_key: Rails.configuration.x.web_push.public_key,
          private_key: Rails.configuration.x.web_push.private_key,
        }
      )
      :sent
    rescue ::WebPush::ExpiredSubscription, ::WebPush::InvalidSubscription
      subscription.destroy
      :expired
    rescue ::WebPush::Error, StandardError => e
      Rails.logger.warn("[WebPush::Sender] #{e.class}: #{e.message}")
      :failed
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rspec spec/services/web_push/sender_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add WebPush::Sender service with expiration handling"
```

---

## Task 5: Discord webhook client

**Files:**
- Create: `app/services/discord/webhook_client.rb`
- Create: `spec/services/discord/webhook_client_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/services/discord/webhook_client_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Discord::WebhookClient do
  let(:url) { "https://discord.com/api/webhooks/123/abc" }
  let(:payload) { { content: "Hello" } }

  describe "#deliver" do
    it "returns :sent on 2xx" do
      stub_request(:post, url).with(body: payload.to_json).to_return(status: 204)

      result = described_class.new.deliver(url: url, payload: payload)
      expect(result).to eq([:sent, nil])
    end

    it "returns :failed with body on 4xx" do
      stub_request(:post, url).to_return(status: 400, body: '{"message":"bad"}')

      result = described_class.new.deliver(url: url, payload: payload)
      expect(result[0]).to eq(:failed)
      expect(result[1]).to include("bad")
    end

    it "retries on 429 respecting Retry-After header" do
      stub_request(:post, url)
        .to_return({ status: 429, headers: { "Retry-After" => "0" }, body: "rate limited" },
                   { status: 204 })

      result = described_class.new.deliver(url: url, payload: payload)
      expect(result).to eq([:sent, nil])
    end

    it "returns :failed after max retries on persistent 429" do
      stub_request(:post, url).to_return(status: 429, headers: { "Retry-After" => "0" }, body: "rate limited")

      result = described_class.new.deliver(url: url, payload: payload)
      expect(result[0]).to eq(:failed)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/services/discord/webhook_client_spec.rb`

- [ ] **Step 3: Implement**

Create `app/services/discord/webhook_client.rb`:
```ruby
module Discord
  class WebhookClient
    MAX_429_RETRIES = 3

    def deliver(url:, payload:, connection: default_connection)
      attempts = 0

      begin
        response = connection.post(url, payload.to_json, "Content-Type" => "application/json")

        return [:sent, nil] if response.success?

        if response.status == 429 && attempts < MAX_429_RETRIES
          attempts += 1
          retry_after = response.headers["Retry-After"].to_f
          sleep(retry_after.clamp(0.0, 5.0))
          raise Retry
        end

        [:failed, "HTTP #{response.status}: #{response.body.to_s[0, 200]}"]
      rescue Retry
        retry
      rescue Faraday::Error => e
        [:failed, e.message]
      end
    end

    private

    class Retry < StandardError; end

    def default_connection
      Faraday.new do |f|
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rspec spec/services/discord/webhook_client_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Discord::WebhookClient with 429 retry"
```

---

## Task 6: NotifyJob — fan out to web push + discord

**Files:**
- Modify: `app/jobs/notify_job.rb`
- Create: `spec/jobs/notify_job_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/jobs/notify_job_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe NotifyJob, type: :job do
  let(:topic) { create(:topic) }
  let(:match) { create(:match, topic: topic) }

  describe "with no subscribers" do
    it "creates no notification rows" do
      expect { NotifyJob.new.perform(match.id) }.not_to change(Notification, :count)
    end
  end

  describe "with a subscribed user who has a push subscription" do
    let(:user) { create(:user) }
    let!(:subscription) { create(:topic_subscription, user: user, topic: topic) }
    let!(:push_sub) { create(:push_subscription, user: user) }
    let(:sender) { instance_double(WebPush::Sender) }

    before do
      allow(WebPush::Sender).to receive(:new).and_return(sender)
      allow(sender).to receive(:deliver).and_return(:sent)
    end

    it "creates one web_push notification targeting the push_subscription" do
      NotifyJob.new.perform(match.id)

      notif = Notification.find_by(match: match, channel: "web_push",
                                   target_type: "PushSubscription", target_id: push_sub.id)
      expect(notif.status).to eq("sent")
      expect(sender).to have_received(:deliver).once
    end

    it "fans out to every push subscription the user has" do
      extra = create(:push_subscription, user: user)

      NotifyJob.new.perform(match.id)

      expect(Notification.where(match: match, channel: "web_push").count).to eq(2)
      expect(sender).to have_received(:deliver).twice
    end

    it "skips paused subscriptions" do
      subscription.update!(active: false)

      NotifyJob.new.perform(match.id)

      expect(Notification.where(match: match)).to be_empty
      expect(sender).not_to have_received(:deliver)
    end

    it "records failure when sender returns :failed" do
      allow(sender).to receive(:deliver).and_return(:failed)

      NotifyJob.new.perform(match.id)

      expect(Notification.find_by(match: match, channel: "web_push",
                                  target_id: push_sub.id).status).to eq("failed")
    end

    it "is idempotent on rerun (unique on match/channel/target)" do
      NotifyJob.new.perform(match.id)
      expect { NotifyJob.new.perform(match.id) }.not_to change(Notification, :count)
    end
  end

  describe "fan-out across multiple subscribers" do
    let!(:subscriber_a) { create(:user) }
    let!(:subscriber_b) { create(:user) }
    let!(:sub_a) { create(:topic_subscription, user: subscriber_a, topic: topic) }
    let!(:sub_b) { create(:topic_subscription, user: subscriber_b, topic: topic) }
    let!(:push_a) { create(:push_subscription, user: subscriber_a) }
    let!(:push_b) { create(:push_subscription, user: subscriber_b) }

    before do
      sender = instance_double(WebPush::Sender)
      allow(WebPush::Sender).to receive(:new).and_return(sender)
      allow(sender).to receive(:deliver).and_return(:sent)
    end

    it "creates one web_push notification per push subscription" do
      NotifyJob.new.perform(match.id)

      targets = Notification.where(match: match, channel: "web_push").pluck(:target_id)
      expect(targets).to contain_exactly(push_a.id, push_b.id)
    end
  end

  describe "with a Discord webhook on the subscription" do
    let(:user) { create(:user) }
    let!(:subscription) do
      create(:topic_subscription,
             user: user, topic: topic,
             discord_webhook: "https://discord.com/api/webhooks/1/abc")
    end
    let(:client) { instance_double(Discord::WebhookClient) }

    before { allow(Discord::WebhookClient).to receive(:new).and_return(client) }

    it "calls Discord client and records notification keyed on the subscription" do
      allow(client).to receive(:deliver).and_return([:sent, nil])

      NotifyJob.new.perform(match.id)

      notif = Notification.find_by(match: match, channel: "discord",
                                   target_type: "TopicSubscription", target_id: subscription.id)
      expect(notif.status).to eq("sent")
    end

    it "records failure with error text" do
      allow(client).to receive(:deliver).and_return([:failed, "HTTP 400: bad"])

      NotifyJob.new.perform(match.id)

      notif = Notification.find_by(match: match, channel: "discord",
                                   target_id: subscription.id)
      expect(notif.status).to eq("failed")
      expect(notif.error).to include("HTTP 400")
    end

    it "skips Discord when subscription has no webhook" do
      subscription.update!(discord_webhook: nil)

      NotifyJob.new.perform(match.id)

      expect(Notification.where(match: match, channel: "discord")).to be_empty
      expect(Discord::WebhookClient).not_to have_received(:new)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/jobs/notify_job_spec.rb`

- [ ] **Step 3: Implement**

Replace `app/jobs/notify_job.rb`:
```ruby
class NotifyJob < ApplicationJob
  queue_as :default

  def perform(match_id)
    match = Match.includes(:story, topic: { topic_subscriptions: { user: :push_subscriptions } })
                 .find(match_id)

    match.topic.topic_subscriptions.where(active: true).each do |subscription|
      deliver_web_push(match, subscription)
      deliver_discord(match, subscription) if subscription.discord_webhook.present?
    end
  end

  private

  def deliver_web_push(match, subscription)
    sender = WebPush::Sender.new

    subscription.user.push_subscriptions.each do |push_sub|
      next if Notification.exists?(match_id: match.id, channel: "web_push",
                                   target_type: "PushSubscription", target_id: push_sub.id)

      result = sender.deliver(subscription: push_sub, payload: web_push_payload(match))
      create_notification(match, "web_push", result.to_s, target: push_sub)
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end

  def deliver_discord(match, subscription)
    return if Notification.exists?(match_id: match.id, channel: "discord",
                                   target_type: "TopicSubscription", target_id: subscription.id)

    client = Discord::WebhookClient.new
    status, error = client.deliver(url: subscription.discord_webhook, payload: discord_payload(match))

    create_notification(match, "discord", status.to_s, target: subscription, error: error)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def create_notification(match, channel, status, target:, error: nil)
    normalized = (status == "sent" ? "sent" : "failed")
    Notification.create!(
      match: match,
      channel: channel,
      target: target,
      status: normalized,
      sent_at: (normalized == "sent" ? Time.current : nil),
      error: error
    )
  end

  def web_push_payload(match)
    {
      title: "#{match.topic.name}: #{match.story.title.to_s[0, 80]}",
      body: match.reason.to_s[0, 140],
      url: match.story.url || "https://news.ycombinator.com/item?id=#{match.story.hn_id}",
    }.to_json
  end

  def discord_payload(match)
    hn_url = "https://news.ycombinator.com/item?id=#{match.story.hn_id}"
    lines = [
      "**#{match.topic.name}** — climbing (#{match.velocity_score&.round(1)} pts/hr)",
      "**#{match.story.title}**",
      match.reason.to_s,
      "<#{match.story.url || hn_url}>",
      "HN: <#{hn_url}>",
    ]
    { content: lines.compact.join("\n") }
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rspec spec/jobs/notify_job_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: implement NotifyJob fan-out to web push + discord"
```

---

## Task 7: Surface Discord delivery failures on the topics catalog index

**Files:**
- Modify: `app/controllers/topics_controller.rb`
- Modify: `app/frontend/pages/topics/index.tsx`
- Modify: `spec/requests/topics_spec.rb`

> **2026-04-20 amendment:** the banner was previously on `pages/topics/edit.tsx`, which no longer exists for regular users. It now lives inline above each subscribed topic's form on `pages/topics/index.tsx`. Failure lookup is keyed on the `topic_subscription` id via `notifications.target_type/target_id`.

- [ ] **Step 1: Extend spec**

Append to `spec/requests/topics_spec.rb` inside the `GET /topics` authenticated block:
```ruby
    it "exposes last_discord_failure per subscription when a recent delivery failed" do
      topic = create(:topic, name: "K8s")
      subscription = create(:topic_subscription, user: user, topic: topic,
                            discord_webhook: "https://discord.com/api/webhooks/1/a")
      match = create(:match, topic: topic)
      create(:notification, match: match, channel: "discord", status: "failed",
             target: subscription, error: "HTTP 400: invalid webhook")

      get "/topics"
      expect(response.body).to include("HTTP 400: invalid webhook")
    end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/requests/topics_spec.rb`

- [ ] **Step 3: Controller — include failure in each topic's subscription props**

Edit `app/controllers/topics_controller.rb#index` to attach `last_discord_failure` to each subscription prop. One query per request is fine — a single `Notification.joins(:match)` grouped by `target_id`:
```ruby
  def index
    topics = Topic.active.order(:name)
    subs_by_topic = current_user.topic_subscriptions.index_by(&:topic_id)
    failures_by_sub = last_discord_failures_by_subscription_id(subs_by_topic.values)

    render inertia: "topics/index", props: {
      topics: topics.map { |t| topic_props(t, subs_by_topic[t.id], failures_by_sub) }
    }
  end

  private

  def topic_props(topic, subscription, failures_by_sub)
    {
      id: topic.id,
      name: topic.name,
      keywords: topic.keywords,
      subscription: subscription && {
        id: subscription.id,
        active: subscription.active,
        discord_webhook: subscription.discord_webhook || "",
        last_discord_failure: failures_by_sub[subscription.id],
      },
    }
  end

  def last_discord_failures_by_subscription_id(subscriptions)
    return {} if subscriptions.empty?

    rows = Notification
           .where(channel: "discord", status: "failed",
                  target_type: "TopicSubscription", target_id: subscriptions.map(&:id))
           .order(created_at: :desc)
           .pluck(:target_id, :error, :created_at)

    rows.each_with_object({}) do |(sub_id, error, at), acc|
      acc[sub_id] ||= { error: error, at: at.iso8601 }
    end
  end
```

- [ ] **Step 4: Update the index page**

Edit `app/frontend/pages/topics/index.tsx`. Extend the `Subscription` type and the inline `SubscriptionForm` to render the banner:
```tsx
type Subscription = {
  id: number;
  active: boolean;
  discord_webhook: string;
  last_discord_failure: { error: string; at: string } | null;
};

// inside SubscriptionForm, at the top of the returned form:
{subscription.last_discord_failure && (
  <div className="mb-2 bg-red-50 border border-red-200 text-red-800 text-xs p-2 rounded">
    <strong>Discord delivery failed</strong> (
    {new Date(subscription.last_discord_failure.at).toLocaleString()}):{" "}
    {subscription.last_discord_failure.error}
  </div>
)}
```

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rspec spec/requests/topics_spec.rb`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: surface last Discord failure on topics catalog subscription row"
```

---

## Task 8: Hook NotifyJob from MatchJob — already done in Plan 2

**Files:** none (sanity check)

- [ ] **Step 1: Verify wiring**

Read `app/jobs/match_job.rb` — confirm that after creating a `Match`, it calls `NotifyJob.perform_later(match.id)`. (This was written in Plan 2 Task 11.)

- [ ] **Step 2: Run the full suite**

Run: `bin/rspec`
Expected: all specs PASS. No commit needed unless issues.

---

## Task 9: End-to-end manual verification

**Files:** none (manual)

- [ ] **Step 1: Prepare a test Discord webhook**

In a Discord server you control, create a test channel, go to channel settings → Integrations → Webhooks → New Webhook → Copy URL.

- [ ] **Step 2: Start everything locally**

```bash
bin/rails db:reset db:seed
bin/rails server
bin/vite dev
bin/jobs start --recurring-schedule-file=config/recurring.yml
```

- [ ] **Step 3: Exercise the flow**

1. Log in as `dev@example.com` / `password123`.
2. On dashboard, click **Enable push notifications**, accept the browser prompt.
3. Go to `/topics`; in the inline subscription form for one of the seeded topics, paste the Discord webhook URL into the "Discord webhook" field and save.
4. Wait for HN polls + matches. (Shortcut to force a match: in `bin/rails console` run `MatchJob.perform_now(Story.active.first.id)` after manually editing the story title to contain a keyword, and setting up velocity.)
5. When a match appears:
   - Expect a browser notification banner.
   - Expect a Discord message in your test channel.
6. In `bin/rails console`, check `Notification.last(5).map { |n| [n.channel, n.status] }` — both should show `[_, "sent"]`.

- [ ] **Step 4: Test failure surfacing**

1. On `/topics`, change the subscription's Discord webhook to a fake URL: `https://discord.com/api/webhooks/999999999999/invalidinvalid`. Save.
2. Trigger another match (console: `NotifyJob.perform_now(Match.last.id)` using a recent match).
3. Visit `/topics` — expect the red "Discord delivery failed" banner above that subscription's form.

- [ ] **Step 5: Test push expiration**

1. In Chrome DevTools → Application → Service Workers → Unregister.
2. Trigger another NotifyJob.
3. Expect: the sender marks it expired and the `PushSubscription` row is deleted (`PushSubscription.count` decreases).

- [ ] **Step 6: Final suite check**

Run: `bin/rspec`
Expected: all green.

- [ ] **Step 7: Final commit (tag as v0.1.0)**

```bash
git tag -a v0.1.0 -m "MVP: HN trend monitor with web push + discord notifications"
```

---

## Plan 3 Done — MVP Complete

At the end of Plan 3:

- Users can enable browser push notifications from the dashboard (captures a `PushSubscription` row).
- `NotifyJob` fans out one delivery per active subscriber: Web Push to every `push_subscription` the subscriber owns, and Discord to the subscription's webhook if present.
- Expired push subscriptions auto-delete.
- Discord webhook failures (404, 4xx, persistent 429) are logged to `notifications.status=failed` with the error text, and surfaced on the subscription's row in `/topics`.
- Every delivery attempt is idempotent via the `(match_id, channel, target_type, target_id)` unique index.
- Full test suite passes.
- Manual verification: browser notifications show up, Discord messages arrive.

## Ready for Deployment

- Fill in `config/deploy.yml` placeholders (`<YOUR_VPS_IP>`, `<YOUR_DOMAIN>`, `<YOUR_GITHUB_USERNAME>`).
- Set production secrets (`OPENAI_API_KEY`, VAPID keys, Postgres password, Rails master key) into `.kamal/secrets`.
- `kamal setup` on first deploy, `kamal deploy` thereafter.
- After deploy, confirm `bin/jobs` is running on the scheduler server (recurring.yml loaded).

## Suggested Post-MVP Backlog (not in scope)

- Twitter and Reddit source adapters (rename `stories.source` column and add polymorphic adapters).
- Admin/usage dashboard.
- Billing.
- Smarter velocity (percentile-based) per spec Section "Alternatives considered."
- Per-user rate limits on topic creation.
- Email digest as an additional channel.
