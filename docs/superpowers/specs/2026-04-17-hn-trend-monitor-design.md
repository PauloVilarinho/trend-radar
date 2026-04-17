# Trend Radar — HN Trend Monitor (MVP Design)

**Date:** 2026-04-17
**Status:** Design approved, awaiting implementation plan
**Scope:** MVP — Hacker News only. Twitter and Reddit are explicitly out of scope for this spec.

## Purpose

A multi-user web application that monitors Hacker News for stories matching user-defined topics, detects when those stories are gaining traction fast (velocity), and notifies subscribers via web push and per-topic Discord webhooks so editorial/social-media teams can post about trending tech topics quickly.

## Key Decisions

| Decision | Choice |
|---|---|
| Product shape | Multi-user web product |
| Data source (MVP) | Hacker News public API (free, no key) |
| Trend signal | Velocity rate check + keyword/topic match (combination) |
| Velocity model | Simple rate check (points/hour between snapshots) + poll young stories every 5 min, others every 30 min |
| Topic matching | Hybrid: keyword prefilter → OpenAI `gpt-4o-mini` classification |
| LLM provider | OpenAI |
| Notifications | In-app dashboard + Web Push + per-topic Discord webhooks |
| Stack | Rails 8 + Inertia + React, PostgreSQL, SolidQueue |
| Auth | Devise with plain ERB auth views; Inertia/React for the rest |
| Deployment | Kamal on a single VPS |

## MVP Scope

**In scope:**
1. User sign up / log in (Devise)
2. Subscribe to topics (freeform keyword lists, per-topic Discord webhook optional)
3. HN poller (every 30 min, young stories every 5 min)
4. Keyword prefilter → OpenAI classification → velocity check pipeline
5. In-app dashboard showing matched + climbing stories
6. Web push notifications (per-user opt-in)
7. Discord webhook notifications (per-topic)
8. "Mark as posted" / "Dismiss" actions on matches
9. History of past alerts (last 7 days)

**Explicitly out of scope for MVP:**
- Twitter / Reddit sources
- Admin / usage dashboard
- Billing / plans
- Mobile app / mobile push

## Architecture

Single Rails 8 app deployed to a single VPS via Kamal, running three process types against one PostgreSQL database:

```
┌──────────────────────────────────────────────────────────────────┐
│                      VPS (Kamal deploy)                          │
│                                                                  │
│  ┌────────────┐   ┌──────────────────┐   ┌────────────────┐      │
│  │  web       │   │  worker          │   │  scheduler     │      │
│  │  (Puma)    │   │  (SolidQueue)    │   │  (SolidQueue   │      │
│  │            │   │                  │   │   recurring)   │      │
│  │  Rails +   │   │  Runs:           │   │  Enqueues:     │      │
│  │  Inertia/  │   │  - FetchFeedsJob │   │  - every 5 min │      │
│  │  React +   │   │  - FetchStoryJob │   │    (young)     │      │
│  │  Devise    │   │  - MatchJob      │   │  - every 30 min│      │
│  │            │   │  - NotifyJob     │   │    (full top)  │      │
│  │            │   │  - PruneSnapshotsJob (daily)          │      │
│  └─────┬──────┘   └─────────┬────────┘   └────────┬───────┘      │
│        │                    │                     │              │
│        └────────────┬───────┴─────────────────────┘              │
│                     │                                            │
│              ┌──────▼────────┐                                   │
│              │  PostgreSQL   │ ← everything (app data +          │
│              │               │   SolidQueue jobs)                │
│              └───────────────┘                                   │
└──────────────────────────────────────────────────────────────────┘
        │                                     │
        ▼                                     ▼
  ┌─────────────────┐                  ┌──────────────┐
  │ Hacker News API │                  │ OpenAI API   │
  │ (HTTPS JSON)    │                  │ (gpt-4o-mini)│
  └─────────────────┘                  └──────────────┘

  Outbound notifications:
  - Web Push (VAPID) → user browsers
  - Discord webhooks → user-configured URLs
```

No Redis, no external job queue. SolidQueue uses Postgres.

## Data Model

### `users` (Devise standard)
Email, encrypted password, timestamps.

### `topics`
User-defined subscriptions.

| Column | Type | Notes |
|---|---|---|
| `user_id` | fk | belongs_to User |
| `name` | string | e.g., "AI agents" |
| `keywords` | text[] | Prefilter terms, ≥1, ≤20 |
| `discord_webhook` | string, encrypted, nullable | Per-topic webhook |
| `active` | boolean, default true | |
| timestamps | | |

Indexes: `(user_id, name)` unique.

Limits: ≤20 keywords per topic, ≤50 topics per user (validation).

### `stories`
One row per HN item we've seen.

| Column | Type | Notes |
|---|---|---|
| `hn_id` | bigint | unique |
| `title` | string | |
| `url` | string, nullable | null for Ask HN |
| `by` | string | author |
| `score` | int | latest score |
| `descendants` | int | comment count |
| `story_type` | string | story/ask/show/job |
| `text` | text, nullable | Ask HN body |
| `hn_created_at` | datetime | |
| `first_seen_at` | datetime | |
| `last_polled_at` | datetime | |
| `tracking_status` | enum: `active` \| `archived`, default `active` | |
| `archived_at` | datetime, nullable | |

Indexes: `hn_id` unique, `last_polled_at`, partial on `tracking_status WHERE status='active'`.

### `story_snapshots`
Time-series score/comments for velocity.

| Column | Type | Notes |
|---|---|---|
| `story_id` | fk | |
| `score` | int | |
| `descendants` | int | |
| `captured_at` | datetime | |

Indexes: `(story_id, captured_at)`.

Retention: pruned to last 7 days by `PruneSnapshotsJob`.

### `matches`
Junction of story × topic, produced when keyword prefilter + LLM confirm relevance.

| Column | Type | Notes |
|---|---|---|
| `story_id` | fk | |
| `topic_id` | fk | |
| `relevance_score` | decimal | LLM 0–1 |
| `reason` | text | "Why this matters" — becomes post starter |
| `velocity_score` | decimal | points/hour at match time |
| `matched_at` | datetime | |
| `dismissed_at` | datetime, nullable | User clicked Dismiss |
| `posted_at` | datetime, nullable | User clicked Mark as posted |

Indexes: `(story_id, topic_id)` unique; `(topic_id, matched_at DESC)` for dashboard queries.

### `notifications`
Audit log per delivery, idempotency guard.

| Column | Type | Notes |
|---|---|---|
| `match_id` | fk | |
| `channel` | enum: `web_push` \| `discord` | |
| `status` | enum: `pending` \| `sent` \| `failed` | |
| `sent_at` | datetime, nullable | |
| `error` | text, nullable | |

Indexes: `(match_id, channel)` unique — prevents double-send on retry.

### `push_subscriptions`
Per-browser Web Push endpoints.

| Column | Type | Notes |
|---|---|---|
| `user_id` | fk | |
| `endpoint` | string | |
| `p256dh_key` | string | |
| `auth_key` | string | |
| `user_agent` | string, nullable | for display |
| timestamps | | |

## Relationships

- `User` has_many `topics`, `push_subscriptions`
- `Topic` has_many `matches`
- `Story` has_many `story_snapshots`, `matches`
- `Match` has_many `notifications`

## Data Flow (Lifecycle of a Story)

Five pipeline stages. Each is its own job class for testability and retry isolation.

### Stage 1 — `FetchFeedsJob` (the poller)

SolidQueue recurring schedules:
- Every **5 min** → `/newstories.json` + `/topstories.json`
- Every **30 min** → additionally `/beststories.json`

Logic:
1. GET the feed(s), receive array of item IDs.
2. Diff against `stories.hn_id` — enqueue `FetchStoryJob` for any new IDs.
3. For existing stories that are "young" (age < 6 h) OR whose `last_polled_at` is stale relative to their schedule, enqueue `FetchStoryJob`.
4. Skip stories with `tracking_status = 'archived'`.

### Stage 2 — `FetchStoryJob(hn_id)`

1. GET `/item/{id}.json`.
2. Upsert into `stories`, update `last_polled_at`.
3. Insert a `story_snapshots` row (score + descendants + timestamp).
4. Compute rolling velocity from last 3 snapshots (`points_gained / elapsed_hours`).
5. Apply archival rules. Archive (set `tracking_status='archived'`, `archived_at=now`) if ANY of:
   - `age > 72h` (hard cutoff)
   - `age > 12h` AND last 3 rolling velocities all `< 3 pts/hr`
   - 3 consecutive snapshots with identical score and identical comment count
6. Decide if this story is a **match candidate**:
   - New story (first time) → always candidate
   - Existing story → candidate if velocity crosses threshold (MVP default: +15 points/hour with ≥30 total)
7. If candidate and not archived → enqueue `MatchJob(story_id)`.

### Stage 3 — `MatchJob(story_id)` — keyword prefilter + LLM

1. Load the story.
2. Query all active topics whose any `keywords` entry appears in `story.title` OR `story.url` OR `story.text` (case-insensitive, using Postgres array semantics + `ILIKE` with escaped literals).
3. For each matching topic **without an existing `Match` for this story**, call OpenAI:
   - Model: `gpt-4o-mini`
   - `response_format: json_object`
   - Prompt: topic name + keywords + story (title, URL, text snippet), asking for `{score: float 0-1, reason: string}`.
4. **Invalid JSON handling (inline retry loop):**
   - Parse the response; require both `score` and `reason` keys.
   - On parse failure or missing keys → retry up to 3 times with a corrective system message: "Your previous response was not valid JSON. Respond with ONLY a JSON object with keys 'score' and 'reason'."
   - After 3 retries, record `relevance_score=0`, do not create a Match, log the last raw response, move on.
5. If `score >= 0.6` (tunable) → insert `Match` row with `relevance_score`, `reason`, `velocity_score`.
6. For each new Match → enqueue `NotifyJob(match_id)`.

Cost-control soft guard: if today's classification count exceeds a configurable budget (default 500/day), stop enqueuing new MatchJobs and log a warning.

### Stage 4 — `NotifyJob(match_id)` — fan-out

1. Load the match + its topic + the topic's user.
2. For each enabled channel:
   - **Web push** → find user's `push_subscriptions`, send via `web-push` gem. One `notifications` row per subscription.
   - **Discord** → if `topic.discord_webhook` present, POST to it. One `notifications` row for the topic.
3. Idempotency guard: `(match_id, channel)` unique constraint prevents double-send on retry.
4. On failure: update notification `status=failed`, `error=...`. Log; do not refan.

### Stage 5 — User action (controller, no job)

- `POST /matches/:id/mark_posted` → sets `posted_at`
- `POST /matches/:id/dismiss` → sets `dismissed_at`
- Dashboard filters dismissed/posted out by default, with a "show all" toggle.

### Supporting: `PruneSnapshotsJob` (daily)

Delete `story_snapshots` where `captured_at < 7 days ago`.

### Supporting: `BackfillTopicJob(topic_id)`

When a user creates a new topic, run MatchJob logic against the last ~24 h of stories so the dashboard isn't empty on signup.

## Error Handling & Edge Cases

### HN API failures
- **Timeouts / 5xx:** SolidQueue retries with exponential backoff (5 attempts). Next scheduled poll naturally recovers missed IDs.
- **Deleted / dead stories:** HN returns `{"deleted": true}` / `{"dead": true}`. Skip; if already stored, archive.
- **Malformed JSON / schema drift:** rescue `JSON::ParserError`, skip missing required fields, log.
- **HN outage:** pipeline resumes on recovery. Velocity math uses actual `captured_at` timestamps, so gaps are handled.

### OpenAI failures
- **Rate limits (429):** SolidQueue retry with backoff.
- **Invalid JSON response:** inline retry loop (up to 3 attempts per call) with a corrective message; after 3 → treat as no match.
- **API outage:** jobs pile up and drain when API recovers. Dashboard stays live.
- **Cost runaway:** daily classification soft budget.

### Discord webhook failures
- **Bad URL / revoked:** 4xx → mark `notifications.status=failed`, do not retry. Surface on topic settings page.
- **Rate limit (429):** retry respecting `Retry-After`.
- **Discord outage:** retry a few times, then fail.

### Web Push failures
- **Expired / invalid subscription (404/410):** delete the `push_subscriptions` row.
- **VAPID keys:** stored in Rails credentials. Rotation invalidates all subs; users re-opt-in.

### Race conditions
- **Concurrent story fetch:** `hn_id` unique + `INSERT … ON CONFLICT DO UPDATE`.
- **Duplicate match:** `(story_id, topic_id)` unique; rescue `RecordNotUnique`.
- **Duplicate notification:** `(match_id, channel)` unique.

### User-input edge cases
- **Keyword with SQL special chars:** parameter-bound `ILIKE`, escape `%` and `_` as literals.
- **Limits:** ≤20 keywords per topic, ≤50 topics per user.
- **Discord webhook URL format:** validate format before saving.
- **Empty keyword list:** disallowed (validation requires ≥1).

### Deployment edge cases
- **First boot:** `FetchFeedsJob` discovers 500 top stories, enqueues 500 `FetchStoryJob`s, drains in minutes.
- **Scheduler restart mid-poll:** SolidQueue recurring schedules are idempotent per tick.
- **Clock skew:** velocity uses DB-stored `captured_at` deltas, not wall clock.

### Observability
- Structured logs per job: `story_hn_id`, `match_id`, `duration_ms`.
- `/health` endpoint on web process.
- Error reporting hooked to Sentry/Honeybadger (or Rails logs).

## Testing Strategy

**Stack:** RSpec + VCR + WebMock + Capybara (for one E2E).

### Unit tests
- `Topic` validations: keyword cap, topic cap, webhook URL format, ≥1 keyword.
- `Story.archive!` under each of the 3 archive conditions.
- `VelocityCalculator` service: rolling points/hour, edge cases (single snapshot → nil, gaps).
- `KeywordMatcher` service: case-insensitive, safe against SQL special chars, matches across title/url/text.

### Job tests (with stubs/mocks)
- `FetchFeedsJob`: WebMock HN feeds → correct IDs enqueued; archived stories skipped.
- `FetchStoryJob`: WebMock item endpoint → upsert + snapshot + archive decision + candidate detection.
- `MatchJob`: VCR-cassette OpenAI → (a) zero LLM calls when keyword prefilter fails, (b) LLM called per passing topic, (c) match only when `score ≥ 0.6`, (d) JSON retry loop up to 3× then graceful fail.
- `NotifyJob`: stub web-push gem + Discord webhook → idempotency verified, expired subscriptions deleted.

### Request specs
- Devise sign-up/login.
- Topic CRUD.
- Dashboard: correct Inertia props; dismiss/mark-posted endpoints.
- Web Push subscribe/unsubscribe endpoints.

### System test
- One Capybara + headless Chrome happy path: sign up → create topic → trigger fake matching story → dashboard shows match → mark as posted → removed from default view.

### External API handling
- VCR cassettes for OpenAI + HN, scrubbed of keys, committed to repo. No real external calls in CI.

### Manual verification (documented, not automated)
- Web Push in Chrome/Firefox/Safari.
- Discord webhook posting to a test channel.
- Archival thresholds against real HN data; tune in staging.

### Priority order for MVP test writing
1. Model validations
2. `MatchJob` with VCR (highest-risk path)
3. `FetchStoryJob` + archive decision
4. Dashboard request specs
5. Everything else fills in as edges are hit

## Configuration

`config/tracking.yml` (tunable without migration):
```yaml
velocity_candidate_threshold:
  points_per_hour: 15
  minimum_score: 30
archive:
  hard_cutoff_hours: 72
  cooling_age_hours: 12
  cooling_points_per_hour: 3
  flat_snapshots_required: 3
match:
  min_relevance_score: 0.6
  daily_classification_budget: 500
snapshot_retention_days: 7
```

Secrets (Rails credentials):
- `openai.api_key`
- `web_push.vapid_public_key`, `web_push.vapid_private_key`, `web_push.subject`

## Open Questions / Deferred

- Exact Devise configuration (confirmations? lockable?) — decide during implementation.
- Rate-limiting the web UI (per-user) — probably overkill for MVP, revisit if abused.
- Frontend styling system (Tailwind vs CSS modules vs other) — decide during implementation.
- Multi-source architecture for future Twitter/Reddit sources: the `stories` table is HN-specific today; when adding sources, introduce a `source` column and polymorphic adapter pattern. Out of scope now.
