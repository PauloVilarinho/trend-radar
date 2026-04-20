# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    render inertia: "dashboard/index"
  end
end
