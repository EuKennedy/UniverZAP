class Api::V1::Accounts::Ai::CreditsController < Api::V1::Accounts::BaseController
  # GET /api/v1/accounts/:account_id/ai/credits
  #
  # Reads the operator's Athenas balance and recent ledger so the
  # dashboard can render the header meter, soft-warning banners and the
  # top-up modal without flashing stale data. Every value is in cents of
  # BRL — the dashboard side does the formatting.
  def show
    ledger = Ai::CreditLedger.new(Current.account)
    render json: ledger.summary.merge(
      packages: top_up_packages,
      recent_entries: serialize_entries(ledger.recent_entries),
      pricing: pricing_snapshot
    )
  end

  private

  # Static catalogue for the top-up modal. The price/bonus split mirrors
  # the Stripe / Hotmart anchoring pattern: the middle card is the one
  # we want most operators to land on, so it shows the strongest
  # "popular" framing in the UI. Keeping the catalogue server-side makes
  # it trivial to A/B test bonuses without shipping a frontend bundle.
  def top_up_packages
    [
      {
        id: 'tokens_50',
        amount_cents_brl: 5_000,
        credit_cents_brl: 5_000,
        bonus_cents_brl: 0,
        checkout_url: 'https://pay.univercart.com/c/pacote-de-tokens-r-50-athenas-ai-39eb',
        badge: nil
      },
      {
        id: 'tokens_100',
        amount_cents_brl: 10_000,
        credit_cents_brl: 11_000,
        bonus_cents_brl: 1_000,
        checkout_url: 'https://pay.univercart.com/c/pacote-de-tokens-r-100-athenas-ai-6575',
        badge: 'popular'
      },
      {
        id: 'tokens_150',
        amount_cents_brl: 15_000,
        credit_cents_brl: 18_000,
        bonus_cents_brl: 3_000,
        checkout_url: 'https://pay.univercart.com/c/pacote-de-tokens-r-150-athenas-ai-cc46',
        badge: 'best_value'
      }
    ]
  end

  def pricing_snapshot
    {
      sonnet_cents_per_conversation: Ai::PricingCalculator.cost_cents_brl(
        model: 'claude-sonnet-4-5', input_tokens: 5_000, output_tokens: 3_000
      ),
      haiku_cents_per_conversation: Ai::PricingCalculator.cost_cents_brl(
        model: 'claude-haiku-4-5', input_tokens: 5_000, output_tokens: 3_000
      )
    }
  end

  def serialize_entries(entries)
    entries.map do |entry|
      {
        id: entry.id,
        kind: entry.kind,
        amount_cents_brl: entry.amount_cents_brl,
        description: entry.description,
        created_at: entry.created_at.to_i
      }
    end
  end
end
