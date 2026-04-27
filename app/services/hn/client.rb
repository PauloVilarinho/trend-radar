module Hn
  class Client
    BASE_URL = "https://hacker-news.firebaseio.com/v0".freeze

    class RequestError < StandardError; end

    def initialize(connection: default_connection)
      @connection = connection
    end

    def top_story_ids
      parse(get("topstories.json"))
    end

    def new_story_ids
      parse(get("newstories.json"))
    end

    def best_story_ids
      parse(get("beststories.json"))
    end

    def item(hn_id)
      data = parse(get("item/#{hn_id}.json"))
      return nil if data.nil? || data[:deleted] || data[:dead]

      data
    end

    private

    attr_reader :connection

    def get(path)
      response = connection.get(path)
      raise RequestError, "HN #{path}: #{response.status}" unless response.success?

      response.body
    end

    def parse(body)
      return nil if body.nil? || body == "null"

      JSON.parse(body, symbolize_names: true)
    rescue JSON::ParserError => e
      raise RequestError, "Invalid JSON from HN: #{e.message}"
    end

    def default_connection
      Faraday.new(url: BASE_URL) do |f|
        f.request :retry, max: 3, interval: 0.5,
                          exceptions: [ Faraday::ConnectionFailed, Faraday::TimeoutError ]
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end
  end
end
