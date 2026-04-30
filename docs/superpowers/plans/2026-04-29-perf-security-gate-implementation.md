# Performance & Security Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four new gates to `bin/rake quality` so that LLM-generated (and human-generated) code is automatically verified against four runtime/static failure modes the existing gate misses: static security flaws (Brakeman), N+1 query patterns (Bullet), suite-wide allocation regressions (`GC.stat`), and per-controller-action SQL count regressions (`ActiveSupport::Notifications`). Plus a Vernier-based diagnostic script for investigating failures.

**Architecture:** Each gate is a self-contained vertical slice. After implementing each task, the user can run `bin/rake quality` (or `bin/rspec`) and see the new check working end-to-end, with a clear way to manually trigger a regression and watch the gate fail. The slices in order: (1) Brakeman, (2) Bullet, (3) Allocations, (4) Per-action SQL, (5) Vernier diagnostic. Slices 1, 3, 4 plug into the existing `Quality::Report` machinery via new parsers under `lib/quality/`. Slice 2 fails the spec suite directly. Slice 5 is a standalone tool.

**Tech Stack:** Ruby 3.x / Rails 8, RSpec, `bullet` (gem), `brakeman` (already in Gemfile), `vernier` (gem), `GC.stat`/`ActiveSupport::Notifications` (stdlib).

**Spec:** `docs/superpowers/specs/2026-04-29-perf-security-gate-design.md`

**Important project conventions:**
- **Commits:** Omit any `Co-Authored-By:` trailer — the git hook rejects commits that add one.
- **No auto-commit during plan execution:** pause before each `git commit` step and ask for approval. Plan steps that say "Commit" mean "propose and await approval," not "run commit unattended."
- **Lint + test after every change:** `bin/rspec` and `bundle exec rubocop` must both be green before considering a task complete — repo convention from `CLAUDE.md`.
- **Run `bin/rake quality` at the end of each task** so each slice ends with a green umbrella gate.
- **Do not update `MUTANT_SUBJECTS`** for the new parsers — they fall under the existing `Quality*` glob in `lib/tasks/quality.rake`.

**Each task is a vertical slice.** It adds one fully working gate end-to-end (parser + threshold + report row + rake wiring + a manual verification path) so the user can prove the slice works before moving on.

---

## Task 1: Brakeman security gate

Static security analysis added as a new sub-task `quality:brakeman`. Hard ratchet on warnings count at medium+ confidence. First-run captures the baseline; subsequent runs fail if a new medium+ warning appears.

**Files:**
- Create: `lib/quality/brakeman_parser.rb`
- Create: `spec/lib/quality/brakeman_parser_spec.rb`
- Create: `spec/fixtures/quality/brakeman_zero.json`
- Create: `spec/fixtures/quality/brakeman_one_warning.json`
- Modify: `lib/quality/report.rb`
- Modify: `spec/lib/quality/report_spec.rb`
- Modify: `lib/tasks/quality.rake`
- Modify: `config/quality_thresholds.yml`

- [ ] **Step 1: Create the zero-warnings fixture**

  `spec/fixtures/quality/brakeman_zero.json`:
  ```json
  {
    "scan_info": { "app_path": "/app", "rails_version": "8.0.5" },
    "warnings": [],
    "errors": [],
    "obsolete": []
  }
  ```

- [ ] **Step 2: Create the one-warning fixture**

  `spec/fixtures/quality/brakeman_one_warning.json`:
  ```json
  {
    "scan_info": { "app_path": "/app", "rails_version": "8.0.5" },
    "warnings": [
      {
        "warning_type": "SQL Injection",
        "warning_code": 0,
        "fingerprint": "abc123",
        "check_name": "SQL",
        "message": "Possible SQL injection",
        "file": "app/controllers/example_controller.rb",
        "line": 42,
        "link": "https://brakemanscanner.org/docs/warning_types/sql_injection/",
        "code": "User.where(\"name = '#{params[:name]}'\")",
        "render_path": null,
        "location": { "type": "method", "class": "ExampleController", "method": "index" },
        "user_input": "params[:name]",
        "confidence": "Medium"
      }
    ],
    "errors": [],
    "obsolete": []
  }
  ```

- [ ] **Step 3: Write the failing parser spec**

  `spec/lib/quality/brakeman_parser_spec.rb`:
  ```ruby
  require "rails_helper"
  require "tempfile"

  RSpec.describe Quality::BrakemanParser do
    it "returns zero warnings when the report has none" do
      path = Rails.root.join("spec/fixtures/quality/brakeman_zero.json")

      parsed = described_class.new(path).parse

      expect(parsed).to eq(warnings: 0)
    end

    it "counts warnings in the report" do
      path = Rails.root.join("spec/fixtures/quality/brakeman_one_warning.json")

      parsed = described_class.new(path).parse

      expect(parsed).to eq(warnings: 1)
    end

    it "raises on malformed JSON" do
      bad = Tempfile.new([ "brakeman", ".json" ])
      bad.write("not json")
      bad.close

      expect { described_class.new(bad.path).parse }.to raise_error(JSON::ParserError)
    ensure
      bad&.unlink
    end
  end
  ```

- [ ] **Step 4: Run the spec to verify it fails**

  ```bash
  bin/rspec spec/lib/quality/brakeman_parser_spec.rb
  ```

  Expected: FAIL with `NameError: uninitialized constant Quality::BrakemanParser`.

- [ ] **Step 5: Implement the parser**

  `lib/quality/brakeman_parser.rb`:
  ```ruby
  require "json"

  module Quality
    class BrakemanParser
      def initialize(path)
        @path = path
      end

      def parse
        data = JSON.parse(File.read(@path))
        { warnings: data.fetch("warnings").size }
      end
    end
  end
  ```

- [ ] **Step 6: Run the spec to verify it passes**

  ```bash
  bin/rspec spec/lib/quality/brakeman_parser_spec.rb
  ```

  Expected: 3 examples, 0 failures.

- [ ] **Step 7: Add a failing Report spec for the brakeman gate**

  Add to `spec/lib/quality/report_spec.rb` inside the existing `describe Quality::Report do` block:

  ```ruby
  it "passes the brakeman gate when warnings are within the threshold" do
    measurements = passing_measurements.merge(brakeman: { warnings: 0 })
    open_thresholds = thresholds.merge("brakeman" => { "warnings_max" => 0 })

    report = described_class.new(measurements: measurements, thresholds: open_thresholds)

    brakeman_row = report.gate_results.find { |r| r.name == "Brakeman warnings" }
    expect(brakeman_row.passed?).to be true
  end

  it "fails the brakeman gate when warnings exceed the threshold" do
    measurements = passing_measurements.merge(brakeman: { warnings: 3 })
    bad_thresholds = thresholds.merge("brakeman" => { "warnings_max" => 0 })

    report = described_class.new(measurements: measurements, thresholds: bad_thresholds)

    brakeman_row = report.gate_results.find { |r| r.name == "Brakeman warnings" }
    expect(brakeman_row.passed?).to be false
    expect(report.passed?).to be false
  end
  ```

- [ ] **Step 8: Run report spec to verify it fails**

  ```bash
  bin/rspec spec/lib/quality/report_spec.rb
  ```

  Expected: 2 new examples FAIL because the Brakeman gate isn't in `Report::GATES` yet.

- [ ] **Step 9: Add Brakeman to `Quality::Report::GATES`**

  In `lib/quality/report.rb`, append a new entry to the `GATES` array (after the mutation entry):

  ```ruby
  { name: "Brakeman warnings",      measure: [ :brakeman, :warnings ],                  threshold: [ "brakeman", "warnings_max" ],                   cmp: :<=, unit: "" }
  ```

  Full `GATES` array becomes:

  ```ruby
  GATES = [
    { name: "Line coverage",            measure: [ :coverage, :line ],                       threshold: [ "coverage", "line_min" ],                       cmp: :>=, unit: "%" },
    { name: "Branch coverage",          measure: [ :coverage, :branch ],                     threshold: [ "coverage", "branch_min" ],                     cmp: :>=, unit: "%" },
    { name: "Flog max (method)",        measure: [ :flog, :method_max ],                     threshold: [ "flog", "method_max" ],                         cmp: :<=, unit: "" },
    { name: "Flog max (class)",         measure: [ :flog, :class_max ],                      threshold: [ "flog", "class_max" ],                          cmp: :<=, unit: "" },
    { name: "Class length max",         measure: [ :rubocop, :class_length_max ],            threshold: [ "rubocop_metrics", "class_length_max" ],        cmp: :<=, unit: "" },
    { name: "Method length max",        measure: [ :rubocop, :method_length_max ],           threshold: [ "rubocop_metrics", "method_length_max" ],       cmp: :<=, unit: "" },
    { name: "AbcSize max",              measure: [ :rubocop, :abc_size_max ],                threshold: [ "rubocop_metrics", "abc_size_max" ],            cmp: :<=, unit: "" },
    { name: "CyclomaticComplexity max", measure: [ :rubocop, :cyclomatic_complexity_max ],   threshold: [ "rubocop_metrics", "cyclomatic_complexity_max" ], cmp: :<=, unit: "" },
    { name: "Mutation kill ratio",      measure: [ :mutation, :kill_ratio ],                 threshold: [ "mutation", "kill_ratio_min" ],                 cmp: :>=, unit: "%" },
    { name: "Brakeman warnings",        measure: [ :brakeman, :warnings ],                   threshold: [ "brakeman", "warnings_max" ],                   cmp: :<=, unit: "" }
  ].freeze
  ```

- [ ] **Step 10: Re-run report spec to verify it passes**

  ```bash
  bin/rspec spec/lib/quality/report_spec.rb
  ```

  Expected: all examples pass.

- [ ] **Step 11: Add the `quality:brakeman` rake task**

  In `lib/tasks/quality.rake`, append a new task inside the `namespace :quality` block (between `:critic` and `:report`):

  ```ruby
  desc "Run Brakeman; emit JSON to tmp/quality/brakeman.json; ratchet warnings_max on first run"
  task :brakeman do
    FileUtils.mkdir_p(QUALITY_DIR)
    out_path = QUALITY_DIR.join("brakeman.json")
    # Brakeman exits non-zero when warnings exist; we capture output and let the report decide.
    sh "bundle exec brakeman --format json --confidence-level 2 --no-pager " \
       "-o #{out_path.to_s.shellescape} || true"

    parsed = Quality::BrakemanParser.new(out_path).parse
    ratchet_brakeman_if_unset!(parsed[:warnings])
  end
  ```

  Append the ratchet helper to the bottom of the file (after `ratchet_if_unset!`):

  ```ruby
  def ratchet_brakeman_if_unset!(warnings)
    require "yaml"
    path = Rails.root.join("config/quality_thresholds.yml")
    thresholds = YAML.load_file(path)
    thresholds["brakeman"] ||= {}

    return unless thresholds["brakeman"]["warnings_max"].nil?

    thresholds["brakeman"]["warnings_max"] = warnings
    File.write(path, thresholds.to_yaml)
    puts "[quality:brakeman] Ratchet set: brakeman.warnings_max = #{warnings}"
  end
  ```

- [ ] **Step 12: Update the umbrella `quality` task to depend on `quality:brakeman`**

  At the bottom of `lib/tasks/quality.rake`, modify the umbrella task:

  ```ruby
  desc "Run all quality gates: coverage, rubocop, critic, flog, mutation, brakeman, report"
  task quality: %w[
    quality:coverage
    quality:rubocop
    quality:critic
    quality:flog
    quality:mutation
    quality:brakeman
    quality:report
  ]
  ```

- [ ] **Step 13: Update `quality:report` to load the brakeman measurement**

  In `lib/tasks/quality.rake`, modify the `:report` task's measurements hash:

  ```ruby
  measurements = {
    coverage: Quality::CoverageParser.new(QUALITY_DIR.join("coverage.json")).parse,
    rubocop: Quality::RubocopParser.new(QUALITY_DIR.join("rubocop.json")).parse,
    flog: JSON.parse(File.read(QUALITY_DIR.join("flog.json")), symbolize_names: true),
    mutation: JSON.parse(File.read(QUALITY_DIR.join("mutation.json")), symbolize_names: true),
    brakeman: Quality::BrakemanParser.new(QUALITY_DIR.join("brakeman.json")).parse
  }
  ```

  Update the "Detailed reports:" footer in the same task:

  ```ruby
  puts "  #{QUALITY_DIR.join('overview.html')}    (RubyCritic)"
  puts "  #{Rails.root.join('coverage/index.html')}       (SimpleCov)"
  puts "  #{QUALITY_DIR.join('mutation.txt')}       (Mutant)"
  puts "  #{QUALITY_DIR.join('brakeman.json')}       (Brakeman)"
  ```

- [ ] **Step 14: Add a placeholder `brakeman` section to `config/quality_thresholds.yml`**

  Append to the bottom of `config/quality_thresholds.yml`:

  ```yaml
  brakeman:
    warnings_max:    # ratcheted on first run
  ```

  Leaving `warnings_max` empty (nil) tells the rake task to capture the value on first run.

- [ ] **Step 15: Run `quality:brakeman` to capture the baseline**

  ```bash
  bin/rake quality:brakeman
  ```

  Expected: brakeman runs, writes `tmp/quality/brakeman.json`, prints `[quality:brakeman] Ratchet set: brakeman.warnings_max = N`.

  If `N > 0` (Brakeman found medium+ warnings on `main`):
  - Inspect the warnings: `cat tmp/quality/brakeman.json | jq '.warnings'`
  - Either fix them in this task and re-run (preferred — green from day one), or accept the baseline of `N` (ratchet stays at N, gate fails on N+1).
  - Discuss with the user before accepting any non-zero baseline.

- [ ] **Step 16: Verify the threshold file was updated**

  ```bash
  cat config/quality_thresholds.yml
  ```

  Expected: `brakeman.warnings_max` now contains the captured integer (typically 0).

- [ ] **Step 17: Run the full quality gate**

  ```bash
  bin/rake quality
  ```

  Expected: all gates pass, the report shows a new row:

  ```
  Brakeman warnings         0       <= 0          ✓
  ```

  And the count line shows `10/10 gates passed.` (was 9/9; brakeman is the new 10th).

- [ ] **Step 18: Manual regression check (optional but recommended)**

  Temporarily introduce a SQL injection in any controller (e.g., `User.where("name = '#{params[:name]}'")`), run the gate, and confirm it fails:

  ```bash
  # In some controller, change a finder to use string interpolation
  bin/rake quality:brakeman
  bin/rake quality
  ```

  Expected: `Brakeman warnings  1   <= 0   ✗` and the gate fails with `9/10 gates passed.`

  Revert the change before continuing:

  ```bash
  git checkout app/controllers/<the_modified_file>.rb
  bin/rake quality:brakeman
  bin/rake quality
  ```

  Expected: back to all green.

- [ ] **Step 19: Run rubocop and the full spec suite**

  ```bash
  bundle exec rubocop
  bin/rspec
  ```

  Expected: both green.

- [ ] **Step 20: Commit (await approval first)**

  ```bash
  git add lib/quality/brakeman_parser.rb \
          spec/lib/quality/brakeman_parser_spec.rb \
          spec/fixtures/quality/brakeman_zero.json \
          spec/fixtures/quality/brakeman_one_warning.json \
          lib/quality/report.rb \
          spec/lib/quality/report_spec.rb \
          lib/tasks/quality.rake \
          config/quality_thresholds.yml
  git commit -m "feat(quality): add Brakeman gate to bin/rake quality (ratcheted, medium+ confidence)"
  ```

---

## Task 2: Bullet N+1 gate

Wire the `bullet` gem into the RSpec suite. Bullet raises on N+1 patterns, which fails the offending spec, which fails `bin/rspec`, which fails `quality:coverage`. No threshold, no parser — the spec failure is the signal. The report surfaces a "Bullet (N+1)" line so a passing run is visibly accounted for.

**Files:**
- Modify: `Gemfile`
- Create: `spec/support/bullet.rb`
- Modify: `spec/rails_helper.rb` (uncomment the support-file glob loader)
- Modify: `lib/quality/report.rb`
- Modify: `spec/lib/quality/report_spec.rb`

- [ ] **Step 1: Add `bullet` to the Gemfile**

  Edit `Gemfile`. Inside the existing `group :development, :test do ... end` block, add:

  ```ruby
  gem "bullet"
  ```

- [ ] **Step 2: Run `bundle install`**

  ```bash
  bundle install
  ```

  Expected: bullet 8.x installed; clean Gemfile.lock update.

- [ ] **Step 3: Uncomment the spec/support glob loader**

  In `spec/rails_helper.rb`, change line 38 from:

  ```ruby
  # Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }
  ```

  to:

  ```ruby
  Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }
  ```

  This loads every `.rb` file under `spec/support/` automatically. All later tasks rely on this.

- [ ] **Step 4: Create `spec/support/bullet.rb`**

  ```ruby
  require "bullet"

  Bullet.enable      = true
  Bullet.raise       = true
  Bullet.bullet_logger = false
  Bullet.console     = false

  RSpec.configure do |config|
    config.before(:each) { Bullet.start_request }
    config.after(:each) do
      Bullet.perform_out_of_channel_notifications if Bullet.notification?
      Bullet.end_request
    end
  end
  ```

- [ ] **Step 5: Run the full spec suite to flush out any existing N+1s**

  ```bash
  bin/rspec
  ```

  Expected: either green, or some specs fail with `Bullet::Notification::UnoptimizedQueryError`.

  If any specs fail with Bullet errors:
  - Read the message — it points at the model/association needing `includes`.
  - Add the `includes` (or equivalent) in the controller / service responsible.
  - If the flag is genuinely a false positive (rare), add a `Bullet.add_safelist` entry in `spec/support/bullet.rb` with a comment explaining why.
  - Re-run until green.

  Discuss with the user before merging any safelist entries.

- [ ] **Step 6: Add a "Bullet (N+1)" informational row to `Quality::Report`**

  Bullet doesn't produce an artifact — its job is binary, and reaching the report means the suite (and Bullet) passed. We surface it so a green report says "yes, Bullet is in the loop."

  In `lib/quality/report.rb`, modify `to_s`:

  ```ruby
  def to_s
    lines = [ "Quality gates", "=" * 13, "" ]
    lines.concat(gate_results.map(&:to_row))
    lines << bullet_line
    lines << ""
    lines << "#{gate_results.count(&:passed?)}/#{gate_results.size} gates passed."
    lines.join("\n")
  end

  private

  def bullet_line
    "Bullet (N+1)              -       no spec failures   ✓"
  end
  ```

  (`bullet_line` is hard-coded because, by the time `quality:report` runs, we know `quality:coverage` already ran `bin/rspec` successfully — Bullet must have passed.)

- [ ] **Step 7: Add a Report spec for the Bullet line**

  Append inside the existing `describe Quality::Report do` block in `spec/lib/quality/report_spec.rb`:

  ```ruby
  it "renders an informational Bullet row" do
    report = described_class.new(measurements: passing_measurements, thresholds: thresholds)

    output = report.to_s

    expect(output).to include("Bullet (N+1)", "no spec failures", "✓")
  end
  ```

- [ ] **Step 8: Run report spec to verify it passes**

  ```bash
  bin/rspec spec/lib/quality/report_spec.rb
  ```

  Expected: all examples pass (10+ examples, 0 failures).

- [ ] **Step 9: Run the full quality gate**

  ```bash
  bin/rake quality
  ```

  Expected: green report, with the new Bullet line appearing after the existing gate rows.

- [ ] **Step 10: Manual regression check**

  Verify Bullet actually catches an N+1. Pick any controller action that already uses `includes` (e.g., `DashboardController#index`). Temporarily remove its `includes(...)` call. Run only the request spec for that action:

  ```bash
  bin/rspec spec/requests/<the_modified_controller>_spec.rb
  ```

  Expected: spec fails with `Bullet::Notification::UnoptimizedQueryError: USE eager loading detected ...`.

  Revert the change:

  ```bash
  git checkout app/controllers/<the_modified_file>.rb
  bin/rspec
  ```

  Expected: back to green.

- [ ] **Step 11: Run rubocop**

  ```bash
  bundle exec rubocop
  ```

  Expected: green.

- [ ] **Step 12: Commit (await approval first)**

  ```bash
  git add Gemfile Gemfile.lock \
          spec/support/bullet.rb \
          spec/rails_helper.rb \
          lib/quality/report.rb \
          spec/lib/quality/report_spec.rb
  git commit -m "feat(quality): wire Bullet into RSpec; raises on N+1, surfaces in quality report"
  ```

  Note: if Step 5 required adding `includes` calls or fixing an N+1 in real code, those changes go in this same commit.

---

## Task 3: Suite-wide allocations gate

Capture `GC.stat(:total_allocated_objects)` around the spec suite via `before(:suite)`/`after(:suite)` hooks, write to `tmp/quality/allocations.json`, gate on a ratcheted total with a +15% tolerance band.

**Files:**
- Create: `spec/support/allocations.rb`
- Create: `lib/quality/allocations_parser.rb`
- Create: `spec/lib/quality/allocations_parser_spec.rb`
- Create: `spec/fixtures/quality/allocations.json`
- Modify: `lib/quality/report.rb`
- Modify: `spec/lib/quality/report_spec.rb`
- Modify: `lib/tasks/quality.rake`
- Modify: `config/quality_thresholds.yml`

- [ ] **Step 1: Create the allocations fixture**

  `spec/fixtures/quality/allocations.json`:
  ```json
  {
    "total_allocated_objects": 1400000
  }
  ```

- [ ] **Step 2: Write the failing parser spec**

  `spec/lib/quality/allocations_parser_spec.rb`:
  ```ruby
  require "rails_helper"
  require "tempfile"

  RSpec.describe Quality::AllocationsParser do
    it "returns the total allocated objects from the JSON artifact" do
      path = Rails.root.join("spec/fixtures/quality/allocations.json")

      parsed = described_class.new(path).parse

      expect(parsed).to eq(total_allocated_objects: 1_400_000)
    end

    it "raises on malformed JSON" do
      bad = Tempfile.new([ "allocations", ".json" ])
      bad.write("not json")
      bad.close

      expect { described_class.new(bad.path).parse }.to raise_error(JSON::ParserError)
    ensure
      bad&.unlink
    end
  end
  ```

- [ ] **Step 3: Run the spec to verify it fails**

  ```bash
  bin/rspec spec/lib/quality/allocations_parser_spec.rb
  ```

  Expected: FAIL with `NameError: uninitialized constant Quality::AllocationsParser`.

- [ ] **Step 4: Implement the parser**

  `lib/quality/allocations_parser.rb`:
  ```ruby
  require "json"

  module Quality
    class AllocationsParser
      def initialize(path)
        @path = path
      end

      def parse
        data = JSON.parse(File.read(@path), symbolize_names: true)
        { total_allocated_objects: data.fetch(:total_allocated_objects) }
      end
    end
  end
  ```

- [ ] **Step 5: Run the spec to verify it passes**

  ```bash
  bin/rspec spec/lib/quality/allocations_parser_spec.rb
  ```

  Expected: 2 examples, 0 failures.

- [ ] **Step 6: Add a failing Report spec for the allocations gate**

  Append inside the existing `describe Quality::Report do` block in `spec/lib/quality/report_spec.rb`:

  ```ruby
  it "passes the allocations gate when within the tolerance band" do
    measurements = passing_measurements.merge(allocations: { total_allocated_objects: 1_420_000 })
    open_thresholds = thresholds.merge(
      "allocations" => { "total_max" => 1_400_000, "tolerance_pct" => 15 }
    )

    report = described_class.new(measurements: measurements, thresholds: open_thresholds)

    row = report.gate_results.find { |r| r.name == "Allocations (total)" }
    expect(row.passed?).to be true
  end

  it "fails the allocations gate when above the tolerance band" do
    measurements = passing_measurements.merge(allocations: { total_allocated_objects: 1_700_000 })
    bad_thresholds = thresholds.merge(
      "allocations" => { "total_max" => 1_400_000, "tolerance_pct" => 15 }
    )

    report = described_class.new(measurements: measurements, thresholds: bad_thresholds)

    row = report.gate_results.find { |r| r.name == "Allocations (total)" }
    expect(row.passed?).to be false
    expect(report.passed?).to be false
  end
  ```

- [ ] **Step 7: Run the report spec to verify it fails**

  ```bash
  bin/rspec spec/lib/quality/report_spec.rb
  ```

  Expected: 2 new examples FAIL because the allocations gate isn't wired up yet.

- [ ] **Step 8: Add allocations handling to `Quality::Report`**

  In `lib/quality/report.rb`, replace `build_gate_results` and add a helper:

  ```ruby
  def build_gate_results
    static = GATES.filter_map do |gate|
      measured = @measurements.dig(*gate[:measure])
      next if measured.nil?

      GateResult.new(
        name: gate[:name],
        measured: measured,
        threshold: @thresholds.dig(*gate[:threshold]),
        comparator: gate[:cmp],
        unit: gate[:unit]
      )
    end

    static + build_allocations_gate
  end

  def build_allocations_gate
    config = @thresholds["allocations"] || {}
    measured = @measurements.dig(:allocations, :total_allocated_objects)
    return [] if measured.nil?

    total_max = config["total_max"]
    tolerance_pct = config["tolerance_pct"] || 0
    effective = total_max && (total_max * (1 + tolerance_pct / 100.0)).floor

    [ GateResult.new(
      name: "Allocations (total)",
      measured: measured,
      threshold: effective,
      comparator: :<=,
      unit: ""
    ) ]
  end
  ```

- [ ] **Step 9: Re-run report spec to verify it passes**

  ```bash
  bin/rspec spec/lib/quality/report_spec.rb
  ```

  Expected: all examples pass.

- [ ] **Step 10: Create the spec/support hook for allocation capture**

  `spec/support/allocations.rb`:
  ```ruby
  require "fileutils"
  require "json"

  module QualityAllocationsState
    class << self
      attr_accessor :start
    end
  end

  RSpec.configure do |config|
    config.before(:suite) do
      QualityAllocationsState.start = GC.stat(:total_allocated_objects)
    end

    config.after(:suite) do
      diff = GC.stat(:total_allocated_objects) - QualityAllocationsState.start
      out_dir = Rails.root.join("tmp/quality")
      FileUtils.mkdir_p(out_dir)
      File.write(
        out_dir.join("allocations.json"),
        JSON.pretty_generate(total_allocated_objects: diff)
      )
    end
  end
  ```

  (RSpec's `before(:suite)` and `after(:suite)` hooks run in different example-group instances, so an `@ivar` set in one wouldn't be visible in the other. We park the start value on a module accessor so both hooks share the same reference.)

- [ ] **Step 11: Wire the allocations measurement into `quality:report`**

  In `lib/tasks/quality.rake`, modify the `:report` task's measurements hash to include the allocations entry:

  ```ruby
  measurements = {
    coverage: Quality::CoverageParser.new(QUALITY_DIR.join("coverage.json")).parse,
    rubocop: Quality::RubocopParser.new(QUALITY_DIR.join("rubocop.json")).parse,
    flog: JSON.parse(File.read(QUALITY_DIR.join("flog.json")), symbolize_names: true),
    mutation: JSON.parse(File.read(QUALITY_DIR.join("mutation.json")), symbolize_names: true),
    brakeman: Quality::BrakemanParser.new(QUALITY_DIR.join("brakeman.json")).parse,
    allocations: Quality::AllocationsParser.new(QUALITY_DIR.join("allocations.json")).parse
  }
  ```

- [ ] **Step 12: Add a placeholder `allocations` section to `config/quality_thresholds.yml`**

  Append:

  ```yaml
  allocations:
    total_max:    # ratcheted on first run
    tolerance_pct: 15
  ```

- [ ] **Step 13: Add a ratchet helper for allocations to the rake file**

  In `lib/tasks/quality.rake`, after `ratchet_brakeman_if_unset!`, add:

  ```ruby
  def ratchet_allocations_if_unset!(total)
    require "yaml"
    path = Rails.root.join("config/quality_thresholds.yml")
    thresholds = YAML.load_file(path)
    thresholds["allocations"] ||= {}

    return unless thresholds["allocations"]["total_max"].nil?

    thresholds["allocations"]["total_max"] = total
    File.write(path, thresholds.to_yaml)
    puts "[quality:coverage] Ratchet set: allocations.total_max = #{total}"
  end
  ```

- [ ] **Step 14: Call the ratchet at the end of `quality:coverage`**

  Allocations are captured during `bin/rspec`, which `quality:coverage` already runs. Modify the existing `:coverage` task:

  ```ruby
  desc "Run rspec with SimpleCov; copy coverage/.last_run.json into tmp/quality/"
  task :coverage do
    FileUtils.mkdir_p(QUALITY_DIR)
    sh "bin/rspec"
    last_run = Rails.root.join("coverage/.last_run.json")
    raise "coverage/.last_run.json missing after bin/rspec" unless last_run.exist?

    FileUtils.cp(last_run, QUALITY_DIR.join("coverage.json"))

    allocations_path = QUALITY_DIR.join("allocations.json")
    if allocations_path.exist?
      parsed = Quality::AllocationsParser.new(allocations_path).parse
      ratchet_allocations_if_unset!(parsed[:total_allocated_objects])
    end
  end
  ```

- [ ] **Step 15: Run `quality:coverage` to capture the allocations baseline**

  ```bash
  bin/rake quality:coverage
  ```

  Expected: spec suite runs, `tmp/quality/allocations.json` is written, output prints `[quality:coverage] Ratchet set: allocations.total_max = N` for some integer `N`.

- [ ] **Step 16: Inspect the captured baseline**

  ```bash
  cat tmp/quality/allocations.json
  cat config/quality_thresholds.yml | grep -A2 allocations
  ```

  Expected: both files show the same `total_allocated_objects` / `total_max` integer (likely a few million for a Rails suite of any size).

- [ ] **Step 17: Run the full quality gate**

  ```bash
  bin/rake quality
  ```

  Expected: a new row appears in the report:

  ```
  Allocations (total)        <total>      <= <effective_max>     ✓
  ```

  Where `<effective_max>` ≈ `total × 1.15`. Gate count goes from 10/10 to 11/11.

- [ ] **Step 18: Manual regression check**

  Add a heavy-allocation block to a frequently-run spec to prove the gate fails on regression. Edit any model/service spec to include this at the top of the `describe` block:

  ```ruby
  before(:all) do
    1_000_000.times { String.new("waste") }
  end
  ```

  Then run:

  ```bash
  bin/rake quality:coverage
  bin/rake quality
  ```

  Expected: `Allocations (total)  <much larger>   <= <effective_max>   ✗` — gate fails.

  Revert the change:

  ```bash
  git checkout spec/<the_modified_spec>.rb
  bin/rake quality:coverage
  bin/rake quality
  ```

  Expected: back to green.

- [ ] **Step 19: Run rubocop**

  ```bash
  bundle exec rubocop
  ```

  Expected: green.

- [ ] **Step 20: Commit (await approval first)**

  ```bash
  git add lib/quality/allocations_parser.rb \
          spec/lib/quality/allocations_parser_spec.rb \
          spec/fixtures/quality/allocations.json \
          spec/support/allocations.rb \
          lib/quality/report.rb \
          spec/lib/quality/report_spec.rb \
          lib/tasks/quality.rake \
          config/quality_thresholds.yml
  git commit -m "feat(quality): suite-wide allocations gate via GC.stat (+15% tolerance, ratcheted)"
  ```

---

## Task 4: Per-action SQL count gate

Subscribe to `start_processing.action_controller`, `sql.active_record`, and `process_action.action_controller` to count queries per controller action during specs. Write per-action max-counts to `tmp/quality/action_metrics.json`. Gate per action with `+25% or +3 queries` tolerance.

**Files:**
- Create: `spec/support/action_metrics.rb`
- Create: `lib/quality/action_metrics_parser.rb`
- Create: `spec/lib/quality/action_metrics_parser_spec.rb`
- Create: `spec/fixtures/quality/action_metrics.json`
- Modify: `lib/quality/report.rb`
- Modify: `spec/lib/quality/report_spec.rb`
- Modify: `lib/tasks/quality.rake`
- Modify: `config/quality_thresholds.yml`

- [ ] **Step 1: Create the action-metrics fixture**

  `spec/fixtures/quality/action_metrics.json`:
  ```json
  {
    "DashboardController#index": { "sql_count_max": 8 },
    "TopicsController#index":    { "sql_count_max": 4 },
    "MatchesController#dismiss": { "sql_count_max": 3 }
  }
  ```

- [ ] **Step 2: Write the failing parser spec**

  `spec/lib/quality/action_metrics_parser_spec.rb`:
  ```ruby
  require "rails_helper"
  require "tempfile"

  RSpec.describe Quality::ActionMetricsParser do
    it "returns each action's sql_count_max keyed by controller#action" do
      path = Rails.root.join("spec/fixtures/quality/action_metrics.json")

      parsed = described_class.new(path).parse

      expect(parsed).to eq(
        "DashboardController#index" => { sql_count_max: 8 },
        "TopicsController#index"    => { sql_count_max: 4 },
        "MatchesController#dismiss" => { sql_count_max: 3 }
      )
    end

    it "returns an empty hash for an empty payload" do
      empty = Tempfile.new([ "action_metrics", ".json" ])
      empty.write("{}")
      empty.close

      parsed = described_class.new(empty.path).parse

      expect(parsed).to eq({})
    ensure
      empty&.unlink
    end

    it "raises on malformed JSON" do
      bad = Tempfile.new([ "action_metrics", ".json" ])
      bad.write("not json")
      bad.close

      expect { described_class.new(bad.path).parse }.to raise_error(JSON::ParserError)
    ensure
      bad&.unlink
    end
  end
  ```

- [ ] **Step 3: Run the spec to verify it fails**

  ```bash
  bin/rspec spec/lib/quality/action_metrics_parser_spec.rb
  ```

  Expected: FAIL with `NameError: uninitialized constant Quality::ActionMetricsParser`.

- [ ] **Step 4: Implement the parser**

  `lib/quality/action_metrics_parser.rb`:
  ```ruby
  require "json"

  module Quality
    class ActionMetricsParser
      def initialize(path)
        @path = path
      end

      def parse
        raw = JSON.parse(File.read(@path))
        raw.each_with_object({}) do |(action, data), result|
          result[action] = { sql_count_max: data.fetch("sql_count_max") }
        end
      end
    end
  end
  ```

- [ ] **Step 5: Run the parser spec to verify it passes**

  ```bash
  bin/rspec spec/lib/quality/action_metrics_parser_spec.rb
  ```

  Expected: 3 examples, 0 failures.

- [ ] **Step 6: Add Report specs for per-action gates**

  Append inside `describe Quality::Report do` in `spec/lib/quality/report_spec.rb`:

  ```ruby
  let(:action_metrics_baselines) do
    {
      "allocations" => { "total_max" => 1_400_000, "tolerance_pct" => 15 },
      "sql_per_action" => {
        "tolerance_pct" => 25,
        "min_delta" => 3,
        "baselines" => { "DashboardController#index" => 8 }
      }
    }
  end

  it "passes a per-action SQL gate when observed is within the percent band" do
    measurements = passing_measurements.merge(
      allocations: { total_allocated_objects: 1_400_000 },
      action_metrics: { "DashboardController#index" => { sql_count_max: 9 } }
    )
    merged_thresholds = thresholds.merge(action_metrics_baselines)

    report = described_class.new(measurements: measurements, thresholds: merged_thresholds)

    row = report.gate_results.find { |r| r.name == "SQL: DashboardController#index" }
    expect(row.passed?).to be true
    expect(row.threshold).to eq(11)  # max(8 * 1.25 = 10, 8 + 3 = 11) → 11
  end

  it "passes a small-action gate via the min_delta floor" do
    measurements = passing_measurements.merge(
      allocations: { total_allocated_objects: 1_400_000 },
      action_metrics: { "MatchesController#dismiss" => { sql_count_max: 5 } }
    )
    open_thresholds = thresholds.merge(
      "allocations" => { "total_max" => 1_400_000, "tolerance_pct" => 15 },
      "sql_per_action" => {
        "tolerance_pct" => 25,
        "min_delta" => 3,
        "baselines" => { "MatchesController#dismiss" => 2 }  # 2 * 1.25 = 2.5 → 2; 2 + 3 = 5; floor wins
      }
    )

    report = described_class.new(measurements: measurements, thresholds: open_thresholds)

    row = report.gate_results.find { |r| r.name == "SQL: MatchesController#dismiss" }
    expect(row.passed?).to be true
    expect(row.threshold).to eq(5)
  end

  it "fails a per-action SQL gate when observed exceeds the cap" do
    measurements = passing_measurements.merge(
      allocations: { total_allocated_objects: 1_400_000 },
      action_metrics: { "DashboardController#index" => { sql_count_max: 25 } }
    )
    merged_thresholds = thresholds.merge(action_metrics_baselines)

    report = described_class.new(measurements: measurements, thresholds: merged_thresholds)

    row = report.gate_results.find { |r| r.name == "SQL: DashboardController#index" }
    expect(row.passed?).to be false
    expect(report.passed?).to be false
  end

  it "lists stale per-action baselines without failing the gate" do
    measurements = passing_measurements.merge(
      allocations: { total_allocated_objects: 1_400_000 },
      action_metrics: {}  # nothing observed
    )
    merged_thresholds = thresholds.merge(action_metrics_baselines)

    report = described_class.new(measurements: measurements, thresholds: merged_thresholds)

    expect(report.passed?).to be true
    expect(report.gate_results.map(&:name)).not_to include("SQL: DashboardController#index")
    expect(report.to_s).to include("DashboardController#index", "[stale - not exercised]")
  end
  ```

- [ ] **Step 7: Run report spec to verify the new examples fail**

  ```bash
  bin/rspec spec/lib/quality/report_spec.rb
  ```

  Expected: the 4 new examples FAIL because per-action handling isn't wired up.

- [ ] **Step 8: Add per-action handling to `Quality::Report`**

  In `lib/quality/report.rb`, modify `build_gate_results`, add a helper for per-action gates, add stale-row tracking, and update `to_s`:

  ```ruby
  def initialize(measurements:, thresholds:)
    @measurements = measurements
    @thresholds = thresholds
    @gate_results = build_gate_results
    @stale_actions = build_stale_actions
  end

  def to_s
    lines = [ "Quality gates", "=" * 13, "" ]
    lines.concat(gate_results.map(&:to_row))
    lines << bullet_line
    @stale_actions.each do |action|
      lines << "SQL: #{action}".ljust(34) + "[stale - not exercised]"
    end
    lines << ""
    lines << "#{gate_results.count(&:passed?)}/#{gate_results.size} gates passed."
    lines.join("\n")
  end

  private

  def build_gate_results
    static = GATES.filter_map do |gate|
      measured = @measurements.dig(*gate[:measure])
      next if measured.nil?

      GateResult.new(
        name: gate[:name],
        measured: measured,
        threshold: @thresholds.dig(*gate[:threshold]),
        comparator: gate[:cmp],
        unit: gate[:unit]
      )
    end

    static + build_allocations_gate + build_action_sql_gates
  end

  def build_action_sql_gates
    config = @thresholds["sql_per_action"] || {}
    baselines = config["baselines"] || {}
    observed = @measurements[:action_metrics] || {}
    tolerance_pct = config["tolerance_pct"] || 25
    min_delta = config["min_delta"] || 3

    baselines.filter_map do |action, baseline|
      observed_count = observed.dig(action, :sql_count_max)
      next if observed_count.nil?  # stale — handled separately

      cap = [ (baseline * (1 + tolerance_pct / 100.0)).floor, baseline + min_delta ].max

      GateResult.new(
        name: "SQL: #{action}",
        measured: observed_count,
        threshold: cap,
        comparator: :<=,
        unit: ""
      )
    end
  end

  def build_stale_actions
    baselines = @thresholds.dig("sql_per_action", "baselines") || {}
    observed = @measurements[:action_metrics] || {}
    baselines.keys.reject { |action| observed.key?(action) }
  end
  ```

  Keep `build_allocations_gate` and `bullet_line` as defined in the previous tasks.

- [ ] **Step 9: Re-run report spec to verify everything passes**

  ```bash
  bin/rspec spec/lib/quality/report_spec.rb
  ```

  Expected: all examples pass.

- [ ] **Step 10: Create the AS::Notifications subscriber**

  `spec/support/action_metrics.rb`:
  ```ruby
  require "fileutils"
  require "json"

  module ActionMetricsTracker
    SKIPPED_QUERY_NAMES = %w[ SCHEMA TRANSACTION CACHE ].freeze
    @data = {}

    class << self
      attr_reader :data

      def reset
        Thread.current[:action_metrics_sql_count] = 0
      end

      def increment
        Thread.current[:action_metrics_sql_count] = (Thread.current[:action_metrics_sql_count] || 0) + 1
      end

      def current
        Thread.current[:action_metrics_sql_count] || 0
      end

      def record(controller:, action:, count:)
        key = "#{controller}##{action}"
        @data[key] ||= { sql_count_max: 0 }
        @data[key][:sql_count_max] = [ @data[key][:sql_count_max], count ].max
      end
    end
  end

  ActiveSupport::Notifications.subscribe("start_processing.action_controller") do |*|
    ActionMetricsTracker.reset
  end

  ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
    payload = args.last
    next if ActionMetricsTracker::SKIPPED_QUERY_NAMES.include?(payload[:name])
    ActionMetricsTracker.increment
  end

  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
    payload = args.last
    ActionMetricsTracker.record(
      controller: payload[:controller],
      action: payload[:action],
      count: ActionMetricsTracker.current
    )
  end

  RSpec.configure do |config|
    config.after(:suite) do
      out_dir = Rails.root.join("tmp/quality")
      FileUtils.mkdir_p(out_dir)
      File.write(
        out_dir.join("action_metrics.json"),
        JSON.pretty_generate(ActionMetricsTracker.data)
      )
    end
  end
  ```

- [ ] **Step 11: Wire the action-metrics measurement into `quality:report`**

  In `lib/tasks/quality.rake`, modify the `:report` task's measurements hash to add the action_metrics entry:

  ```ruby
  measurements = {
    coverage: Quality::CoverageParser.new(QUALITY_DIR.join("coverage.json")).parse,
    rubocop: Quality::RubocopParser.new(QUALITY_DIR.join("rubocop.json")).parse,
    flog: JSON.parse(File.read(QUALITY_DIR.join("flog.json")), symbolize_names: true),
    mutation: JSON.parse(File.read(QUALITY_DIR.join("mutation.json")), symbolize_names: true),
    brakeman: Quality::BrakemanParser.new(QUALITY_DIR.join("brakeman.json")).parse,
    allocations: Quality::AllocationsParser.new(QUALITY_DIR.join("allocations.json")).parse,
    action_metrics: Quality::ActionMetricsParser.new(QUALITY_DIR.join("action_metrics.json")).parse
  }
  ```

- [ ] **Step 12: Add a placeholder `sql_per_action` section to `config/quality_thresholds.yml`**

  Append:

  ```yaml
  sql_per_action:
    tolerance_pct: 25
    min_delta: 3
    baselines:    # populated on first run
  ```

- [ ] **Step 13: Add a per-action ratchet helper to the rake file**

  In `lib/tasks/quality.rake`, after `ratchet_allocations_if_unset!`, add:

  ```ruby
  def ratchet_action_sql_baselines!(observed)
    require "yaml"
    path = Rails.root.join("config/quality_thresholds.yml")
    thresholds = YAML.load_file(path)
    thresholds["sql_per_action"] ||= {}
    thresholds["sql_per_action"]["baselines"] ||= {}

    added = []
    observed.each do |action, data|
      next if thresholds["sql_per_action"]["baselines"].key?(action)

      thresholds["sql_per_action"]["baselines"][action] = data[:sql_count_max]
      added << action
    end

    return if added.empty?

    File.write(path, thresholds.to_yaml)
    puts "[quality:coverage] Captured per-action SQL baselines for: #{added.join(', ')}"
  end
  ```

- [ ] **Step 14: Call the per-action ratchet at the end of `quality:coverage`**

  In `lib/tasks/quality.rake`, modify the `:coverage` task to also call the new ratchet:

  ```ruby
  desc "Run rspec with SimpleCov; copy coverage/.last_run.json into tmp/quality/"
  task :coverage do
    FileUtils.mkdir_p(QUALITY_DIR)
    sh "bin/rspec"
    last_run = Rails.root.join("coverage/.last_run.json")
    raise "coverage/.last_run.json missing after bin/rspec" unless last_run.exist?

    FileUtils.cp(last_run, QUALITY_DIR.join("coverage.json"))

    allocations_path = QUALITY_DIR.join("allocations.json")
    if allocations_path.exist?
      parsed = Quality::AllocationsParser.new(allocations_path).parse
      ratchet_allocations_if_unset!(parsed[:total_allocated_objects])
    end

    action_metrics_path = QUALITY_DIR.join("action_metrics.json")
    if action_metrics_path.exist?
      parsed = Quality::ActionMetricsParser.new(action_metrics_path).parse
      ratchet_action_sql_baselines!(parsed)
    end
  end
  ```

- [ ] **Step 15: Run `quality:coverage` to capture per-action baselines**

  ```bash
  bin/rake quality:coverage
  ```

  Expected: spec suite runs, `tmp/quality/action_metrics.json` written, output prints `[quality:coverage] Captured per-action SQL baselines for: <list of controller#action>`.

- [ ] **Step 16: Inspect the captured baselines**

  ```bash
  cat tmp/quality/action_metrics.json
  cat config/quality_thresholds.yml | grep -A20 sql_per_action
  ```

  Expected: both files list the controller actions exercised by request specs (e.g., `DashboardController#index`, `TopicsController#index`, `MatchesController#dismiss`, etc.) with their max query counts.

- [ ] **Step 17: Run the full quality gate**

  ```bash
  bin/rake quality
  ```

  Expected: per-action rows appear in the report:

  ```
  SQL: DashboardController#index   8   <= 11   ✓
  SQL: TopicsController#index      4   <= 7    ✓
  SQL: MatchesController#dismiss   3   <= 6    ✓
  ```

  Gate count grows by N (number of actions). All green.

- [ ] **Step 18: Manual regression check**

  Add an extra query to a controller action that has a baseline. For example, in `DashboardController#index`, add `User.find_by(email: "noop@example.com")` somewhere in the action body. Then:

  ```bash
  bin/rake quality:coverage
  bin/rake quality
  ```

  Expected: `SQL: DashboardController#index   <baseline + 1>   <= <cap>   ✓` (still within tolerance — `+25%` or `+3` is generous).

  To force failure, add a loop that runs many extra queries (e.g., `5.times { User.find_by(id: -1) }`):

  ```bash
  bin/rake quality:coverage
  bin/rake quality
  ```

  Expected: that action's row fails: `SQL: DashboardController#index   <much larger>   <= <cap>   ✗`.

  Revert and verify green:

  ```bash
  git checkout app/controllers/dashboard_controller.rb
  bin/rake quality:coverage
  bin/rake quality
  ```

- [ ] **Step 19: Manual stale-entry check**

  Manually edit `config/quality_thresholds.yml` and add a fake action that has no spec exercising it:

  ```yaml
  sql_per_action:
    baselines:
      # ...existing entries...
      FakeController#missing: 99
  ```

  Run:

  ```bash
  bin/rake quality:coverage
  bin/rake quality
  ```

  Expected: report shows `SQL: FakeController#missing   [stale - not exercised]` at the bottom of the gate rows. Gate still passes (stale entries don't fail).

  Remove the fake entry:

  ```bash
  git checkout config/quality_thresholds.yml
  ```

- [ ] **Step 20: Run rubocop**

  ```bash
  bundle exec rubocop
  ```

  Expected: green.

- [ ] **Step 21: Commit (await approval first)**

  ```bash
  git add lib/quality/action_metrics_parser.rb \
          spec/lib/quality/action_metrics_parser_spec.rb \
          spec/fixtures/quality/action_metrics.json \
          spec/support/action_metrics.rb \
          lib/quality/report.rb \
          spec/lib/quality/report_spec.rb \
          lib/tasks/quality.rake \
          config/quality_thresholds.yml
  git commit -m "feat(quality): per-action SQL count gate via AS::Notifications (+25% or +3 ratcheted)"
  ```

---

## Task 5: Vernier diagnostic script + CLAUDE.md update

Vernier is a development-only diagnostic tool. It's not part of the gate — it's what you run when the gate flags an allocation regression and you need to figure out where the regression is. Plus a one-line update to CLAUDE.md.

**Files:**
- Modify: `Gemfile`
- Create: `script/profile.rb`
- Create: `docs/profiling.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add `vernier` to the Gemfile**

  In `Gemfile`, inside the `group :development, :test do ... end` block, add:

  ```ruby
  gem "vernier"
  ```

- [ ] **Step 2: Run `bundle install`**

  ```bash
  bundle install
  ```

  Expected: vernier 1.x installed cleanly.

- [ ] **Step 3: Create `script/profile.rb`**

  ```ruby
  #!/usr/bin/env ruby
  require_relative "../config/environment"
  require "vernier"

  expression = ARGV.first or abort "Usage: bin/ruby script/profile.rb '<ruby expression>'"

  out = Rails.root.join("tmp/quality/vernier.json").to_s
  Vernier.profile(out: out) { eval(expression) }  # rubocop:disable Security/Eval

  puts "Wrote #{out}"
  puts "Open it in https://profiler.firefox.com (drag the file into the page)."
  ```

  Make it executable:

  ```bash
  chmod +x script/profile.rb
  ```

- [ ] **Step 4: Smoke-test the script**

  ```bash
  mkdir -p tmp/quality
  bin/ruby script/profile.rb 'sleep(0.05)'
  ls -lh tmp/quality/vernier.json
  ```

  Expected: file created, non-empty (a few KB minimum), JSON content.

- [ ] **Step 5: Create `docs/profiling.md`**

  ```markdown
  # Profiling with Vernier

  Vernier is a CPU + allocation profiler for Ruby. We use it on-demand when the
  `bin/rake quality` gate flags a regression and we need to find the cause.

  ## When to run

  - The `Allocations (total)` gate fails: a recent change is allocating more
    objects across the spec suite.
  - A `SQL: Controller#action` gate fails *and* you've ruled out an obvious
    new query: the regression may be in CPU work or string allocations.
  - You're investigating "feels slow" on a specific code path before a release.

  Vernier is not part of the automated gate. It is a tool a human (or Claude
  prompted by the gate) runs to investigate after a failure.

  ## How to run

  ```bash
  bin/ruby script/profile.rb '<ruby expression>'
  ```

  Examples:

  ```bash
  # Profile a controller action against the current dev DB
  bin/ruby script/profile.rb 'DashboardController.new.tap { |c| c.params = ActionController::Parameters.new; c.index }'

  # Profile a service or job
  bin/ruby script/profile.rb 'MatchJob.new.perform(Story.last.id)'

  # Profile any Ruby expression
  bin/ruby script/profile.rb 'Match.where(dismissed_at: nil).each { |m| m.story.title }'
  ```

  Output is written to `tmp/quality/vernier.json`.

  ## How to read the profile

  1. Open https://profiler.firefox.com in a browser.
  2. Drag `tmp/quality/vernier.json` onto the page (or use the file picker).
  3. The default view is a flame graph: function names on the y-axis, time on
     the x-axis, width = wall time spent in the function.
  4. Switch to the **Allocations** tab (top of the page) to see per-method
     allocation counts. This is where you look first if the allocations gate
     was what failed.
  5. Look for unexpectedly wide blocks (CPU) or unexpectedly tall allocation
     bars on methods you didn't change. Those are usually the culprits.

  ## Resolving a flagged regression

  Once you've identified the hot method:

  - **Genuine optimization:** fix the code, re-run `bin/rake quality`, confirm
    the gate is back to green. The threshold stays put — you've just moved
    farther under it.
  - **Acceptable regression** (new feature genuinely needs more allocations):
    bump the relevant threshold in `config/quality_thresholds.yml` *as a
    deliberate, separate commit* explaining the trade-off. Reviewers can see
    the threshold bump in the diff.

  Never bump a threshold without first running Vernier to understand why the
  number changed.
  ```

- [ ] **Step 6: Update CLAUDE.md**

  In `CLAUDE.md`, replace the existing quality-gate bullet:

  ```markdown
  - **Run the quality gate before committing.** Run `bin/rake quality` before declaring a task complete. Do not commit if any gate fails. Report the gate numbers in your response so regressions are visible. Thresholds live in `config/quality_thresholds.yml`.
  ```

  with:

  ```markdown
  - **Run the quality gate before committing.** Run `bin/rake quality` before declaring a task complete. Do not commit if any gate fails. Report the gate numbers in your response so regressions are visible. Thresholds live in `config/quality_thresholds.yml`. If the allocations gate fails, run `bin/ruby script/profile.rb '<expression>'` against the suspected hot path and share the Vernier findings before raising the threshold (see `docs/profiling.md`).
  ```

- [ ] **Step 7: Run the full gate one more time**

  ```bash
  bin/rake quality
  ```

  Expected: green.

- [ ] **Step 8: Run rubocop**

  ```bash
  bundle exec rubocop
  ```

  Expected: green.

- [ ] **Step 9: Commit (await approval first)**

  ```bash
  git add Gemfile Gemfile.lock \
          script/profile.rb \
          docs/profiling.md \
          CLAUDE.md
  git commit -m "feat(quality): vernier diagnostic script + docs/profiling.md + CLAUDE.md update"
  ```

---

## Final verification

After Task 5 commits, do an end-to-end pass to confirm everything is wired correctly.

- [ ] **Step 1: Clean tmp and re-run from scratch**

  ```bash
  rm -rf tmp/quality coverage
  bin/rake quality
  ```

  Expected: every sub-task runs from a clean slate; final report shows all 12 + N gate rows green.

- [ ] **Step 2: Confirm threshold file looks right**

  ```bash
  cat config/quality_thresholds.yml
  ```

  Expected: contains sections for `coverage`, `flog`, `rubocop_metrics`, `mutation`, `brakeman` (with `warnings_max` populated), `allocations` (with `total_max` populated, `tolerance_pct: 15`), and `sql_per_action` (with `tolerance_pct: 25`, `min_delta: 3`, and `baselines` populated for every action exercised by request specs).

- [ ] **Step 3: Quick smoke-check of the report's bullet/stale logic**

  Use the same regression tactics from Tasks 2/3/4 once more in any order, confirming the new gates still fail-then-pass cleanly. Five minutes; not exhaustive.
