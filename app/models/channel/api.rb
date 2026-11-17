# == Schema Information
#
# Table name: channel_api
#
#  id                    :bigint           not null, primary key
#  additional_attributes :jsonb
#  hmac_mandatory        :boolean          default(FALSE)
#  hmac_token            :string
#  identifier            :string
#  secret                :string
#  webhook_url           :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :integer          not null
#
# Indexes
#
#  index_channel_api_on_hmac_token  (hmac_token) UNIQUE
#  index_channel_api_on_identifier  (identifier) UNIQUE
#

class Channel::Api < ApplicationRecord
  include Channelable

  self.table_name = 'channel_api'
  EDITABLE_ATTRS = [:webhook_url, :hmac_mandatory, { additional_attributes: {} }].freeze

  has_secure_token :identifier
  has_secure_token :hmac_token
  include WebhookSecretable
  validate :ensure_valid_agent_reply_time_window
  validates :webhook_url, length: { maximum: Limits::URL_LENGTH_LIMIT }
  validate :waha_bridge_without_mandatory_hmac

  def name
    'API'
  end

  def waha_bridge?
    additional_attributes.to_h['source'] == 'waha'
  end

  private

  # A ponte WAHA não assina os contatos que cria. Com a validação obrigatória,
  # todo contato novo era recusado e a mensagem dele não entrava na caixa.
  def waha_bridge_without_mandatory_hmac
    errors.add(:hmac_mandatory, I18n.t('errors.channel_api.waha_hmac_mandatory')) if hmac_mandatory && waha_bridge?
  end

  def ensure_valid_agent_reply_time_window
    return if additional_attributes['agent_reply_time_window'].blank?
    return if additional_attributes['agent_reply_time_window'].to_i.positive?

    errors.add(:agent_reply_time_window, 'agent_reply_time_window must be greater than 0')
  end
end
