class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :authenticate_user!

  inertia_share do
    {
      current_user: current_user && { id: current_user.id, email: current_user.email },
      flash: { notice: flash[:notice], alert: flash[:alert] }.compact
    }
  end
end
