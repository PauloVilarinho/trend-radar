# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    matches = Match.visible
                   .where(topic_id: current_user.subscribed_topics.select(:id))
                   .includes(:story, :topic)
                   .recent
                   .limit(100)

    render inertia: "dashboard/index", props: {
      matches: matches.map { |m| match_props(m) }
    }
  end

  private

  def match_props(match)
    {
      id: match.id,
      topic: { id: match.topic.id, name: match.topic.name },
      story: story_props(match.story),
      relevance_score: match.relevance_score.to_f,
      velocity_score: match.velocity_score&.to_f,
      reason: match.reason,
      matched_at: match.matched_at.iso8601
    }
  end

  def story_props(story)
    {
      id: story.id,
      hn_id: story.hn_id,
      title: story.title,
      url: story.url,
      score: story.score,
      descendants: story.descendants,
      hn_url: "https://news.ycombinator.com/item?id=#{story.hn_id}"
    }
  end
end
