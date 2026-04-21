# Code Quality Metrics — Design

**Date:** 2026-04-21
**Status:** Draft — awaiting review

## Purpose

Instrument the codebase with the quality measurements Uncle Bob identifies as the right things to watch when humans stop reading AI-generated code line-by-line: test coverage, cyclomatic complexity, module sizes, and mutation testing. These gates become a baseline; future AI contributions are measured against them, and the result is the evidence for an upcoming blog post on AI code quality.

## Scope

### In scope

- A single rake command (`bin/rake quality`) that runs all four measurements and fails if any threshold is breached.
- Threshold configuration in `config/quality_thresholds.yml`.
- CLAUDE.md instruction so Claude runs the gate after every change.
- Aspirational thresholds for coverage, complexity, and module sizes (set up front, code cleaned up until green).
- Ratcheted threshold for mutation kill ratio (captured on first run; the rule is "don't get worse").

### Out of scope (intentional)

- **Dependency-structure analysis** (Packwerk, cycle detection, DIP checks). For a five-controller Rails monolith, package boundaries are architecture-theatre. This will be called out honestly in the blog post as "doesn't map cleanly onto idiomatic Rails."
- **CI gate / GitHub Actions workflow.** Phase two, once thresholds have settled. The rake task is the single source of truth; CI will just shell out to it when it's added.
- **Per-PR / changed-files diff mode for Mutant.** Added later only if full-app runtime grows painful.
- **Longitudinal history / database of past results.** Every run is fresh. If later we want graphs over time, that's a separate feature.
- **HTML dashboards** beyond the ones RubyCritic and SimpleCov emit for free.

## Tool Stack

| Uncle Bob's metric | Tool | Notes |
|---|---|---|
| Test coverage | SimpleCov | Line + branch coverage. Runs with the spec suite. |
| Cyclomatic complexity | Flog (via RubyCritic) + Rubocop `Metrics/CyclomaticComplexity` | Two angles: Flog for weighted ABC, Rubocop for classical cyclomatic. |
| Module sizes | Rubocop `Metrics/ClassLength`, `Metrics/MethodLength` | These cops are disabled in `rubocop-rails-omakase`; we re-enable them via `.rubocop.yml` override. |
| Mutation testing | Mutant (`mbj/mutant`) with RSpec integration | Targets `app/` only. |
| Dependency structure | *Skipped — see Out of Scope.* | — |

## Architecture

One rake namespace, four sub-tasks, one aggregator.

```
bin/rake quality
├── quality:coverage   → runs bin/rspec, reads coverage/.last_run.json   → tmp/quality/coverage.json
├── quality:critic     → rubycritic --format json --no-browser           → tmp/quality/critic.json
├── quality:rubocop    → rubocop --only Metrics --format json            → tmp/quality/rubocop.json
├── quality:mutation   → mutant run --use rspec --format json            → tmp/quality/mutation.json
└── quality:report     → reads all four JSON files, compares against
                         config/quality_thresholds.yml, prints summary
                         table, exits 0 (pass) or 1 (any gate failed)
```

### Design decisions

- **Sub-tasks are runnable individually.** When iterating on one dimension, you don't pay the cost of the others.
- **`quality:report` is the only task that reads thresholds.** Every other task just produces raw data.
- **Raw output under `tmp/quality/`**, not committed. Regenerated every run. Added to `.gitignore`.
- **Aggregator is a plain Ruby class** (`lib/quality/report.rb`, ~100 lines). No gem, no abstraction layer. Unit-testable in isolation.
- **SimpleCov is wired into the spec suite normally** (added in `spec/spec_helper.rb`), not invoked separately. `quality:coverage` is a thin shell-out wrapper around `bin/rspec` that reads the coverage artifact afterward.
- **Mutant configuration lives in `.mutant.yml`** — integration rspec, include `app/`, require `config/environment`.

### File layout introduced by this change

```
.mutant.yml                              # mutant config
.rubocop.yml                             # re-enable Metrics cops on top of omakase
config/quality_thresholds.yml            # thresholds (aspirational + ratcheted)
lib/quality/report.rb                    # aggregator class
lib/quality/rubocop_parser.rb            # thin parser per tool
lib/quality/critic_parser.rb
lib/quality/coverage_parser.rb
lib/quality/mutant_parser.rb
lib/tasks/quality.rake                   # the rake namespace
spec/lib/quality/report_spec.rb          # aggregator tests (fixture-driven)
spec/lib/quality/*_parser_spec.rb        # parser tests
tmp/quality/                             # .gitignored
```

## Thresholds

### Aspirational (fixed up front in `config/quality_thresholds.yml`)

| Metric | Threshold | Tool |
|---|---|---|
| Line coverage | ≥ 95% | SimpleCov |
| Branch coverage | ≥ 90% | SimpleCov |
| Max flog per method | ≤ 15 | RubyCritic (Flog) |
| Max flog per class | ≤ 40 | RubyCritic (Flog) |
| Max class length | ≤ 100 lines | Rubocop `Metrics/ClassLength` |
| Max method length | ≤ 10 lines | Rubocop `Metrics/MethodLength` |
| Max AbcSize | ≤ 15 | Rubocop `Metrics/AbcSize` |
| Max CyclomaticComplexity | ≤ 6 | Rubocop `Metrics/CyclomaticComplexity` |

If current code fails any of these, the cleanup happens as part of implementation — the gate must be green the day it's introduced.

### Ratcheted (captured automatically on first run)

| Metric | Threshold | Tool |
|---|---|---|
| Mutation kill ratio | ≥ *N* (first-run value) | Mutant |

**First-run behaviour:** if `quality_thresholds.yml` has no `mutation.kill_ratio_min` set, `quality:mutation` writes the observed ratio into the file and exits zero. The human then commits the file; that value is the floor from then on. Subsequent runs fail if the ratio drops below the recorded floor.

## Report Format

Console output of `bin/rake quality`:

```
Quality gates
=============
Coverage (line)           96.2%   ≥ 95%        ✓
Coverage (branch)         91.4%   ≥ 90%        ✓
Flog max (method)         12      ≤ 15         ✓
Flog max (class)          38      ≤ 40         ✓
Class length max          87      ≤ 100        ✓
Method length max         9       ≤ 10         ✓
AbcSize max               13      ≤ 15         ✓
CyclomaticComplexity max  5       ≤ 6          ✓
Mutation kill ratio       92.1%   ≥ 92.1%      ✓  [ratcheted]

9/9 gates passed.

Detailed reports:
  tmp/quality/critic.html        (RubyCritic)
  coverage/index.html            (SimpleCov)
  tmp/quality/mutation.json      (Mutant)
```

On any failure: the failing rows are marked `✗`, the summary line shows `N/9 gates passed`, and the process exits 1.

## CLAUDE.md Addition

One bullet added to the existing conventions list (kept minimal per project preference):

> **Run the quality gate after every change.** Run `bin/rake quality` alongside `bin/rspec` and `bundle exec rubocop`. Do not claim a task complete if any gate fails. Report the numbers so regressions are visible.

## Mutant Specifics

- **Config file:** `.mutant.yml`
  - `integration: rspec`
  - `includes: [app]`
  - `requires: [./config/environment]`
- **Target scope:** `app/models/**/*.rb`, `app/services/**/*.rb`, `app/controllers/**/*.rb`, `app/jobs/**/*.rb`.
- **Expected runtime:** low-single-digit minutes on the current codebase.
- **Escape hatch (future, not built now):** if runtime becomes painful, swap `quality:mutation` to target only files changed vs `main` via `git diff --name-only`.

## Testing Strategy

- **Parser classes** (`lib/quality/*_parser.rb`) are tested against committed fixture JSON under `spec/fixtures/quality/`. No shelling out; pure data in, pure data out.
- **Aggregator** (`lib/quality/report.rb`) is tested with synthesized parser results and a fake `quality_thresholds.yml`. Covers: all green, one failure, ratcheted-gate-not-yet-set, all failures.
- **No integration tests** that actually shell out to RubyCritic / Mutant. Those tools have their own suites; we only test our integration surface (parsing + threshold comparison).
- The aggregator itself must pass its own thresholds — no special exemption.

## Rollout

Single phase for this design:

1. Add gems (dev/test: `simplecov`, `rubycritic`, `mutant-rspec`).
2. Enable Rubocop Metrics cops.
3. Write parsers + aggregator + rake task.
4. Run `bin/rake quality` once. Clean up any code that fails aspirational gates.
5. Run once more with Mutant; record the ratchet value.
6. Add the CLAUDE.md bullet.
7. Commit.

**Later (explicitly out of scope here):** a phase-two change adds a GitHub Actions workflow that calls the same rake task. A phase-three change, if needed, adds diff-scoped Mutant.

## Open Questions / Risks

- **Mutant runtime unknown.** If the first run exceeds ~10 minutes, we drop it from the default `quality` task and expose it as `bin/rake quality:mutation` only, with a note in CLAUDE.md that it's a separate pre-commit step. Decided at implementation time based on actual numbers.
- **RubyCritic JSON format.** The tool's JSON output schema isn't perfectly stable across versions. The parser spec pins a fixture from the version we adopt; a gem upgrade means re-checking the fixture.
- **Branch coverage on Ruby 3.x.** SimpleCov branch coverage has had rough edges historically. If branch coverage reporting is unreliable, we drop that threshold and keep line coverage only. Decided at implementation time.
- **Rubocop cop re-enabling may conflict with omakase.** The override file must be careful not to broadly un-tune omakase; it should only re-enable the specific Metrics cops we gate on.
