# Performance & Security Gate — Design

**Date:** 2026-04-29
**Status:** Draft — awaiting review

## Purpose

Extend the existing `bin/rake quality` gate with performance and security checks so that LLM-generated code (and human-generated code) is automatically verified for two failure modes the current gate can't see: N+1 query patterns / allocation regressions, and static security flaws. The goal is the same as the existing quality gate — give Claude (and humans) a single command whose green output is evidence the change is safe to commit.

## Scope

### In scope

- Bullet wired into the RSpec suite to fail any spec that triggers an N+1 or unused-eager-loading pattern.
- Brakeman wired as a static-analysis step (`quality:brakeman`) producing a JSON warning report; gated on warnings count at medium+ confidence.
- A suite-wide allocation ratchet using `GC.stat(:total_allocated_objects)`, captured around the full spec run.
- A per-controller-action SQL query count ratchet, derived from `ActiveSupport::Notifications` subscriptions during specs. Detects route-specific regressions that suite-wide allocations and Bullet miss (e.g., a controller starts running 25 queries instead of 5 due to a non-N+1 pattern such as count-per-record loops or new `find_by` calls in services).
- Vernier installed as a development tool with a small wrapper script, so when the allocation gate fails the LLM can prompt the user to investigate.
- Threshold config in the existing `config/quality_thresholds.yml`.
- Updates to `quality:report` to surface the new rows.

### Out of scope (intentional)

- **Per-action wall-time gating.** Wall time is too noisy for a gate without median-of-N runs and a fixed environment. Vernier handles per-action wall-time investigation on-demand. Per-action *SQL count* is in scope (deterministic); per-action *time* is not.
- **External HTTP call counter.** The test suite uses WebMock which already raises on unstubbed external calls; a separate counter doesn't add signal.
- **Auto-running vernier.** The LLM surfaces regressions and prompts the user to run vernier; the gate itself never runs vernier. Keeps the gate fast and predictable.
- **CI workflow.** Same phase-two scope as the existing quality gate.
- **`memory_profiler`, `stackprof`, `benchmark-ips`.** Replaced by `GC.stat` (deterministic suite-wide signal, no gem dependency) and `vernier` (single fresh tool for diagnostic profiling).
- **Parallel-spec safety for the per-action subscriber.** Single-process RSpec only. If `parallel_tests` or similar is adopted later, the subscriber needs per-process JSON output and a merging parser; out of scope until then.

## Tool stack

| Concern | Tool | Last release |
|---|---|---|
| N+1 / unused eager loading | bullet 8.1.1 | 2026-04-23 |
| Static security analysis | brakeman 8.0.4 (already in Gemfile) | 2026-02-27 |
| Allocation regression (suite-wide) | `GC.stat` (Ruby stdlib) | always current |
| SQL queries per controller action | `ActiveSupport::Notifications` (Rails stdlib) | always current |
| Off-gate diagnostic profiler | vernier 1.10.0 | 2026-03-02 |

`GC.stat(:total_allocated_objects)` returns a deterministic integer counter of every object Ruby has allocated since process start. Wrapping a span of code with two reads gives an exact, reproducible allocation count — the strongest signal available for ratchet-based regression detection. No third-party dependency, no sampling noise.

`ActiveSupport::Notifications` is Rails' built-in instrumentation pipeline. Subscribing to `start_processing.action_controller`, `sql.active_record`, and `process_action.action_controller` lets us count exactly how many queries ran during each controller action that specs exercised — deterministic given the same fixtures and code path. Same regression-friendly properties as `GC.stat`.

## Architecture

Extend the existing `bin/rake quality` namespace; do not create a parallel namespace.

```
bin/rake quality
├── quality:coverage    (existing — extended) → enables Bullet,
│                                                writes allocations.json,
│                                                writes action_metrics.json
├── quality:rubocop     (existing)
├── quality:critic      (existing)
├── quality:flog        (existing)
├── quality:mutation    (existing)
├── quality:brakeman    (NEW)                 → tmp/quality/brakeman.json
└── quality:report      (existing — extended)
                          ├─ reads brakeman.json       — gates on warnings count
                          ├─ reads allocations.json    — gates on total_allocated_objects
                          └─ reads action_metrics.json — gates per-action SQL count
```

Bullet does not produce a JSON artifact. Its failure mode is raising during a spec, which fails `bin/rspec`, which fails `quality:coverage`, which fails the umbrella `quality` task. The report still surfaces a "Bullet (N+1)" row so a passing run is visibly accounted for.

### Files added

```
lib/quality/brakeman_parser.rb            # parses brakeman JSON into {warnings: N}
lib/quality/allocations_parser.rb         # reads allocations.json
lib/quality/action_metrics_parser.rb      # reads action_metrics.json
spec/support/bullet.rb                    # enables Bullet in test
spec/support/allocations.rb               # before/after :suite hook around GC.stat
spec/support/action_metrics.rb            # AS::Notifications subscribers + write hook
script/profile.rb                         # vernier wrapper for off-gate diagnostic
spec/lib/quality/brakeman_parser_spec.rb
spec/lib/quality/allocations_parser_spec.rb
spec/lib/quality/action_metrics_parser_spec.rb
docs/profiling.md                         # how to use vernier when the gate fails
```

### Files modified

- `Gemfile` / `Gemfile.lock` — add `bullet` (dev/test) and `vernier` (dev/test).
- `config/quality_thresholds.yml` — add `brakeman`, `allocations`, and `sql_per_action` sections.
- `lib/tasks/quality.rake` — add the `quality:brakeman` task, wire new parsers into `quality:report`, depend the new task in the umbrella `quality` task.
- `lib/quality/report.rb` — render new rows.
- `spec/spec_helper.rb` (or `spec/rails_helper.rb`) — require the new support files.
- `CLAUDE.md` — extend the existing quality-gate convention with the vernier prompt.

`MUTANT_SUBJECTS` does not need updating — the new parsers live under the existing `Quality*` glob.

## How each gate works

### Bullet (binary)

Configured in `spec/support/bullet.rb`:

```ruby
Bullet.enable      = true
Bullet.raise       = true
Bullet.bullet_logger = false
Bullet.console     = false

RSpec.configure do |config|
  config.before(:each) { Bullet.start_request }
  config.after(:each)  { Bullet.perform_out_of_channel_notifications if Bullet.notification?; Bullet.end_request }
end
```

Any N+1 detected raises `Bullet::Notification::UnoptimizedQueryError`, fails that spec, fails `bin/rspec`, fails `quality:coverage`. No threshold, no parser, no JSON artifact.

False positives (rare but real — counter caches read directly, polymorphic preloads Bullet doesn't recognize) are silenced via `Bullet.add_safelist` in the same file with a comment explaining each case.

### Brakeman (hard ratchet on warnings count)

New `quality:brakeman` task:

```bash
bundle exec brakeman --format json --confidence-level 2 --no-pager -o tmp/quality/brakeman.json
```

`--confidence-level 2` filters out low-confidence warnings (informational noise), gating only on medium and high. Brakeman exits non-zero when warnings exist; the rake task swallows that exit code (matching the pattern used for `rubocop` and `mutation`) so the gate is the report, not Brakeman's own exit code.

`Quality::BrakemanParser` extracts `{warnings: N}` from the JSON.

`config/quality_thresholds.yml` gains:

```yaml
brakeman:
  warnings_max: 0   # captured on first run; manual bump required to accept findings
```

First-run behaviour mirrors `mutation:kill_ratio_min` — observed value is written into the threshold file, exit zero, human commits.

**Tolerance: zero.** Any new medium+ warning fails the gate. To accept a finding, edit `warnings_max` deliberately. Unlike continuous metrics, security warnings are discrete findings tied to specific code locations — silently tolerating one risks shipping an SQL injection.

### Allocations (suite-wide ratchet, +15% tolerance)

`spec/support/allocations.rb`:

```ruby
RSpec.configure do |config|
  config.before(:suite) do
    @allocations_start = GC.stat(:total_allocated_objects)
  end

  config.after(:suite) do
    diff = GC.stat(:total_allocated_objects) - @allocations_start
    File.write(
      Rails.root.join("tmp/quality/allocations.json"),
      JSON.pretty_generate(total_allocated_objects: diff)
    )
  end
end
```

`Quality::AllocationsParser` reads the artifact.

`config/quality_thresholds.yml` gains:

```yaml
allocations:
  total_max: 1_400_000   # captured on first run
  tolerance_pct: 15
```

Gate passes if `observed <= total_max * (1 + tolerance_pct/100.0)`. The report shows the actual delta even when within tolerance, so drift is visible:

```
Allocations (total)       1.42M   ≤ 1.61M (+15%)     ✓  +1.4%
```

**On failure:**

```
Allocations (total)       1.65M   ≤ 1.61M (+15%)     ✗  +17.9%

  Allocations grew from 1.40M to 1.65M (+17.9%).
  Run `bin/ruby script/profile.rb '<your hot path>'` and open the
  resulting tmp/quality/vernier.json in https://profiler.firefox.com.
  See docs/profiling.md.
```

**No auto-update on improvement.** If observed drops below the baseline, the threshold stays put; capturing the improvement requires editing `total_max` deliberately. Matches the existing mutation-ratio pattern. The cost is one occasional explicit commit; the benefit is no implicit drift logic to reason about.

### SQL queries per controller action (ratchet, +25% or +3 queries)

Implemented via `ActiveSupport::Notifications` subscriptions in `spec/support/action_metrics.rb`. The mechanism:

- On `start_processing.action_controller` — reset a thread-local SQL counter to 0.
- On `sql.active_record` — increment the counter, skipping payloads with `name` of `SCHEMA`, `TRANSACTION`, or `CACHE` (Rails' internal queries).
- On `process_action.action_controller` — read the counter, take the max of `(observed, current_max)` for that `"#{controller}##{action}"`, store in an in-memory hash.

After the suite runs (`after(:suite)` hook), the hash is written to `tmp/quality/action_metrics.json`:

```json
{
  "DashboardController#index":   {"sql_count_max": 8},
  "TopicsController#index":      {"sql_count_max": 4},
  "MatchesController#dismiss":   {"sql_count_max": 3}
}
```

`Quality::ActionMetricsParser` reads it.

`config/quality_thresholds.yml` gains:

```yaml
sql_per_action:
  tolerance_pct: 25
  min_delta: 3
  baselines:
    DashboardController#index: 8
    TopicsController#index: 4
    MatchesController#dismiss: 3
```

Each action passes if `observed <= max(baseline * 1.25, baseline + 3)`. The `min_delta` floor (`+3` queries) handles small actions: an action with a baseline of 1 query has a percentage cap of `1 × 1.25 = 1.25` (effectively 1), but the floor allows up to `1 + 3 = 4` before failing. Without `min_delta`, every small action would be impossible to evolve.

**First-run / new-action behaviour.** If `sql_per_action.baselines` is missing entirely, capture all observed values, write them to the threshold file, exit zero (mirrors mutation ratchet). If `baselines` exists but is missing a specific action — newly added route, or first time exercised by a spec — auto-add it on the next run with the observed value. The diff is visible in the threshold file, so you see which actions are being tracked for the first time.

**Stale entries.** An action listed in `baselines` but not exercised by the current spec run is reported as `[stale]` in the report and is *not* gated. Removal is manual. The gate doesn't auto-prune, because if a request spec is inadvertently deleted the silent disappearance of its baseline would mask the problem.

**Threading model.** The thread-local SQL counter is safe under default RSpec (single-threaded). System specs running Capybara with a separate Rails server are an edge case — the controller runs in the server process, not the test process — and those queries don't get counted. Acceptable: per-action SQL counts are most meaningful from request specs anyway.

### Vernier (off-gate diagnostic)

`script/profile.rb`:

```ruby
#!/usr/bin/env ruby
require_relative "../config/environment"
require "vernier"

expression = ARGV.first or abort "Usage: bin/ruby script/profile.rb '<ruby expression>'"

out = Rails.root.join("tmp/quality/vernier.json").to_s
Vernier.profile(out: out) { eval(expression) }
puts "Wrote #{out}. Open it in https://profiler.firefox.com"
```

`docs/profiling.md` is a one-page guide: when to run the script, example expressions for hot paths in this app (e.g., `DashboardController.new.index`), how to load the JSON in firefox-profiler, what to look for in a flame graph.

When the allocation gate fails, the report tells the user to run this script. **Claude does not run vernier itself in the gate** — it surfaces the regression and prompts the user. Keeps the gate fast (vernier adds runtime), keeps the spec environment clean, and forces a human moment of "is this regression actually OK?" before the threshold gets bumped.

## Updated quality report

```
Quality gates
=============
Coverage (line)           96.2%   ≥ 95%              ✓
Coverage (branch)         91.4%   ≥ 90%              ✓
Flog max (method)         12      ≤ 20               ✓
Flog max (class)          38      ≤ 70               ✓
Class length max          87      ≤ 100              ✓
Method length max         9       ≤ 15               ✓
AbcSize max               13      ≤ 15               ✓
CyclomaticComplexity max  5       ≤ 6                ✓
Mutation kill ratio       92.1%   ≥ 69.46%           ✓
Bullet (N+1)              -       no spec failures   ✓
Brakeman warnings         0       ≤ 0                ✓  [ratcheted]
Allocations (total)       1.42M   ≤ 1.61M (+15%)     ✓  +1.4%
SQL queries per action (max delta, +25% or +3)
  DashboardController#index   8   ≤ 11               ✓  +0
  TopicsController#index      4   ≤ 7                ✓  +0
  MatchesController#dismiss   3   ≤ 6                ✓  +0

15/15 gates passed.

Detailed reports:
  tmp/quality/overview.html        (RubyCritic)
  coverage/index.html              (SimpleCov)
  tmp/quality/mutation.txt         (Mutant)
  tmp/quality/brakeman.json        (Brakeman)
```

(Total gate count is `12 + N` where N is the number of controller actions in `sql_per_action.baselines`. The example above shows 3 actions for 15 gates.)

On any failure: failing rows show `✗`, the summary line shows `M/N gates passed`, and the process exits 1. Stale per-action entries (in baselines but not exercised) appear as `[stale]` and don't count as failures.

## CLAUDE.md addition

Extend the existing quality-gate convention with one sentence about vernier. The current CLAUDE.md bullet:

> **Run the quality gate before committing.** Run `bin/rake quality` before declaring a task complete. Do not commit if any gate fails. Report the gate numbers in your response so regressions are visible. Thresholds live in `config/quality_thresholds.yml`.

Becomes:

> **Run the quality gate before committing.** Run `bin/rake quality` before declaring a task complete. Do not commit if any gate fails. Report the gate numbers in your response so regressions are visible. Thresholds live in `config/quality_thresholds.yml`. If the allocations gate fails, run `bin/ruby script/profile.rb '<expression>'` against the suspected hot path and share the vernier findings before raising the threshold.

## Testing strategy

- **`Quality::BrakemanParser`** tested against committed fixture JSON in `spec/fixtures/quality/`. Cases: zero warnings, one medium warning, one high warning, malformed JSON, missing file.
- **`Quality::AllocationsParser`** tested against committed fixture JSON. Cases: normal payload, missing file, malformed JSON.
- **`Quality::ActionMetricsParser`** tested against committed fixture JSON. Cases: normal multi-action payload, single action, empty hash, missing file, malformed JSON.
- **`Quality::Report`** gains spec coverage for: per-action gate pass within tolerance, per-action gate fail above tolerance, per-action gate pass via `min_delta` floor (small action), stale entry handling (in baselines, missing from observed), new entry handling (in observed, missing from baselines).
- **No spec for `script/profile.rb`** — it's a thin shell-out. We test that the file exists and is executable. Vernier has its own suite.
- **No spec for the `before(:suite)` allocation hook or the `ActiveSupport::Notifications` subscribers** — tested implicitly by running the suite (the artifacts must appear with sane contents).
- The new code itself must pass the existing aspirational gates (coverage, complexity, mutation). No exemptions.

## Rollout

Single phase:

1. Add `bullet` and `vernier` to Gemfile (dev/test groups). `bundle install`.
2. Configure Bullet in `spec/support/bullet.rb`. Run the suite; fix any N+1s flagged. The gate must be green the day it's introduced.
3. Wire allocation hook in `spec/support/allocations.rb`. Run the suite; capture the baseline into `quality_thresholds.yml`.
4. Wire per-action subscribers in `spec/support/action_metrics.rb`. Run the suite; capture per-action baselines into `quality_thresholds.yml` (`sql_per_action.baselines` populated automatically on first run, like the mutation ratchet).
5. Add the `quality:brakeman` task. Run it; capture the warnings-count baseline. If any medium+ warnings exist on `main`, fix them before merging — same "green from day one" rule.
6. Add `Quality::BrakemanParser`, `Quality::AllocationsParser`, `Quality::ActionMetricsParser`, and extend `Quality::Report` to render the new rows. Tests for the parsers and the new report logic.
7. Add `script/profile.rb` and `docs/profiling.md`.
8. Update CLAUDE.md.
9. Run `bin/rake quality` end-to-end. Confirm green.
10. Commit.

## Open questions / risks

- **Bullet false positives.** Some Rails patterns Bullet flags are intentional (counter caches read directly, certain polymorphic preloads). Mitigation: per-case `Bullet.add_safelist` with comments explaining each case. A growing safelist is a signal to revisit, not silently disable.
- **Allocation baseline drift.** Adding fixtures, factories, or test helpers inflates the baseline, requiring an explicit threshold bump. This is a known cost of the ratchet pattern, accepted because the alternative (auto-bumping) hides drift.
- **Brakeman JSON schema stability.** Brakeman's JSON output is stable but not contractually so. Parser fixtures pin the version we adopt; gem upgrades require re-checking the fixture.
- **Vernier `eval`-based wrapper.** `script/profile.rb` evaluates an arbitrary expression. Acceptable because the script is developer-only and never invoked by the gate, deploy, or any automated process. If we ever wire it into automation, the design changes.
- **Per-action gate depends on request-spec coverage.** A controller action without a request spec (or one that's never exercised by any spec) has no baseline and is invisible to the gate. The existing coverage gate catches the lack-of-spec problem; this gate just inherits whatever the coverage gate already enforces.
- **Per-action thresholds bloat the YAML.** Each controller action becomes a line in `quality_thresholds.yml`. For an app with dozens of routes the file grows. Acceptable for trend-radar's current size (~5 controllers); if it becomes unwieldy, a future change moves baselines to a separate `config/quality_baselines.yml` keyed by metric type.
- **System specs miss per-action SQL counting.** Capybara-driven system specs run controllers in a separate Rails server thread/process, so the `sql.active_record` events fire outside the test thread and aren't captured. Counts come from request specs only. Mitigation: trend-radar's per-action coverage relies on request specs anyway; if a route's only test is a system spec, it gets no per-action baseline. Documented behaviour, not a defect.
- **`min_delta = 3` is a guess.** It's chosen so an action with 1 query baseline can grow to 4 before failing. If this proves too loose (small actions can grow ~3× silently) or too tight, tune the value via the threshold file rather than the code.
