class TopicSubscriptionsController < ApplicationController
  def create
    subscription = current_user.topic_subscriptions.build(
      topic_id: params[:topic_id],
      **subscription_params.to_h.symbolize_keys
    )
    if subscription.save
      BackfillSubscriptionJob.perform_later(subscription.id)
      return redirect_to topics_path, notice: "Subscribed."
    end

    render_index_with_errors(subscription)
  end

  def update
    subscription = current_user.topic_subscriptions.find_by!(topic_id: params[:topic_id])
    return redirect_to topics_path, notice: "Subscription updated." if subscription.update(subscription_params)

    render_index_with_errors(subscription)
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

  def render_index_with_errors(subscription)
    render inertia: "topics/index",
           props: TopicIndexProps.call(current_user, errors: subscription.errors.to_hash),
           status: :unprocessable_content
  end
end
