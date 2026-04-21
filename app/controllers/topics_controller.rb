class TopicsController < ApplicationController
  def index
    render inertia: "topics/index", props: TopicIndexProps.call(current_user)
  end
end
