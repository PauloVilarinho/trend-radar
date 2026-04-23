# Security & Performance Standards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two independent rake gates — `bin/rake security` and `bin/rake performance` — that fail on any new security finding or perf regression. Security runs Brakeman and bundler-audit with a zero-tolerance policy. Performance runs Bullet (raising on N+1), records per-endpoint latency medians, and measures memory growth + object allocations via derailed_benchmarks, comparing every metric against a committed baseline with per-metric tolerance.

**Architecture:** Mirrors the existing `lib/tasks/quality.rake` pattern. Each namespace has data-producing subtasks that write JSON into `tmp/quality/`, plus a `:report` subtask that loads the artifacts, compares them to thresholds/baseline, prints a pass/fail table, and exits non-zero on failure. Parsers + report classes live under `lib/security/` and `lib/performance/`, each unit-tested with hand-crafted fixtures — no shelling out in specs.

**Tech Stack:** Ruby 3.x / Rails 8, RSpec, Brakeman, bundler-audit, Bullet, derailed_benchmarks, memory_profiler.

**Important project conventions:**
- **Commits:** Omit any `Co-Authored-By:` trailer — the git hook rejects commits that add one.
- **No auto-commit during plan execution:** pause before each `git commit` step and ask for approval.
- **Lint + test after every change:** `bin/rspec` and `bundle exec rubocop` must both be green before considering a task complete — project convention from `CLAUDE.md`.
- **`MUTANT_SUBJECTS`:** When new top-level constants are introduced (`Security*`, `Performance*`), append them to `MUTANT_SUBJECTS` in `lib/tasks/quality.rake`. Otherwise mutation testing silently excludes the new code.

**Scope decisions (agreed up front):**
- Two separate rake tasks; no meta `bin/rake check`.
- Security gate is strict: zero Brakeman warnings, zero bundler-audit advisories. No ignore file on day one.
- bundler-audit refreshes its advisory DB on every run (requires network).
- Bullet raises on **N+1 only**; unused eager-load and counter_cache notifications are logged and surfaced as a warning count, not a hard fail.
- Performance baseline lives at `config/performance_baseline.yml` (committed). Rebaselining is explicit (`bin/rake performance:rebaseline`).
- Tolerances: latency 20%, memory 10%, allocations 5%. Default sample size for latency = 5 runs, take the median.
- `:perf`-tagged request specs are the coverage set. Initial endpoints: `DashboardController#index`, `TopicsController#index`, `TopicsController#show`, `TopicSubscriptionsController#create`. **No admin endpoints.**
- Representative endpoint for derailed memory/allocations: `/dashboard`.
- Gate runs locally only. No CI wiring, no git hook.

---

## Task 1: Add gems and run `bundle install`

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gems to the `:development, :test` group in `Gemfile`**

  Add next to the existing `brakeman` line:

  ```ruby
  gem "bundler-audit", require: false
  gem "bullet"
  gem "derailed_benchmarks", require: false
  gem "memory_profiler", require: false
  ```

- [ ] **Step 2: Run `bundle install`**

  Expected: clean resolve. If `bullet` conflicts with another gem on Rails 8, pin the newest released version that supports Rails 8 and document the pin in the commit message.

- [ ] **Step 3: Commit**

  Message: `chore(deps): add bullet, bundler-audit, derailed_benchmarks for security + performance gates`

---

## Task 2: Wire Bullet into test and development

**Files:**
- Modify: `config/environments/test.rb`
- Modify: `config/environments/development.rb`
- Modify: `spec/rails_helper.rb` (or `spec/spec_helper.rb`, whichever enables the test env for request specs)
- Create: `config/initializers/bullet.rb` (only if the notification routing below needs it — otherwise inline in the env files)

- [ ] **Step 1: Enable Bullet in the test environment**

  In `config/environments/test.rb`, inside the `Rails.application.configure do ... end` block:

  ```ruby
  config.after_initialize do
    Bullet.enable = true
    Bullet.bullet_logger = true
    Bullet.raise = true # see Step 3 for why this is safe
    Bullet.n_plus_one_query_enable = true
    Bullet.unused_eager_loading_enable = true
    Bullet.counter_cache_enable = true
  end
  ```

- [ ] **Step 2: Enable Bullet in the development environment (observability only, no raise)**

  ```ruby
  config.after_initialize do
    Bullet.enable = true
    Bullet.alert = true
    Bullet.console = true
    Bullet.rails_logger = true
    Bullet.n_plus_one_query_enable = true
    Bullet.unused_eager_loading_enable = true
    Bullet.counter_cache_enable = true
  end
  ```

- [ ] **Step 3: Implement "raise on N+1 only" filtering**

  Bullet's `raise` flag is global. To get N+1 raising while the other two categories stay warn-only, monkey-patch `Bullet.add_notification` (or the equivalent current-API hook) so that non-N+1 notifications are routed only to the logger, never to the raise path. Put the patch in `config/initializers/bullet.rb`, guarded by `if Rails.env.test?`.

  Before writing the patch, read Bullet's current source to identify the exact method that dispatches notifications — the API has changed across versions. If the split cannot be implemented cleanly, fall back to `Bullet.raise = true` for all categories and document the decision in the commit message.

  Parser / report plumbing in later tasks must read `log/bullet.log` to count unused eager-load + counter_cache findings.

- [ ] **Step 4: Run the full suite under Bullet and fix any N+1s it surfaces**

  ```bash
  bin/rspec
  ```

  Any `Bullet::Notification::UnoptimizedQueryError` (or equivalent) is a real N+1 and must be fixed (add `includes`, `preload`, or `eager_load` at the call site — do not suppress in Bullet's whitelist). If the suite explodes with many findings, triage in a separate commit per controller.

- [ ] **Step 5: Commit**

  Message: `chore(bullet): enable Bullet in test + dev; raise on N+1 only`

---

## Task 3: `security:brakeman` subtask

**Files:**
- Create: `lib/tasks/security.rake`
- Create: `lib/security/brakeman_parser.rb`
- Create: `spec/lib/security/brakeman_parser_spec.rb`

- [ ] **Step 1: Implement `Security::BrakemanParser`**

  Takes a path to `tmp/quality/brakeman.json`, reads `warnings` and `errors` arrays from the JSON, exposes `#warning_count`, `#error_count`, `#warnings` (for the report), `#passed?` (true iff both counts are zero).

- [ ] **Step 2: Write parser specs**

  Fixtures under `spec/fixtures/brakeman/`: one with zero findings (pass), one with a sample SQLi warning (fail), one with a scan error (fail). Assert on count methods and `#passed?`.

- [ ] **Step 3: Define `security:brakeman` rake task**

  In `lib/tasks/security.rake`:

  ```ruby
  namespace :security do
    desc "Run Brakeman; fail on any warning or scan error"
    task :brakeman do
      FileUtils.mkdir_p(QUALITY_DIR) # reuse QUALITY_DIR from quality.rake
      sh "bundle exec brakeman --format json --output #{QUALITY_DIR.join('brakeman.json')} --quiet --no-progress || true"
    end
  end
  ```

  Brakeman exits non-zero when findings exist. We suppress its exit and let `security:report` be the gate.

- [ ] **Step 4: Run tests + rubocop**

  ```bash
  bin/rspec spec/lib/security/brakeman_parser_spec.rb
  bundle exec rubocop lib/security/brakeman_parser.rb lib/tasks/security.rake
  ```

- [ ] **Step 5: Commit**

  Message: `feat(security): add brakeman subtask and parser`

---

## Task 4: `security:bundler_audit` subtask

**Files:**
- Modify: `lib/tasks/security.rake`
- Create: `lib/security/bundler_audit_parser.rb`
- Create: `spec/lib/security/bundler_audit_parser_spec.rb`

- [ ] **Step 1: Implement `Security::BundlerAuditParser`**

  bundler-audit's `--format json` output lists advisories under a `results` or `vulnerabilities` key (verify against the installed version). Parser exposes `#advisory_count`, `#advisories`, `#passed?` (true iff `advisory_count.zero?`).

- [ ] **Step 2: Write parser specs**

  Fixtures under `spec/fixtures/bundler_audit/`: one with zero advisories, one with a sample CVE against an unused gem.

- [ ] **Step 3: Define `security:bundler_audit` rake task**

  ```ruby
  namespace :security do
    desc "Update advisory DB and audit the bundle; fail on any advisory"
    task :bundler_audit do
      FileUtils.mkdir_p(QUALITY_DIR)
      sh "bundle exec bundle-audit update"
      out = %x(bundle exec bundle-audit check --format json)
      File.write(QUALITY_DIR.join("bundler_audit.json"), out)
    end
  end
  ```

  If the installed `bundler-audit` version does not support `--format json`, fall back to parsing the text output and document the fallback in the commit message.

- [ ] **Step 4: Run tests + rubocop**

- [ ] **Step 5: Commit**

  Message: `feat(security): add bundler-audit subtask and parser`

---

## Task 5: `security:report` + top-level `security` task

**Files:**
- Modify: `lib/tasks/security.rake`
- Create: `lib/security/report.rb`
- Create: `spec/lib/security/report_spec.rb`

- [ ] **Step 1: Implement `Security::Report`**

  Takes `{ brakeman: BrakemanParser, bundler_audit: BundlerAuditParser }`, exposes `#passed?`, implements `#to_s` with a two-row pass/fail table in the same style as `Quality::Report`.

- [ ] **Step 2: Write report specs**

  Assert pass/fail combinations and the rendered table shape.

- [ ] **Step 3: Define `security:report` and top-level `security` task**

  ```ruby
  namespace :security do
    desc "Aggregate security findings; exit 1 on any"
    task :report do
      report = Security::Report.new(
        brakeman: Security::BrakemanParser.new(QUALITY_DIR.join("brakeman.json")).parse,
        bundler_audit: Security::BundlerAuditParser.new(QUALITY_DIR.join("bundler_audit.json")).parse
      )
      puts report
      exit(report.passed? ? 0 : 1)
    end
  end

  desc "Run all security gates: brakeman, bundler_audit, report"
  task security: %w[security:brakeman security:bundler_audit security:report]
  ```

- [ ] **Step 4: Run the gate end-to-end**

  ```bash
  bin/rake security
  ```

  Any findings must be fixed before this task can land — the gate is strict-zero and we're not committing with a failing baseline.

- [ ] **Step 5: Add `Security*` to `MUTANT_SUBJECTS`**

  In `lib/tasks/quality.rake`, append `"Security*"` to the `MUTANT_SUBJECTS` array.

- [ ] **Step 6: Commit**

  Message: `feat(security): add security:report and wire bin/rake security`

---

## Task 6: Tag `:perf` request specs

**Files:**
- Modify: `spec/requests/dashboard_spec.rb` (or equivalent)
- Modify: `spec/requests/topics_spec.rb`
- Modify: `spec/requests/topic_subscriptions_spec.rb`

- [ ] **Step 1: Add `:perf` tags to the chosen examples**

  For each of the four target endpoints, pick the existing happy-path example (or add one if missing) and tag it:

  ```ruby
  it "renders", :perf do
    ...
  end
  ```

  Targets:
  - `GET /dashboard` (DashboardController#index)
  - `GET /topics` (TopicsController#index)
  - `GET /topics/:id` (TopicsController#show)
  - `POST /topic_subscriptions` (TopicSubscriptionsController#create)

- [ ] **Step 2: Verify specs still pass**

  ```bash
  bin/rspec --tag perf
  ```

- [ ] **Step 3: Commit**

  Message: `test(requests): tag critical endpoints with :perf`

---

## Task 7: Latency recorder + `performance:latency` subtask

**Files:**
- Create: `lib/tasks/performance.rake`
- Create: `lib/performance/latency_recorder.rb`
- Create: `lib/performance/latency_parser.rb`
- Create: `config/performance_thresholds.yml`
- Create: `spec/lib/performance/latency_recorder_spec.rb`
- Create: `spec/lib/performance/latency_parser_spec.rb`

- [ ] **Step 1: Create `config/performance_thresholds.yml`**

  ```yaml
  ---
  latency:
    sample_size: 5
    tolerance_pct: 20
  memory:
    tolerance_pct: 10
    target_url: /dashboard
  allocations:
    tolerance_pct: 5
    target_url: /dashboard
  ```

- [ ] **Step 2: Implement `Performance::LatencyRecorder`**

  A custom RSpec formatter (or `around(:each, :perf)` hook — pick the cleaner option after prototyping). For each `:perf`-tagged example, run the example body `sample_size` times, record wall-clock duration per run, emit the median into `tmp/quality/latency.json` keyed by a stable example identifier (`description` + file location). Use `Process.clock_gettime(Process::CLOCK_MONOTONIC)`.

- [ ] **Step 3: Implement `Performance::LatencyParser`**

  Reads `tmp/quality/latency.json`, returns `{ endpoint_key => median_ms }`.

- [ ] **Step 4: Write specs for recorder + parser**

  Recorder spec: stub out timing, verify median calculation over N samples. Parser spec: fixture JSON, assert shape.

- [ ] **Step 5: Define `performance:latency` rake task**

  Runs `bin/rspec --tag perf` with the recorder wired in; produces `tmp/quality/latency.json`.

- [ ] **Step 6: Run tests + rubocop**

- [ ] **Step 7: Commit**

  Message: `feat(performance): record per-endpoint latency medians for :perf specs`

---

## Task 8: `performance:memory` via derailed `perf:mem_over_time`

**Files:**
- Modify: `lib/tasks/performance.rake`
- Create: `lib/performance/memory_parser.rb`
- Create: `spec/lib/performance/memory_parser_spec.rb`
- Modify: `Rakefile` or create a dedicated `lib/tasks/derailed.rake` shim if derailed needs rake plumbing

- [ ] **Step 1: Wire derailed_benchmarks**

  derailed requires `require "derailed_benchmarks"` + `require "derailed_benchmarks/tasks"` in a rake file, plus an ENV-configurable `PATH_TO_HIT` (defaults to `/`). Set it to the value from `config/performance_thresholds.yml` (`memory.target_url`). Follow the derailed_benchmarks README for the latest wiring pattern.

- [ ] **Step 2: Implement `Performance::MemoryParser`**

  `derailed exec perf:mem_over_time` prints a sequence of RSS values to stdout. Parse the final RSS minus initial RSS as `rss_growth_mb`. Expose `#to_json` writing `{ target_url:, rss_growth_mb: }` to `tmp/quality/memory.json`.

- [ ] **Step 3: Write parser specs**

  Fixture stdout capture, assert on growth calculation.

- [ ] **Step 4: Define `performance:memory` rake task**

  Shells out to `bundle exec derailed exec perf:mem_over_time`, captures stdout, hands to parser, writes JSON.

- [ ] **Step 5: Run tests + rubocop + a one-off `bin/rake performance:memory`** to verify end-to-end.

- [ ] **Step 6: Commit**

  Message: `feat(performance): track per-request memory growth via derailed`

---

## Task 9: `performance:allocations` via derailed `perf:objects`

**Files:**
- Modify: `lib/tasks/performance.rake`
- Create: `lib/performance/allocations_parser.rb`
- Create: `spec/lib/performance/allocations_parser_spec.rb`

- [ ] **Step 1: Implement `Performance::AllocationsParser`**

  Parses the memory_profiler report printed by `derailed exec perf:objects`. Extract `total_allocated_objects`; write `{ target_url:, allocations: }` to `tmp/quality/allocations.json`.

- [ ] **Step 2: Write parser specs**

  Fixture stdout of a sample memory_profiler report.

- [ ] **Step 3: Define `performance:allocations` rake task**

- [ ] **Step 4: Run tests + rubocop + a one-off `bin/rake performance:allocations`** to verify end-to-end.

- [ ] **Step 5: Commit**

  Message: `feat(performance): track per-request object allocations via derailed`

---

## Task 10: `performance:report`, `performance:rebaseline`, top-level `performance` task

**Files:**
- Modify: `lib/tasks/performance.rake`
- Create: `lib/performance/report.rb`
- Create: `lib/performance/bullet_parser.rb`
- Create: `spec/lib/performance/report_spec.rb`
- Create: `spec/lib/performance/bullet_parser_spec.rb`

- [ ] **Step 1: Implement `Performance::BulletParser`**

  Reads `log/bullet.log` produced during the `:perf` spec run, aggregates counts of unused-eager-loading + counter-cache findings (N+1s already raised and failed the spec — we never reach this parser if any exist). Writes `tmp/quality/bullet.json`.

- [ ] **Step 2: Implement `Performance::Report`**

  Takes measurements (latency medians, memory growth, allocations, bullet warn counts) + baseline (`config/performance_baseline.yml`) + thresholds. For each endpoint/metric, pass if `measured <= baseline * (1 + tolerance_pct/100)`. Bullet warn counts: pass if count == baseline count (no regression). Render a pass/fail table.

- [ ] **Step 3: Write report specs**

  Cover: no baseline file (first run — pass with a clear "no baseline, run performance:rebaseline" note), in-tolerance regression, out-of-tolerance regression, per-metric failures.

- [ ] **Step 4: Define `performance:report`, `performance:rebaseline`, and top-level `performance` task**

  ```ruby
  namespace :performance do
    desc "Aggregate perf measurements; compare against baseline; exit 1 on regression"
    task :report do
      # load measurements from tmp/quality/
      # load baseline from config/performance_baseline.yml
      # load thresholds from config/performance_thresholds.yml
      # build Performance::Report, print, exit status
    end

    desc "Overwrite config/performance_baseline.yml with the latest measurements"
    task :rebaseline do
      # load measurements from tmp/quality/
      # write config/performance_baseline.yml
    end
  end

  desc "Run all performance gates: bullet (via tagged specs), latency, memory, allocations, report"
  task performance: %w[performance:latency performance:memory performance:allocations performance:report]
  ```

  Note: `performance:latency` runs the `:perf`-tagged specs with Bullet enabled, so Bullet's N+1 raise happens in that step. The `performance:bullet` parser step runs inside `performance:report` by reading `log/bullet.log`.

- [ ] **Step 5: Run tests + rubocop**

- [ ] **Step 6: Commit**

  Message: `feat(performance): add performance:report and wire bin/rake performance`

---

## Task 11: Generate and commit the initial baseline

**Files:**
- Create: `config/performance_baseline.yml`

- [ ] **Step 1: Run the measurement tasks**

  ```bash
  bin/rake performance:latency
  bin/rake performance:memory
  bin/rake performance:allocations
  bin/rake performance:rebaseline
  ```

- [ ] **Step 2: Inspect `config/performance_baseline.yml`**

  Sanity-check that numbers look reasonable (no sub-millisecond latencies, no zero-byte memory growth). If anything is obviously wrong, re-run. Baseline is what we'll compare against forever, so it's worth a second look.

- [ ] **Step 3: Run the full gate to confirm it passes against the freshly-written baseline**

  ```bash
  bin/rake performance
  ```

  Expected: all green.

- [ ] **Step 4: Add `Performance*` to `MUTANT_SUBJECTS`**

  In `lib/tasks/quality.rake`, append `"Performance*"`.

- [ ] **Step 5: Commit**

  Message: `chore(performance): capture initial baseline for :perf endpoints`

---

## Task 12: Update `CLAUDE.md` to document the new gates

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add a section describing `bin/rake security` and `bin/rake performance`**

  Cover: when to run each, how to rebaseline perf, zero-tolerance security policy, and the `:perf` tagging convention for request specs.

- [ ] **Step 2: Commit**

  Message: `docs(claude): document security and performance gates`

---

## Task 13: Final verification

- [ ] **Step 1: Run every gate back-to-back**

  ```bash
  bin/rake quality
  bin/rake security
  bin/rake performance
  ```

  All three must exit 0. Report the numbers from each in the PR description so regressions against this baseline are visible in later PRs.
