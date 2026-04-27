class MatchesController < ApplicationController
  before_action :set_match

  def mark_posted
    @match.update!(posted_at: Time.current)
    redirect_to root_path, notice: "Marked as posted."
  end

  def dismiss
    @match.update!(dismissed_at: Time.current)
    redirect_to root_path, notice: "Dismissed."
  end

  private

  def set_match
    @match = Match.joins(topic: :topic_subscriptions)
                  .where(topic_subscriptions: { user_id: current_user.id })
                  .find(params[:id])
  end
end
