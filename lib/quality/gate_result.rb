module Quality
  class GateResult
    COMPARATOR_SYMBOLS = { :>= => ">=", :<= => "<=", :> => ">", :< => "<" }.freeze

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
      name_col = name.ljust(26)
      measured_col = format_value(measured).ljust(8)

      return "#{name_col}#{measured_col}(unset)      — [ratchet pending]" if threshold.nil?

      threshold_col = "#{COMPARATOR_SYMBOLS.fetch(comparator)} #{format_value(threshold)}".ljust(12)
      "#{name_col}#{measured_col}#{threshold_col}#{passed? ? '✓' : '✗'}"
    end

    private

    def format_value(value)
      value.is_a?(Float) ? "#{format('%.1f', value)}#{unit}" : "#{value}#{unit}"
    end
  end
end
