# Code Quality Metrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Instrument the Rails app with four Uncle-Bob-style quality gates — test coverage (SimpleCov), complexity + module size (Rubocop Metrics + Flog), and mutation testing (Mutant) — wrapped in a single `bin/rake quality` command that fails on threshold breach. Thresholds live in `config/quality_thresholds.yml`; mutation kill ratio is ratcheted, everything else is aspirational.

**Architecture:** One rake namespace with four data-producing sub-tasks (`quality:coverage`, `quality:rubocop`, `quality:critic`, `quality:mutation`) plus a `quality:report` aggregator that reads the JSON artifacts under `tmp/quality/` and compares them to `config/quality_thresholds.yml`. Aggregator + parsers are plain Ruby under `lib/quality/`, each testable with hand-crafted fixtures — no shelling out in specs.

**Tech Stack:** Ruby 3.x / Rails 8, RSpec, SimpleCov, RuboCop (metrics cops on top of rubocop-rails-omakase), RubyCritic (Flog/Flay/Reek aggregator, HTML dashboard), Flog (programmatic API), Mutant with rspec integration.

**Spec:** `docs/superpowers/specs/2026-04-21-code-quality-metrics-design.md`

**Important project conventions:**
- **Commits:** Omit any `Co-Authored-By:` trailer — the git hook rejects commits that add one.
- **No auto-commit during plan execution:** pause before each `git commit` step and ask for approval. Plan steps that say "Commit" mean "propose and await approval," not "run commit unattended."
- **Lint + test after every change:** `bin/rspec` and `bundle exec rubocop` must both be green before considering a task complete — this is a repo convention from `CLAUDE.md`.

---

## Task 1: Add gems and wire SimpleCov into the spec suite

**Files:**
- Modify: `Gemfile`
- Modify: `spec/spec_helper.rb`
- Modify: `.gitignore`

- [ ] **Step 1: Add gems to `Gemfile`**

  Add inside the existing `group :development, :test do ... end` block (next to `rspec-rails`):

  ```ruby
  gem "simplecov", require: false
  ```

  Add a new development-only block for the analysis tools (they aren't needed when the suite runs in CI inside Docker, only for local gate runs — but keeping them in `:development, :test` is also fine since dev/test gems are all installed locally):

  ```ruby
  group :development do
    gem "rubycritic", require: false
    gem "flog", require: false
    gem "mutant-rspec", require: false
  end
  ```

  **Note on Mutant licensing:** Before running `bundle install`, check the `mutant` gem's current license on rubygems.org. If the active release requires a paid license for commercial / private-repo use, substitute `mutest-rspec` (fork) in the Gemfile. Document the substitution in the commit message.

- [ ] **Step 2: Run `bundle install`**

  ```bash
  bundle install
  ```

  Expected: clean install, all gems resolve. If Mutant licensing blocks the install, switch to `mutest-rspec` and retry.

- [ ] **Step 3: Wire SimpleCov at the top of `spec/spec_helper.rb`**

  Insert the following as the **very first lines** of the file (SimpleCov must start before anything under measurement is required):

  ```ruby
  require "simplecov"

  SimpleCov.start "rails" do
    enable_coverage :branch
    add_filter "/spec/"
    add_filter "/config/"
    add_filter "/db/"
    add_filter "/lib/tasks/"
  end
  ```

  Keep the existing RSpec.configure block intact below.

- [ ] **Step 4: Add `coverage/` to `.gitignore`**

  Append to `.gitignore`:

  ```
  # Code quality artifacts
  /coverage/
  /tmp/quality/
  ```

  (`tmp/*` is already gitignored, but adding `/tmp/quality/` is explicit documentation.)

- [ ] **Step 5: Run specs and verify coverage artifact lands on disk**

  ```bash
  bin/rspec
  ls coverage/.last_run.json
  cat coverage/.last_run.json
  ```

  Expected: green spec run; `coverage/.last_run.json` exists; contents look like `{"result":{"line":<number>,"branch":<number>}}`. If `branch` is missing, branch coverage is unsupported on this Ruby/SimpleCov combo — drop `enable_coverage :branch` from Step 3 and rerun (this is the "branch coverage on Ruby 3.x" risk flagged in the spec).

- [ ] **Step 6: Run rubocop, fix any resulting style issues**

  ```bash
  bundle exec rubocop
  ```

  Expected: green.

- [ ] **Step 7: Commit**

  ```bash
  git add Gemfile Gemfile.lock spec/spec_helper.rb .gitignore
  git commit -m "chore(quality): add SimpleCov, RubyCritic, Flog, Mutant dev dependencies"
  ```

---

## Task 2: Enable Rubocop Metrics cops with our thresholds

**Files:**
- Modify: `.rubocop.yml`

- [ ] **Step 1: Replace `.rubocop.yml` contents**

  The file currently only inherits `rubocop-rails-omakase`. Extend it to re-enable the Metrics cops we gate on. Full new contents:

  ```yaml
  # Omakase Ruby styling for Rails
  inherit_gem: { rubocop-rails-omakase: rubocop.yml }

  # --- Code-quality gates (aspirational thresholds) ---
  Metrics/ClassLength:
    Enabled: true
    Max: 100
    Exclude:
      - 'spec/**/*'
      - 'db/**/*'

  Metrics/ModuleLength:
    Enabled: true
    Max: 100
    Exclude:
      - 'spec/**/*'

  Metrics/MethodLength:
    Enabled: true
    Max: 10
    Exclude:
      - 'db/migrate/**/*'

  Metrics/AbcSize:
    Enabled: true
    Max: 15
    Exclude:
      - 'db/migrate/**/*'

  Metrics/CyclomaticComplexity:
    Enabled: true
    Max: 6

  Metrics/PerceivedComplexity:
    Enabled: true
    Max: 7

  # Don't gate block length — DSLs and rake tasks are legitimately long
  Metrics/BlockLength:
    Exclude:
      - 'config/**/*'
      - 'spec/**/*'
      - 'lib/tasks/**/*'
  ```

- [ ] **Step 2: Run Rubocop to see current violations**

  ```bash
  bundle exec rubocop --only Metrics
  ```

  Expected: may report violations in `app/` code. Do **not** auto-fix — the point of this step is to establish which app code violates aspirational gates.

- [ ] **Step 3: Decide per-violation: refactor vs. annotate**

  For each reported violation:
  - **If in production code (`app/`):** refactor. This is the aspirational cleanup the spec committed to. Extract a method, extract a service, split a class — whichever fits the Rails conventions the project already uses (`CLAUDE.md` says: controllers stay slim, extract services for complex logic).
  - **If in migration or auto-generated code you can't reasonably change:** already excluded above. If something slipped through, add to `Exclude:`.

  **Do not** add `# rubocop:disable` inline pragmas to skip the gate — that defeats the purpose.

- [ ] **Step 4: After refactoring, rerun Rubocop**

  ```bash
  bundle exec rubocop
  ```

  Expected: green.

- [ ] **Step 5: Rerun the spec suite to make sure refactors didn't break behaviour**

  ```bash
  bin/rspec
  ```

  Expected: green.

- [ ] **Step 6: Commit**

  ```bash
  git add .rubocop.yml app/
  git commit -m "chore(quality): enable Rubocop Metrics cops with aspirational thresholds"
  ```

  (If no `app/` files needed changes, only `.rubocop.yml` is staged.)

---

## Task 3: Create `config/quality_thresholds.yml`

**Files:**
- Create: `config/quality_thresholds.yml`

- [ ] **Step 1: Write the file**

  Exact contents:

  ```yaml
  # Quality gate thresholds — see docs/superpowers/specs/2026-04-21-code-quality-metrics-design.md
  #
  # `mutation.kill_ratio_min` is intentionally null on initial setup. The first
  # `bin/rake quality:mutation` run records the observed ratio into this file;
  # subsequent runs fail if the ratio drops below that floor.

  coverage:
    line_min: 95.0
    branch_min: 90.0

  flog:
    method_max: 15
    class_max: 40

  rubocop_metrics:
    class_length_max: 100
    method_length_max: 10
    abc_size_max: 15
    cyclomatic_complexity_max: 6
    perceived_complexity_max: 7

  mutation:
    kill_ratio_min: null
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add config/quality_thresholds.yml
  git commit -m "chore(quality): add threshold configuration"
  ```

---

## Task 4: Scaffold `lib/quality` module + shared result struct

**Files:**
- Create: `lib/quality.rb`
- Create: `lib/quality/gate_result.rb`
- Create: `spec/lib/quality/gate_result_spec.rb`

- [ ] **Step 1: Write the failing test**

  Create `spec/lib/quality/gate_result_spec.rb`:

  ```ruby
  require "rails_helper"
  require "quality/gate_result"

  RSpec.describe Quality::GateResult do
    it "is passing when measured value respects the comparator" do
      result = described_class.new(
        name: "Line coverage",
        measured: 96.2,
        threshold: 95.0,
        comparator: :>=,
        unit: "%"
      )

      expect(result.passed?).to be true
      expect(result.to_row).to eq("Line coverage             96.2%   >= 95.0%     ✓")
    end

    it "is failing when measured value violates the comparator" do
      result = described_class.new(
        name: "Flog max method",
        measured: 22,
        threshold: 15,
        comparator: :<=,
        unit: ""
      )

      expect(result.passed?).to be false
      expect(result.to_row).to eq("Flog max method           22      <= 15        ✗")
    end

    it "marks the threshold unset when the threshold is nil" do
      result = described_class.new(
        name: "Mutation kill ratio",
        measured: 88.0,
        threshold: nil,
        comparator: :>=,
        unit: "%"
      )

      expect(result.passed?).to be true
      expect(result.to_row).to eq("Mutation kill ratio       88.0%   (unset)      — [ratchet pending]")
    end
  end
  ```

- [ ] **Step 2: Run the test; verify it fails with LoadError**

  ```bash
  bin/rspec spec/lib/quality/gate_result_spec.rb
  ```

  Expected: `cannot load such file -- quality/gate_result`.

- [ ] **Step 3: Make `lib/` autoload for specs**

  Verify `spec/rails_helper.rb` loads `lib/`. Rails 8 autoloads `lib/` only if `config.autoload_lib` is set. Check `config/application.rb`:

  ```bash
  grep -n "autoload_lib\|eager_load_paths" config/application.rb
  ```

  If `config.autoload_lib(ignore: %w[assets tasks])` (or similar) is present, Rails will autoload `lib/quality/*`. If not, add this line to `spec/rails_helper.rb` after the `require_relative '../config/environment'` line:

  ```ruby
  $LOAD_PATH.unshift(Rails.root.join("lib").to_s)
  ```

- [ ] **Step 4: Implement `lib/quality/gate_result.rb`**

  ```ruby
  module Quality
    class GateResult
      attr_reader :name, :measured, :threshold, :comparator, :unit

      def initialize(name:, measured:, threshold:, comparator:, unit: "")
        @name = name
        @measured = measured
        @threshold = threshold
        @comparator = comparator
        @unit = unit
      end

      def passed?
        return true if threshold.nil?

        measured.public_send(comparator, threshold)
      end

      def to_row
        name_col = name.ljust(25)
        measured_col = format_value(measured).ljust(8)

        if threshold.nil?
          "#{name_col}#{measured_col}(unset)      — [ratchet pending]"
        else
          threshold_col = "#{comparator_symbol} #{format_value(threshold)}".ljust(12)
          status = passed? ? "✓" : "✗"
          "#{name_col}#{measured_col}#{threshold_col}#{status}"
        end
      end

      private

      def format_value(value)
        value.is_a?(Float) ? "#{format('%.1f', value)}#{unit}" : "#{value}#{unit}"
      end

      def comparator_symbol
        { :>= => ">=", :<= => "<=", :> => ">", :< => "<" }.fetch(comparator)
      end
    end
  end
  ```

- [ ] **Step 5: Create the umbrella module file**

  `lib/quality.rb`:

  ```ruby
  module Quality
  end
  ```

- [ ] **Step 6: Run the test; verify it passes**

  ```bash
  bin/rspec spec/lib/quality/gate_result_spec.rb
  ```

  Expected: 3 examples, 0 failures. If the whitespace in the string expectations trips you up, adjust the formatting inside `to_row` to match the spec — the spec pins the exact column widths. Rubocop may also complain about line length; if so, split `to_row` into helper methods to satisfy `Metrics/MethodLength`.

- [ ] **Step 7: Run rubocop**

  ```bash
  bundle exec rubocop lib/quality/ spec/lib/quality/
  ```

  Expected: green.

- [ ] **Step 8: Commit**

  ```bash
  git add lib/quality.rb lib/quality/gate_result.rb spec/lib/quality/gate_result_spec.rb spec/rails_helper.rb
  git commit -m "feat(quality): add GateResult value object with formatted row output"
  ```

---

## Task 5: CoverageParser (SimpleCov `last_run.json`)

**Files:**
- Create: `lib/quality/coverage_parser.rb`
- Create: `spec/lib/quality/coverage_parser_spec.rb`
- Create: `spec/fixtures/quality/coverage_last_run.json`

- [ ] **Step 1: Create the fixture**

  `spec/fixtures/quality/coverage_last_run.json`:

  ```json
  {"result":{"line":96.25,"branch":90.5}}
  ```

- [ ] **Step 2: Write the failing test**

  `spec/lib/quality/coverage_parser_spec.rb`:

  ```ruby
  require "rails_helper"
  require "quality/coverage_parser"

  RSpec.describe Quality::CoverageParser do
    let(:fixture) { Rails.root.join("spec/fixtures/quality/coverage_last_run.json") }

    it "reads line and branch coverage from SimpleCov's last_run.json" do
      parsed = described_class.new(fixture).parse

      expect(parsed).to eq(line: 96.25, branch: 90.5)
    end

    it "returns nil for branch coverage when SimpleCov didn't record it" do
      tmp = Tempfile.new(["last_run", ".json"])
      tmp.write('{"result":{"line":88.0}}')
      tmp.close

      parsed = described_class.new(tmp.path).parse

      expect(parsed).to eq(line: 88.0, branch: nil)
    ensure
      tmp&.unlink
    end
  end
  ```

- [ ] **Step 3: Run the test; verify it fails**

  ```bash
  bin/rspec spec/lib/quality/coverage_parser_spec.rb
  ```

  Expected: LoadError for `quality/coverage_parser`.

- [ ] **Step 4: Implement the parser**

  `lib/quality/coverage_parser.rb`:

  ```ruby
  require "json"

  module Quality
    class CoverageParser
      def initialize(path)
        @path = path
      end

      def parse
        data = JSON.parse(File.read(@path))
        result = data.fetch("result")
        { line: result["line"], branch: result["branch"] }
      end
    end
  end
  ```

- [ ] **Step 5: Run the test; verify it passes**

  ```bash
  bin/rspec spec/lib/quality/coverage_parser_spec.rb
  ```

  Expected: 2 examples, 0 failures.

- [ ] **Step 6: Run rubocop**

  ```bash
  bundle exec rubocop lib/quality/ spec/lib/quality/
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add lib/quality/coverage_parser.rb spec/lib/quality/coverage_parser_spec.rb spec/fixtures/quality/coverage_last_run.json
  git commit -m "feat(quality): parse SimpleCov last_run.json for line and branch coverage"
  ```

---

## Task 6: RubocopParser (JSON output)

**Files:**
- Create: `lib/quality/rubocop_parser.rb`
- Create: `spec/lib/quality/rubocop_parser_spec.rb`
- Create: `spec/fixtures/quality/rubocop.json`

- [ ] **Step 1: Create the fixture**

  `spec/fixtures/quality/rubocop.json`:

  ```json
  {
    "metadata": { "rubocop_version": "1.60.0" },
    "files": [
      {
        "path": "app/models/user.rb",
        "offenses": [
          {
            "cop_name": "Metrics/ClassLength",
            "message": "Class has too many lines. [143/100]",
            "location": {}
          },
          {
            "cop_name": "Metrics/MethodLength",
            "message": "Method has too many lines. [14/10]",
            "location": {}
          }
        ]
      },
      {
        "path": "app/services/topic_index_props.rb",
        "offenses": [
          {
            "cop_name": "Metrics/AbcSize",
            "message": "Assignment Branch Condition size for call is too high. [<7, 18, 3> 19.55/15]",
            "location": {}
          }
        ]
      }
    ],
    "summary": {}
  }
  ```

- [ ] **Step 2: Write the failing test**

  `spec/lib/quality/rubocop_parser_spec.rb`:

  ```ruby
  require "rails_helper"
  require "quality/rubocop_parser"

  RSpec.describe Quality::RubocopParser do
    let(:fixture) { Rails.root.join("spec/fixtures/quality/rubocop.json") }

    it "returns the max measured value per Metrics cop" do
      parsed = described_class.new(fixture).parse

      expect(parsed[:class_length_max]).to eq(143)
      expect(parsed[:method_length_max]).to eq(14)
      expect(parsed[:abc_size_max]).to eq(19.55)
      expect(parsed[:cyclomatic_complexity_max]).to be_nil
      expect(parsed[:perceived_complexity_max]).to be_nil
    end

    it "returns nil for a cop with no reported offenses (passing)" do
      empty_file = Tempfile.new(["rubocop", ".json"])
      empty_file.write('{"files":[],"summary":{}}')
      empty_file.close

      parsed = described_class.new(empty_file.path).parse

      expect(parsed[:class_length_max]).to be_nil
    ensure
      empty_file&.unlink
    end
  end
  ```

- [ ] **Step 3: Run the test; verify it fails**

  ```bash
  bin/rspec spec/lib/quality/rubocop_parser_spec.rb
  ```

  Expected: LoadError.

- [ ] **Step 4: Implement the parser**

  `lib/quality/rubocop_parser.rb`:

  ```ruby
  require "json"

  module Quality
    class RubocopParser
      COPS = {
        class_length_max: "Metrics/ClassLength",
        method_length_max: "Metrics/MethodLength",
        abc_size_max: "Metrics/AbcSize",
        cyclomatic_complexity_max: "Metrics/CyclomaticComplexity",
        perceived_complexity_max: "Metrics/PerceivedComplexity"
      }.freeze

      # Regex captures the first "<measured>/<max>" pair in the offense message.
      # Handles both "[143/100]" and "[<7, 18, 3> 19.55/15]" shapes.
      MEASURE_RE = %r{([\d.]+)/[\d.]+}

      def initialize(path)
        @path = path
      end

      def parse
        offenses = JSON.parse(File.read(@path)).fetch("files").flat_map { |f| f["offenses"] }

        COPS.transform_values do |cop_name|
          max_for(cop_name, offenses)
        end
      end

      private

      def max_for(cop_name, offenses)
        values = offenses
          .select { |o| o["cop_name"] == cop_name }
          .map { |o| o["message"][MEASURE_RE, 1]&.to_f }
          .compact

        return nil if values.empty?

        picked = values.max
        picked == picked.to_i ? picked.to_i : picked
      end
    end
  end
  ```

- [ ] **Step 5: Run the test; verify it passes**

  ```bash
  bin/rspec spec/lib/quality/rubocop_parser_spec.rb
  ```

  Expected: 2 examples, 0 failures.

- [ ] **Step 6: Run rubocop**

  ```bash
  bundle exec rubocop lib/quality/ spec/lib/quality/
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add lib/quality/rubocop_parser.rb spec/lib/quality/rubocop_parser_spec.rb spec/fixtures/quality/rubocop.json
  git commit -m "feat(quality): parse Rubocop JSON for Metrics cop max values"
  ```

---

## Task 7: FlogParser (programmatic Flog API)

**Files:**
- Create: `lib/quality/flog_parser.rb`
- Create: `spec/lib/quality/flog_parser_spec.rb`
- Create: `spec/fixtures/quality/flog_sample.rb`

- [ ] **Step 1: Create a deterministic Ruby fixture Flog can analyse**

  `spec/fixtures/quality/flog_sample.rb`:

  ```ruby
  class Simple
    def trivial
      42
    end
  end

  class Branchy
    def heavy(a, b, c)
      if a && b
        c.each do |item|
          item.tap do |i|
            i.save! if i.valid? && i.fresh?
          end
        end
      else
        raise ArgumentError
      end
    end
  end
  ```

  (`Branchy#heavy` flogs ~10+ via ABC; `Simple#trivial` flogs ~1. Exact numbers aren't asserted; we compare relative max.)

- [ ] **Step 2: Write the failing test**

  `spec/lib/quality/flog_parser_spec.rb`:

  ```ruby
  require "rails_helper"
  require "quality/flog_parser"

  RSpec.describe Quality::FlogParser do
    let(:fixture) { Rails.root.join("spec/fixtures/quality/flog_sample.rb") }

    it "returns max flog score per method and per class for a path" do
      parsed = described_class.new([fixture.to_s]).parse

      expect(parsed[:method_max]).to be > 5.0
      expect(parsed[:class_max]).to be > parsed[:method_max]
    end

    it "returns zeros when the target path has no Ruby code" do
      empty = Tempfile.new(["empty", ".rb"])
      empty.close

      parsed = described_class.new([empty.path]).parse

      expect(parsed).to eq(method_max: 0.0, class_max: 0.0)
    ensure
      empty&.unlink
    end
  end
  ```

- [ ] **Step 3: Run the test; verify it fails**

  ```bash
  bin/rspec spec/lib/quality/flog_parser_spec.rb
  ```

  Expected: LoadError.

- [ ] **Step 4: Implement the parser**

  `lib/quality/flog_parser.rb`:

  ```ruby
  require "flog"

  module Quality
    class FlogParser
      def initialize(paths)
        @paths = Array(paths)
      end

      def parse
        flog = Flog.new
        @paths.each { |path| flog.flog(path) }

        method_scores = flog.totals.reject { |name, _| name.end_with?("#none") || class_key?(name) }
        class_scores  = flog.totals.select { |name, _| class_key?(name) }

        {
          method_max: method_scores.values.max || 0.0,
          class_max:  class_scores.values.max  || 0.0
        }
      end

      private

      # Flog keys class-level scores as "Klass#none" or just "Klass".
      # Method keys look like "Klass#method" or "Klass::singleton".
      def class_key?(name)
        !name.include?("#") && !name.include?("::")
      end
    end
  end
  ```

  **Implementation note:** Flog's totals hash semantics are slightly version-dependent — in some versions class-level scores appear as `"Klass#none"`, in others as `"Klass"` with no separator. If the spec's first assertion (`class_max > method_max`) fails, inspect `flog.totals` interactively (`bin/rails runner 'require "flog"; f = Flog.new; f.flog("spec/fixtures/quality/flog_sample.rb"); pp f.totals'`) and adjust the `class_key?` predicate to match actual keys. Do not ship a parser you haven't verified against real Flog output.

- [ ] **Step 5: Run the test; verify it passes**

  ```bash
  bin/rspec spec/lib/quality/flog_parser_spec.rb
  ```

  Expected: 2 examples, 0 failures. If it fails, apply the implementation note above.

- [ ] **Step 6: Run rubocop**

  ```bash
  bundle exec rubocop lib/quality/ spec/lib/quality/
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add lib/quality/flog_parser.rb spec/lib/quality/flog_parser_spec.rb spec/fixtures/quality/flog_sample.rb
  git commit -m "feat(quality): parse Flog scores for max method and class complexity"
  ```

---

## Task 8: MutantParser (kill ratio from Mutant output)

**Files:**
- Create: `lib/quality/mutant_parser.rb`
- Create: `spec/lib/quality/mutant_parser_spec.rb`
- Create: `spec/fixtures/quality/mutant_output.txt`

- [ ] **Step 1: Create the fixture**

  `spec/fixtures/quality/mutant_output.txt` — a representative Mutant summary block:

  ```
  Mutant configuration:
  - Matcher:         #<Mutant::Matcher::Config ...>
  - Integration:     rspec
  Subjects:          12
  Mutations:         240
  Results:           240
  Kills:             218
  Alive:             22
  Runtime:           96.27s
  Killtime:          212.81s
  Overhead:          -55.76%
  Mutations/s:       2.49
  Coverage:          90.83%
  ```

- [ ] **Step 2: Write the failing test**

  `spec/lib/quality/mutant_parser_spec.rb`:

  ```ruby
  require "rails_helper"
  require "quality/mutant_parser"

  RSpec.describe Quality::MutantParser do
    let(:fixture) { Rails.root.join("spec/fixtures/quality/mutant_output.txt") }

    it "extracts the kill ratio as a float percentage" do
      parsed = described_class.new(fixture).parse

      expect(parsed[:kill_ratio]).to eq(90.83)
      expect(parsed[:mutations]).to eq(240)
      expect(parsed[:kills]).to eq(218)
    end

    it "raises a clear error when the summary block isn't found" do
      garbage = Tempfile.new(["mutant", ".txt"])
      garbage.write("nothing to see here\n")
      garbage.close

      expect { described_class.new(garbage.path).parse }.to raise_error(Quality::MutantParser::ParseError)
    ensure
      garbage&.unlink
    end
  end
  ```

- [ ] **Step 3: Run the test; verify it fails**

  ```bash
  bin/rspec spec/lib/quality/mutant_parser_spec.rb
  ```

  Expected: LoadError.

- [ ] **Step 4: Implement the parser**

  `lib/quality/mutant_parser.rb`:

  ```ruby
  module Quality
    class MutantParser
      class ParseError < StandardError; end

      PATTERNS = {
        mutations: /^Mutations:\s+(\d+)$/,
        kills:     /^Kills:\s+(\d+)$/,
        coverage:  /^Coverage:\s+([\d.]+)%$/
      }.freeze

      def initialize(path)
        @path = path
      end

      def parse
        text = File.read(@path)
        extracted = PATTERNS.transform_values do |re|
          match = text.match(re)
          match && match[1]
        end

        if extracted[:coverage].nil?
          raise ParseError, "Could not find Coverage line in mutant output at #{@path}"
        end

        {
          mutations: extracted[:mutations].to_i,
          kills:     extracted[:kills].to_i,
          kill_ratio: extracted[:coverage].to_f
        }
      end
    end
  end
  ```

- [ ] **Step 5: Run the test; verify it passes**

  ```bash
  bin/rspec spec/lib/quality/mutant_parser_spec.rb
  ```

  Expected: 2 examples, 0 failures.

- [ ] **Step 6: Run rubocop**

  ```bash
  bundle exec rubocop lib/quality/ spec/lib/quality/
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add lib/quality/mutant_parser.rb spec/lib/quality/mutant_parser_spec.rb spec/fixtures/quality/mutant_output.txt
  git commit -m "feat(quality): parse Mutant kill ratio from summary output"
  ```

---

## Task 9: Report aggregator (threshold comparison + formatted output)

**Files:**
- Create: `lib/quality/report.rb`
- Create: `spec/lib/quality/report_spec.rb`

- [ ] **Step 1: Write the failing test**

  `spec/lib/quality/report_spec.rb`:

  ```ruby
  require "rails_helper"
  require "quality/report"

  RSpec.describe Quality::Report do
    let(:passing_measurements) do
      {
        coverage:       { line: 96.2, branch: 91.4 },
        rubocop:        { class_length_max: 87, method_length_max: 9, abc_size_max: 13, cyclomatic_complexity_max: 5, perceived_complexity_max: 6 },
        flog:           { method_max: 12.0, class_max: 38.0 },
        mutation:       { kill_ratio: 92.1 }
      }
    end

    let(:thresholds) do
      {
        "coverage"        => { "line_min" => 95.0, "branch_min" => 90.0 },
        "flog"            => { "method_max" => 15, "class_max" => 40 },
        "rubocop_metrics" => { "class_length_max" => 100, "method_length_max" => 10, "abc_size_max" => 15, "cyclomatic_complexity_max" => 6, "perceived_complexity_max" => 7 },
        "mutation"        => { "kill_ratio_min" => 92.0 }
      }
    end

    it "passes when every measurement respects its threshold" do
      report = described_class.new(measurements: passing_measurements, thresholds: thresholds)

      expect(report.passed?).to be true
      expect(report.gate_results.count(&:passed?)).to eq(report.gate_results.size)
    end

    it "fails when any single measurement breaches its threshold" do
      bad = passing_measurements.deep_dup
      bad[:rubocop][:class_length_max] = 142

      report = described_class.new(measurements: bad, thresholds: thresholds)

      expect(report.passed?).to be false
      failing = report.gate_results.reject(&:passed?)
      expect(failing.map(&:name)).to eq(["Class length max"])
    end

    it "treats the ratcheted mutation threshold as passing when still unset" do
      open_thresholds = thresholds.deep_dup
      open_thresholds["mutation"]["kill_ratio_min"] = nil

      report = described_class.new(measurements: passing_measurements, thresholds: open_thresholds)

      expect(report.passed?).to be true
      mutation_row = report.gate_results.find { |r| r.name == "Mutation kill ratio" }
      expect(mutation_row.to_row).to include("(unset)")
    end

    it "renders a human-readable multi-line summary" do
      report = described_class.new(measurements: passing_measurements, thresholds: thresholds)

      output = report.to_s

      expect(output).to include("Quality gates")
      expect(output).to include("Line coverage")
      expect(output).to include("#{report.gate_results.size}/#{report.gate_results.size} gates passed")
    end
  end
  ```

- [ ] **Step 2: Run the test; verify it fails**

  ```bash
  bin/rspec spec/lib/quality/report_spec.rb
  ```

  Expected: LoadError.

- [ ] **Step 3: Implement the aggregator**

  `lib/quality/report.rb`:

  ```ruby
  require "quality/gate_result"

  module Quality
    class Report
      GATE_DEFINITIONS = [
        { name: "Line coverage",           measurement: [:coverage, :line],                       threshold: ["coverage", "line_min"],                     comparator: :>=, unit: "%" },
        { name: "Branch coverage",         measurement: [:coverage, :branch],                     threshold: ["coverage", "branch_min"],                   comparator: :>=, unit: "%" },
        { name: "Flog max (method)",       measurement: [:flog, :method_max],                     threshold: ["flog", "method_max"],                       comparator: :<=, unit: "" },
        { name: "Flog max (class)",        measurement: [:flog, :class_max],                      threshold: ["flog", "class_max"],                        comparator: :<=, unit: "" },
        { name: "Class length max",        measurement: [:rubocop, :class_length_max],            threshold: ["rubocop_metrics", "class_length_max"],      comparator: :<=, unit: "" },
        { name: "Method length max",       measurement: [:rubocop, :method_length_max],           threshold: ["rubocop_metrics", "method_length_max"],     comparator: :<=, unit: "" },
        { name: "AbcSize max",             measurement: [:rubocop, :abc_size_max],                threshold: ["rubocop_metrics", "abc_size_max"],          comparator: :<=, unit: "" },
        { name: "CyclomaticComplexity max", measurement: [:rubocop, :cyclomatic_complexity_max],  threshold: ["rubocop_metrics", "cyclomatic_complexity_max"], comparator: :<=, unit: "" },
        { name: "Mutation kill ratio",     measurement: [:mutation, :kill_ratio],                 threshold: ["mutation", "kill_ratio_min"],               comparator: :>=, unit: "%" }
      ].freeze

      attr_reader :gate_results

      def initialize(measurements:, thresholds:)
        @measurements = measurements
        @thresholds = thresholds
        @gate_results = build_gate_results
      end

      def passed?
        gate_results.all?(&:passed?)
      end

      def to_s
        lines = ["Quality gates", "=" * 13, ""]
        lines.concat(gate_results.map(&:to_row))
        lines << ""
        passed_count = gate_results.count(&:passed?)
        lines << "#{passed_count}/#{gate_results.size} gates passed."
        lines.join("\n")
      end

      private

      def build_gate_results
        GATE_DEFINITIONS.filter_map do |gate|
          measured = @measurements.dig(*gate[:measurement])
          next if measured.nil?

          GateResult.new(
            name: gate[:name],
            measured: measured,
            threshold: @thresholds.dig(*gate[:threshold]),
            comparator: gate[:comparator],
            unit: gate[:unit]
          )
        end
      end
    end
  end
  ```

- [ ] **Step 4: Run the test; verify it passes**

  ```bash
  bin/rspec spec/lib/quality/report_spec.rb
  ```

  Expected: 4 examples, 0 failures. If rubocop flags `Metrics/ClassLength` on the `GATE_DEFINITIONS` array itself (it shouldn't — data doesn't count as class length), extract the array into a constant file under `lib/quality/gate_definitions.rb`.

- [ ] **Step 5: Run rubocop**

  ```bash
  bundle exec rubocop lib/quality/ spec/lib/quality/
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add lib/quality/report.rb spec/lib/quality/report_spec.rb
  git commit -m "feat(quality): aggregate measurements into pass/fail gate report"
  ```

---

## Task 10: Coverage + Rubocop rake sub-tasks

**Files:**
- Create: `lib/tasks/quality.rake`

- [ ] **Step 1: Create the rake file with the first two sub-tasks**

  `lib/tasks/quality.rake`:

  ```ruby
  require "fileutils"
  require "json"

  QUALITY_DIR = Rails.root.join("tmp/quality")

  namespace :quality do
    desc "Run rspec with SimpleCov; fail if coverage/.last_run.json isn't produced"
    task :coverage do
      FileUtils.mkdir_p(QUALITY_DIR)
      sh "bin/rspec"
      last_run = Rails.root.join("coverage/.last_run.json")
      raise "coverage/.last_run.json missing after bin/rspec" unless last_run.exist?

      FileUtils.cp(last_run, QUALITY_DIR.join("coverage.json"))
    end

    desc "Run rubocop on the codebase, write JSON to tmp/quality/rubocop.json"
    task :rubocop do
      FileUtils.mkdir_p(QUALITY_DIR)
      out_path = QUALITY_DIR.join("rubocop.json")
      # --format json writes to stdout; capture without failing the task on offenses
      result = %x{bundle exec rubocop --format json --no-color --only Metrics}
      File.write(out_path, result)
      # Rubocop exits non-zero on offenses — don't fail here; quality:report is the gate.
    end
  end
  ```

  **Note:** `sh` (rake's helper) fails the task if the subshell exits non-zero. For `quality:rubocop` we explicitly use `%x{}` so a Rubocop offense doesn't abort the pipeline — the gate is decided by `quality:report`, not by Rubocop's exit code.

- [ ] **Step 2: Smoke-test the two tasks**

  ```bash
  bin/rake quality:coverage
  ls tmp/quality/coverage.json
  bin/rake quality:rubocop
  ls tmp/quality/rubocop.json
  ```

  Expected: both files exist; the specs run as part of `quality:coverage`.

- [ ] **Step 3: Run rubocop on the rake file**

  ```bash
  bundle exec rubocop lib/tasks/quality.rake
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add lib/tasks/quality.rake
  git commit -m "feat(quality): add coverage and rubocop rake sub-tasks"
  ```

---

## Task 11: RubyCritic + Flog rake sub-tasks

**Files:**
- Modify: `lib/tasks/quality.rake`

- [ ] **Step 1: Add `quality:critic` task**

  Append inside the existing `namespace :quality do` block:

  ```ruby
    desc "Run RubyCritic; emit HTML dashboard and JSON report under tmp/quality/"
    task :critic do
      FileUtils.mkdir_p(QUALITY_DIR)
      sh "bundle exec rubycritic --no-browser --format json --format html " \
         "--path #{QUALITY_DIR} app"
      # RubyCritic writes tmp/quality/report.json and tmp/quality/overview.html
    end

    desc "Run Flog against app/; write JSON with max per-method and per-class scores"
    task :flog do
      require "quality/flog_parser"
      FileUtils.mkdir_p(QUALITY_DIR)
      paths = Dir[Rails.root.join("app/**/*.rb").to_s]
      result = Quality::FlogParser.new(paths).parse
      File.write(QUALITY_DIR.join("flog.json"), JSON.pretty_generate(result))
    end
  ```

- [ ] **Step 2: Smoke-test**

  ```bash
  bin/rake quality:critic
  ls tmp/quality/overview.html
  bin/rake quality:flog
  cat tmp/quality/flog.json
  ```

  Expected: HTML dashboard opens readably in a browser; flog.json contains `{"method_max": ..., "class_max": ...}`.

  **Note:** If RubyCritic's `--path` flag for JSON output isn't honored by the installed version (older versions default to `tmp/rubycritic/`), adjust: either move the generated files into `tmp/quality/` explicitly with `FileUtils.mv`, or accept the default and update the report task to read from `tmp/rubycritic/report.json`. We don't parse RubyCritic's JSON for gating, so only the HTML path matters for downstream tasks.

- [ ] **Step 3: Run rubocop**

  ```bash
  bundle exec rubocop lib/tasks/quality.rake
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add lib/tasks/quality.rake
  git commit -m "feat(quality): add rubycritic and flog rake sub-tasks"
  ```

---

## Task 12: Mutant rake sub-task with ratchet handling

**Files:**
- Create: `.mutant.yml`
- Modify: `lib/tasks/quality.rake`

- [ ] **Step 1: Create Mutant config**

  `.mutant.yml`:

  ```yaml
  integration:
    name: rspec
  includes:
    - app
  requires:
    - ./config/environment
  matcher:
    subjects:
      - "*"
  ```

- [ ] **Step 2: Add `quality:mutation` rake task**

  Append to `lib/tasks/quality.rake` (inside the namespace):

  ```ruby
    desc "Run Mutant against app/; parse kill ratio; ratchet threshold on first run"
    task :mutation do
      require "quality/mutant_parser"
      require "yaml"
      FileUtils.mkdir_p(QUALITY_DIR)

      txt_path = QUALITY_DIR.join("mutation.txt")
      subjects = %w[
        app/models/**/*.rb
        app/services/**/*.rb
        app/controllers/**/*.rb
        app/jobs/**/*.rb
      ].flat_map { |glob| Dir[Rails.root.join(glob).to_s] }

      cmd = [
        "bundle", "exec", "mutant", "run",
        "--use", "rspec",
        "--include", "app",
        "--require", "./config/environment",
        *subjects.map { |p| "--match-expression=#{expression_for(p)}" }
      ].compact

      system({ "MUTANT_JOBS" => "4" }, *cmd, out: txt_path.to_s, err: [:child, :out])
      # Don't fail the task on non-zero; parse the output to decide the gate.

      parsed = Quality::MutantParser.new(txt_path).parse
      File.write(QUALITY_DIR.join("mutation.json"), JSON.pretty_generate(parsed))

      ratchet_if_unset!(parsed[:kill_ratio])
    end

    def expression_for(path)
      # Convert "app/models/user.rb" -> "User*" so mutant matches the constant.
      constant = File.basename(path, ".rb").camelize
      "#{constant}*"
    end

    def ratchet_if_unset!(kill_ratio)
      thresholds_path = Rails.root.join("config/quality_thresholds.yml")
      thresholds = YAML.load_file(thresholds_path)

      return unless thresholds.dig("mutation", "kill_ratio_min").nil?

      thresholds["mutation"]["kill_ratio_min"] = kill_ratio
      File.write(thresholds_path, thresholds.to_yaml)
      puts "[quality:mutation] Ratchet set: mutation.kill_ratio_min = #{kill_ratio}"
    end
  ```

  **Note on match expressions:** Mutant matches by Ruby constant, not by file path. `expression_for` converts file paths into a rough constant match. If the app uses namespaced models (e.g. `Admin::UsersController`), adjust the helper to honour directory structure: `"app/controllers/admin/users_controller.rb"` → `"Admin::UsersController*"`. Verify on the first run.

  **Simplest alternative if expression mapping proves fiddly:** replace the `--match-expression` block with a single `"--match-expression", "*"` and scope via `.mutant.yml`'s `matcher.subjects` instead. Pick whichever works on the first real run.

- [ ] **Step 3: Smoke-test (expect ratchet to be written)**

  ```bash
  bin/rake quality:mutation
  cat config/quality_thresholds.yml | grep kill_ratio_min
  cat tmp/quality/mutation.json
  ```

  Expected: `kill_ratio_min` is now a number (the first-run value); `mutation.json` contains the parsed summary.

  **If Mutant runtime exceeds 10 minutes on the full app:** drop `quality:mutation` from the default `quality` meta-task (Task 13) and document in CLAUDE.md that it's a separate pre-commit step. The spec flags this as a known contingency.

- [ ] **Step 4: Run rubocop**

  ```bash
  bundle exec rubocop lib/tasks/quality.rake .mutant.yml
  ```

  (Rubocop will skip the YAML file.)

- [ ] **Step 5: Commit**

  ```bash
  git add lib/tasks/quality.rake .mutant.yml config/quality_thresholds.yml
  git commit -m "feat(quality): add Mutant rake task with first-run ratchet"
  ```

---

## Task 13: `quality:report` aggregator task + top-level `quality` task

**Files:**
- Modify: `lib/tasks/quality.rake`

- [ ] **Step 1: Append `quality:report` to the rake file**

  ```ruby
    desc "Aggregate all measurements; print summary table; exit 0 on pass, 1 on fail"
    task :report do
      require "quality/coverage_parser"
      require "quality/rubocop_parser"
      require "quality/report"
      require "yaml"

      measurements = {
        coverage: Quality::CoverageParser.new(QUALITY_DIR.join("coverage.json")).parse,
        rubocop:  Quality::RubocopParser.new(QUALITY_DIR.join("rubocop.json")).parse,
        flog:     JSON.parse(File.read(QUALITY_DIR.join("flog.json")), symbolize_names: true),
        mutation: JSON.parse(File.read(QUALITY_DIR.join("mutation.json")), symbolize_names: true)
      }

      thresholds = YAML.load_file(Rails.root.join("config/quality_thresholds.yml"))

      report = Quality::Report.new(measurements: measurements, thresholds: thresholds)
      puts report.to_s
      puts ""
      puts "Detailed reports:"
      puts "  #{QUALITY_DIR.join('overview.html')}    (RubyCritic)"
      puts "  #{Rails.root.join('coverage/index.html')}       (SimpleCov)"
      puts "  #{QUALITY_DIR.join('mutation.txt')}       (Mutant)"

      exit(report.passed? ? 0 : 1)
    end
  end
  ```

- [ ] **Step 2: Add top-level `quality` task (outside the namespace, at end of file)**

  ```ruby
  desc "Run all quality gates: coverage, rubocop, flog, rubycritic, mutation, report"
  task quality: %w[
    quality:coverage
    quality:rubocop
    quality:critic
    quality:flog
    quality:mutation
    quality:report
  ]
  ```

- [ ] **Step 3: End-to-end test**

  ```bash
  bin/rake quality
  echo "Exit: $?"
  ```

  Expected: table printed, summary shows `N/N gates passed`, exit 0 on green.

  **If any gate is failing:**
  - If it's one of the aspirational gates (coverage / flog / rubocop), this is the cleanup phase promised in the spec. Fix the code, not the threshold. Iterate until green.
  - If it's the mutation gate and this is truly the first run, the ratchet logic should have set the threshold to exactly the observed value, so it should pass. If it doesn't, there's a bug in `ratchet_if_unset!` — debug and fix before moving on.

- [ ] **Step 4: Run rubocop**

  ```bash
  bundle exec rubocop
  ```

- [ ] **Step 5: Commit**

  Commit the rake additions first:

  ```bash
  git add lib/tasks/quality.rake
  git commit -m "feat(quality): add aggregator task and top-level quality command"
  ```

  Then, if cleanup commits were needed to bring current code to green, commit them separately with descriptive messages like `refactor(topic): split TopicIndexProps to satisfy class length gate`. Each cleanup should be its own commit.

---

## Task 14: Add CLAUDE.md instruction

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read current CLAUDE.md**

  ```bash
  cat CLAUDE.md
  ```

- [ ] **Step 2: Add one bullet under `## Project conventions`**

  Insert between the existing "Run tests and the linter after every change" bullet and the end of the list:

  ```markdown
  - **Run the quality gate after every change.** Run `bin/rake quality` alongside `bin/rspec` and `bundle exec rubocop`. Do not claim a task complete if any gate fails. Report the numbers so regressions are visible.
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add CLAUDE.md
  git commit -m "docs: require bin/rake quality after every change"
  ```

---

## Task 15: Final verification pass

**Files:** none (validation only)

- [ ] **Step 1: From a clean working tree, run the full gate**

  ```bash
  git status   # expect clean
  bin/rake quality
  ```

  Expected: all gates pass, exit 0.

- [ ] **Step 2: Verify threshold ratchet persists**

  ```bash
  grep kill_ratio_min config/quality_thresholds.yml
  ```

  Expected: a concrete number, not `null`.

- [ ] **Step 3: Deliberately violate one gate to confirm failure mode**

  Temporarily add a long method to any service or model, e.g. paste 15 lines of no-op code into `app/services/topic_index_props.rb`. Then:

  ```bash
  bin/rake quality
  echo "Exit: $?"
  ```

  Expected: gate breach reported with `✗`, exit code 1. Revert the change before proceeding:

  ```bash
  git checkout app/services/topic_index_props.rb
  ```

- [ ] **Step 4: Verify the full spec suite + rubocop both still green**

  ```bash
  bin/rspec
  bundle exec rubocop
  ```

- [ ] **Step 5: Summarise for the user**

  Report the final gate numbers from the green run so they have the baseline for the blog post. No commit — this task is validation only.

---

## Self-Review Notes

This plan implements every section of the spec:

- ✅ Tool stack (coverage, flog, rubocop, mutant) — Tasks 1, 2, 7, 8
- ✅ Skipping dependency structure — not implemented, noted in spec
- ✅ Rake namespace with 4 sub-tasks + report aggregator — Tasks 10–13
- ✅ Thresholds file — Task 3 (aspirational) + Task 12 (ratchet)
- ✅ Report format with checkmark table — Tasks 4 + 9
- ✅ Mutant config in `.mutant.yml` scoped to `app/` — Task 12
- ✅ Parsers + aggregator are plain Ruby, testable with fixtures — Tasks 5–9
- ✅ Raw output in `tmp/quality/` (gitignored) — Task 1
- ✅ CLAUDE.md bullet — Task 14
- ✅ Final verification — Task 15

Known contingencies from the spec's Open Questions section are flagged inline where relevant (branch coverage support in Task 1; RubyCritic JSON path in Task 11; Mutant runtime and match-expression edge cases in Task 12).
