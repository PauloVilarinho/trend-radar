require "flog"

module Quality
  class FlogParser
    def initialize(paths)
      @paths = Array(paths)
    end

    def parse
      flog = Flog.new
      @paths.each { |path| flog.flog(path) }

      totals = flog.totals
      return empty_result if totals.empty?

      {
        method_max: totals.values.max,
        class_max: max_class_score(totals)
      }
    end

    private

    def empty_result
      { method_max: 0.0, class_max: 0.0 }
    end

    def max_class_score(totals)
      totals
        .group_by { |method_name, _| method_name.split(/[#.]/, 2).first }
        .values
        .map { |entries| entries.sum { |_, score| score } }
        .max
    end
  end
end
