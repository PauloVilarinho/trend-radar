class Admin::TopicsController < ApplicationController
  before_action :require_admin!
  before_action :set_topic, only: [ :edit, :update ]

  def index
    topics = Topic.order(:name).left_joins(:topic_subscriptions)
                   .group(:id)
                   .select("topics.*, COUNT(topic_subscriptions.id) AS subscriber_count")
    render inertia: "admin/topics/index", props: {
      topics: topics.map { |t| admin_topic_row(t) }
    }
  end

  def new
    render inertia: "admin/topics/new", props: {
      topic: empty_form,
      errors: {}
    }
  end

  def create
    topic = Topic.new(topic_params.merge(created_by: current_user))
    if topic.save
      redirect_to admin_topics_path, notice: "Topic created."
    else
      render inertia: "admin/topics/new",
             props: { topic: form_attrs(topic), errors: topic.errors.to_hash },
             status: :unprocessable_content
    end
  end

  def edit
    render inertia: "admin/topics/edit", props: {
      topic: form_attrs(@topic).merge(id: @topic.id),
      errors: {}
    }
  end

  def update
    if @topic.update(topic_params)
      redirect_to admin_topics_path, notice: "Topic updated."
    else
      render inertia: "admin/topics/edit",
             props: { topic: form_attrs(@topic).merge(id: @topic.id), errors: @topic.errors.to_hash },
             status: :unprocessable_content
    end
  end

  private

  def set_topic
    @topic = Topic.find(params[:id])
  end

  def topic_params
    params.require(:topic).permit(:name, :active, keywords: [])
  end

  def admin_topic_row(topic)
    {
      id: topic.id,
      name: topic.name,
      keywords: topic.keywords,
      active: topic.active,
      subscriber_count: topic.attributes["subscriber_count"].to_i
    }
  end

  def form_attrs(topic)
    {
      name: topic.name || "",
      keywords: topic.keywords || [],
      active: topic.active.nil? ? true : topic.active
    }
  end

  def empty_form
    { name: "", keywords: [], active: true }
  end
end
