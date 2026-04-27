module Openai
  class Matcher
    MODEL = "gpt-4o-mini".freeze
    MAX_JSON_RETRIES = 3

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a strict classifier that decides if a Hacker News story is relevant to a given
      editorial topic. Respond with ONLY a JSON object: {"score": float 0-1, "reason": string}.
      A score of 1.0 means the story is clearly and primarily about the topic. 0.0 means not
      relevant at all. 0.6+ is the threshold for "worth notifying an editor".
      The reason should be one sentence suitable as a social-media post opener.
    PROMPT

    JSON_REPAIR_PROMPT = "Your previous response was not valid JSON. Respond with ONLY a JSON " \
                        "object with keys 'score' (float 0-1) and 'reason' (string). No prose, " \
                        "no markdown fences.".freeze

    def initialize(client: OpenAI::Client.new)
      @client = client
    end

    def call(story:, topic:)
      messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: user_prompt(story: story, topic: topic) }
      ]

      MAX_JSON_RETRIES.times do
        content = chat_content(messages)
        parsed = parse(content)
        return parsed if parsed

        push_repair_messages(messages, content)
      end

      Rails.logger.warn("[Openai::Matcher] exhausted retries story=#{story.id} topic=#{topic.id}")
      { score: 0.0, reason: "invalid response from classifier" }
    end

    private

    attr_reader :client

    def chat_content(messages)
      response = client.chat(parameters: {
        model: MODEL,
        messages: messages,
        response_format: { type: "json_object" },
        temperature: 0.2
      })
      response.dig("choices", 0, "message", "content").to_s
    end

    def push_repair_messages(messages, content)
      messages << { role: "assistant", content: content }
      messages << { role: "system", content: JSON_REPAIR_PROMPT }
    end

    def parse(content)
      data = JSON.parse(content)
      return nil unless data.is_a?(Hash) && data.key?("score") && data.key?("reason")

      score = data["score"].to_f
      return nil unless score.between?(0.0, 1.0)

      { score: score, reason: data["reason"].to_s }
    rescue JSON::ParserError
      nil
    end

    def user_prompt(story:, topic:)
      <<~PROMPT
        Topic: #{topic.name}
        Topic keywords (may be narrower than the name): #{topic.keywords.join(', ')}

        Story:
          Title: #{story.title}
          URL: #{story.url || '(none)'}
          Text: #{(story.text || '').truncate(500)}

        Classify: is this story relevant to the topic?
      PROMPT
    end
  end
end
