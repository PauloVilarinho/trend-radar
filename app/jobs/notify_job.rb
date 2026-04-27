class NotifyJob < ApplicationJob
  queue_as :default

  def perform(_match_id)
    # Implemented in Plan 3.
  end
end
