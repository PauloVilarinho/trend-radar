class KeywordMatcher
  class << self
    def matches?(story, keywords)
      text = searchable_text(story)
      return false if text.blank?

      keywords.any? { |kw| keyword_hit?(text, kw) }
    end

    def matching_topics(story, topics_scope)
      topics_scope.where(active: true).select { |topic| matches?(story, topic.keywords) }
    end

    private

    def keyword_hit?(text, keyword)
      normalized = keyword.to_s.downcase.strip
      return false if normalized.empty?

      text.include?(normalized)
    end

    def searchable_text(story)
      [ story.title, story.url, story.text ].compact.join(" ").downcase
    end
  end
end
