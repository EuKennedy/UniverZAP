class Api::V1::Accounts::KanbanWebhookSubscriptionsController < Api::V1::Accounts::BaseController
  before_action :fetch_subscription, except: [:index, :create]
  before_action :check_authorization

  def index
    render json: Current.account.kanban_webhook_subscriptions.order(created_at: :desc).map(&:push_event_data)
  end

  def show
    # `include_secret: true` only on this single endpoint, gated by
    # admin policy — the operator needs the secret to wire HMAC
    # verification on their end (n8n etc.). Index hides it to avoid
    # accidental log exposure.
    render json: @subscription.push_event_data(include_secret: true)
  end

  def create
    subscription = Current.account.kanban_webhook_subscriptions.create!(
      subscription_params.merge(created_by_user: Current.user)
    )
    render json: subscription.push_event_data(include_secret: true), status: :created
  end

  def update
    @subscription.update!(subscription_params)
    render json: @subscription.push_event_data
  end

  def destroy
    @subscription.destroy!
    head :ok
  end

  # POST /kanban_webhook_subscriptions/:id/test
  # Sends a synthetic `webhook.test` payload to the configured URL so
  # the operator can verify the receiver is reachable + signature
  # validates BEFORE relying on real events.
  def test
    Kanban::WebhookSubscriptionDeliveryJob.perform_later(
      @subscription.id,
      'webhook.test',
      {
        event: 'webhook.test',
        delivered_at: Time.current.iso8601,
        account_id: Current.account.id,
        data: { message: 'This is a test delivery from UniverZAP.' }
      }
    )
    head :accepted
  end

  private

  def fetch_subscription
    @subscription = Current.account.kanban_webhook_subscriptions.find(params[:id])
  end

  def subscription_params
    params.require(:kanban_webhook_subscription).permit(:name, :url, :active, events: [])
  end
end
