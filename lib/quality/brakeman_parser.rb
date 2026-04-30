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
