require "fileutils"
require "json"

QUALITY_DIR = Rails.root.join("tmp/quality")

# Top-level constants Mutant should mutate. Add new models/controllers/services here.
MUTANT_SUBJECTS = %w[
  User* Topic* PushSubscription* TopicSubscription* TopicIndexProps*
  ApplicationController* DashboardController* TopicsController*
  TopicSubscriptionsController* Admin* Quality* TrackingConfig*
  Story* StorySnapshot* Match* Notification* VelocityCalculator*
  KeywordMatcher* Hn* FetchStoryJob* FetchFeedsJob* MatchJob*
  StoryArchiver* StoryFlatlineDetector* Openai* NotifyJob*
  BackfillSubscriptionJob* PruneSnapshotsJob* MatchesController*
].freeze

namespace :quality do
  desc "Run rspec with SimpleCov; copy coverage/.last_run.json into tmp/quality/"
  task :coverage do
    FileUtils.mkdir_p(QUALITY_DIR)
    sh "bin/rspec"
    last_run = Rails.root.join("coverage/.last_run.json")
    raise "coverage/.last_run.json missing after bin/rspec" unless last_run.exist?

    FileUtils.cp(last_run, QUALITY_DIR.join("coverage.json"))
  end

  desc "Run rubocop Metrics cops; capture JSON to tmp/quality/rubocop.json"
  task :rubocop do
    FileUtils.mkdir_p(QUALITY_DIR)
    out_path = QUALITY_DIR.join("rubocop.json")
    # --format json prints to stdout; capture it without aborting on offenses
    # (quality:report is the gate, not rubocop's exit code).
    output = %x(bundle exec rubocop --format json --no-color --only Metrics)
    File.write(out_path, output)
  end

  desc "Run RubyCritic; emit HTML dashboard and JSON report under tmp/quality/"
  task :critic do
    FileUtils.mkdir_p(QUALITY_DIR)
    sh "bundle exec rubycritic --no-browser --format json --format html " \
       "--path #{QUALITY_DIR} app"
  end

  desc "Run Flog against app/; write max method/class scores to tmp/quality/flog.json"
  task flog: :environment do
    FileUtils.mkdir_p(QUALITY_DIR)
    paths = Dir[Rails.root.join("app/**/*.rb").to_s]
    result = Quality::FlogParser.new(paths).parse
    File.write(QUALITY_DIR.join("flog.json"), JSON.pretty_generate(result))
  end

  desc "Run Brakeman; emit JSON to tmp/quality/brakeman.json; ratchet warnings_max on first run"
  task brakeman: :environment do
    FileUtils.mkdir_p(QUALITY_DIR)
    out_path = QUALITY_DIR.join("brakeman.json")
    # Brakeman exits non-zero when warnings exist; we capture output and let the report decide.
    sh "bundle exec brakeman --format json --confidence-level 2 --no-pager " \
       "-o #{out_path.to_s.shellescape} || true"

    parsed = Quality::BrakemanParser.new(out_path).parse
    ratchet_brakeman_if_unset!(parsed[:warnings])
  end

  desc "Aggregate all measurements; print gate table; exit 0 on pass, 1 on fail"
  task report: :environment do
    require "yaml"
    measurements = {
      coverage: Quality::CoverageParser.new(QUALITY_DIR.join("coverage.json")).parse,
      rubocop: Quality::RubocopParser.new(QUALITY_DIR.join("rubocop.json")).parse,
      flog: JSON.parse(File.read(QUALITY_DIR.join("flog.json")), symbolize_names: true),
      brakeman: Quality::BrakemanParser.new(QUALITY_DIR.join("brakeman.json")).parse
    }
    mutation_path = QUALITY_DIR.join("mutation.json")
    if mutation_path.exist?
      measurements[:mutation] = JSON.parse(File.read(mutation_path), symbolize_names: true)
    end

    thresholds = YAML.load_file(Rails.root.join("config/quality_thresholds.yml"))

    report = Quality::Report.new(measurements: measurements, thresholds: thresholds)
    puts report
    puts ""
    puts "Detailed reports:"
    puts "  #{QUALITY_DIR.join('overview.html')}    (RubyCritic)"
    puts "  #{Rails.root.join('coverage/index.html')}       (SimpleCov)"
    puts "  #{QUALITY_DIR.join('mutation.txt')}       (Mutant)"
    puts "  #{QUALITY_DIR.join('brakeman.json')}       (Brakeman)"

    exit(report.passed? ? 0 : 1)
  end

  desc "Run Mutant against app/ and lib/quality; ratchet threshold on first run"
  task mutation: :environment do
    FileUtils.mkdir_p(QUALITY_DIR)
    txt_path = QUALITY_DIR.join("mutation.txt")

    cmd = [
      "bundle", "exec", "mutant", "run",
      "--integration", "rspec",
      "--require", "./script/mutant_bootstrap.rb",
      "--usage", "opensource",
      "--", *MUTANT_SUBJECTS
    ]
    sh "#{cmd.shelljoin} > #{txt_path.to_s.shellescape} 2>&1 || true"

    parsed = Quality::MutantParser.new(txt_path).parse
    File.write(QUALITY_DIR.join("mutation.json"), JSON.pretty_generate(parsed))

    ratchet_if_unset!(parsed[:kill_ratio])
  end
end

def ratchet_if_unset!(kill_ratio)
  require "yaml"
  path = Rails.root.join("config/quality_thresholds.yml")
  thresholds = YAML.load_file(path)

  return unless thresholds.dig("mutation", "kill_ratio_min").nil?

  thresholds["mutation"]["kill_ratio_min"] = kill_ratio
  File.write(path, thresholds.to_yaml)
  puts "[quality:mutation] Ratchet set: mutation.kill_ratio_min = #{kill_ratio}"
end

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

namespace :quality do
  desc "Remove stale mutation.json so :report skips the mutation row in local runs"
  task :clean_mutation_artifact do
    path = QUALITY_DIR.join("mutation.json")
    path.delete if path.exist?
  end

  desc "Fast local quality gate (everything except mutation testing). ~15s runtime."
  task local: %w[
    quality:clean_mutation_artifact
    quality:coverage
    quality:rubocop
    quality:critic
    quality:flog
    quality:brakeman
    quality:report
  ]
end

desc "Full quality gate including mutation testing. ~3min runtime — used by CI."
task quality: %w[
  quality:coverage
  quality:rubocop
  quality:critic
  quality:flog
  quality:mutation
  quality:brakeman
  quality:report
]
