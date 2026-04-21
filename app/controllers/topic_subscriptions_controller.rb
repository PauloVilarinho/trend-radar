class TopicSubscriptionsController < ApplicationController
  def create
    subscription = current_user.topic_subscriptions.build(
      topic_id: params[:topic_id],
      **subscription_params.to_h.symbolize_keys
    )

    if subscription.save
      redirect_to topics_path, notice: "Subscribed."
    else
      render inertia: "topics/index",
             props: TopicIndexProps.call(current_user, errors: subscription.errors.to_hash),
             status: :unprocessable_content
    end
  end

  def update
    subscription = current_user.topic_subscriptions.find_by!(topic_id: params[:topic_id])

    if subscription.update(subscription_params)
      redirect_to topics_path, notice: "Subscription updated."
    else
      render inertia: "topics/index",
             props: TopicIndexProps.call(current_user, errors: subscription.errors.to_hash),
             status: :unprocessable_content
    end
  end

  def destroy
    subscription = current_user.topic_subscriptions.find_by!(topic_id: params[:topic_id])
    subscription.destroy
    redirect_to topics_path, notice: "Unsubscribed."
  end

  private

  def subscription_params
    return ActionController::Parameters.new.permit! unless params[:topic_subscription]

    params.require(:topic_subscription).permit(:discord_webhook, :active)
  end
end
