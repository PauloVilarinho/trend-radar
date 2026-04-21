module Quality
  class Report
    GATES = [
      { name: "Line coverage",            measure: [ :coverage, :line ],                       threshold: [ "coverage", "line_min" ],                       cmp: :>=, unit: "%" },
      { name: "Branch coverage",          measure: [ :coverage, :branch ],                     threshold: [ "coverage", "branch_min" ],                     cmp: :>=, unit: "%" },
      { name: "Flog max (method)",        measure: [ :flog, :method_max ],                     threshold: [ "flog", "method_max" ],                         cmp: :<=, unit: "" },
      { name: "Flog max (class)",         measure: [ :flog, :class_max ],                      threshold: [ "flog", "class_max" ],                          cmp: :<=, unit: "" },
      { name: "Class length max",         measure: [ :rubocop, :class_length_max ],            threshold: [ "rubocop_metrics", "class_length_max" ],        cmp: :<=, unit: "" },
      { name: "Method length max",        measure: [ :rubocop, :method_length_max ],           threshold: [ "rubocop_metrics", "method_length_max" ],       cmp: :<=, unit: "" },
      { name: "AbcSize max",              measure: [ :rubocop, :abc_size_max ],                threshold: [ "rubocop_metrics", "abc_size_max" ],            cmp: :<=, unit: "" },
      { name: "CyclomaticComplexity max", measure: [ :rubocop, :cyclomatic_complexity_max ],   threshold: [ "rubocop_metrics", "cyclomatic_complexity_max" ], cmp: :<=, unit: "" },
      { name: "Mutation kill ratio",      measure: [ :mutation, :kill_ratio ],                 threshold: [ "mutation", "kill_ratio_min" ],                 cmp: :>=, unit: "%" }
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
      lines = [ "Quality gates", "=" * 13, "" ]
      lines.concat(gate_results.map(&:to_row))
      lines << ""
      lines << "#{gate_results.count(&:passed?)}/#{gate_results.size} gates passed."
      lines.join("\n")
    end

    private

    def build_gate_results
      GATES.filter_map do |gate|
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
    end
  end
end
