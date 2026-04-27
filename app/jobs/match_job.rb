class MatchJob < ApplicationJob
  queue_as :default

  def perform(_story_id)
    # Implemented in plan-2 task 11.
  end
end
