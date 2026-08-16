require 'rails_helper'

RSpec.describe Whatsapp::WahaInboxResolver do
  subject(:resolver) { described_class.new(account) }

  let(:account) { create(:account) }
  let(:json) { { 'Content-Type' => 'application/json' } }

  # A inbox nascida do fluxo de conexão: WahaController#install_app cria um
  # Channel::Api e guarda a sessão em additional_attributes.
  def api_inbox(session_name: 'u1-loja', owner: account)
    create(:channel_api, account: owner,
                         additional_attributes: { 'source' => 'waha', 'session_name' => session_name }).reload.inbox
  end

  # O outro caminho: canal de WhatsApp com provider waha, que pode apontar para
  # uma instância WAHA própria do cliente.
  def whatsapp_inbox(config: { 'session_name' => 'u1-zap', 'base_url' => 'https://own.waha', 'api_key' => 'k' })
    create(:channel_whatsapp, account: account, provider: 'waha', provider_config: config,
                              validate_provider_config: false, sync_templates: false).reload.inbox
  end

  describe '#resolve!' do
    it 'resolves the session of an inbox created by the WAHA connect flow' do
      inbox = api_inbox
      stub_request(:get, 'https://waha.test/api/u1-loja/profile').to_return(status: 200, headers: json, body: '{}')

      with_modified_env(WAHA_BASE_URL: 'https://waha.test', WAHA_API_KEY: 'k') do
        _found, service = resolver.resolve!(inbox.id)
        service.profile
      end

      expect(a_request(:get, 'https://waha.test/api/u1-loja/profile')).to have_been_made
    end

    # Um cliente pode ter a WAHA dele. Se ignorássemos o provider_config, o
    # painel falaria com a instância errada usando a chave errada.
    it 'talks to the WAHA instance configured on the channel instead of the one from the ENV' do
      inbox = whatsapp_inbox
      stub_request(:get, 'https://own.waha/api/u1-zap/profile').to_return(status: 200, headers: json, body: '{}')

      with_modified_env(WAHA_BASE_URL: 'https://waha.test', WAHA_API_KEY: 'other') do
        _found, service = resolver.resolve!(inbox.id)
        service.profile
      end

      expect(a_request(:get, 'https://own.waha/api/u1-zap/profile')).to have_been_made
    end

    it 'refuses an inbox that has nothing to do with WAHA' do
      inbox = create(:inbox, account: account)

      expect { resolver.resolve!(inbox.id) }.to raise_error(described_class::NotWahaInboxError)
    end

    it 'refuses a WhatsApp channel whose provider is not waha' do
      inbox = create(:channel_whatsapp, account: account, provider: 'default',
                                        validate_provider_config: false, sync_templates: false).reload.inbox

      expect { resolver.resolve!(inbox.id) }.to raise_error(described_class::NotWahaInboxError)
    end

    # O session_name entra na URL da WAHA. Sem esta trava, um provider_config
    # com "../" transformaria o painel numa porta para qualquer endpoint dela.
    it 'refuses a session name that could escape the WAHA path' do
      inbox = api_inbox(session_name: '../sessions')

      expect { resolver.resolve!(inbox.id) }.to raise_error(described_class::NotWahaInboxError)
    end

    it 'does not find an inbox that belongs to another account' do
      stranger = api_inbox(session_name: 'u2-loja', owner: create(:account))

      expect { resolver.resolve!(stranger.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#waha_inboxes' do
    it 'lists both flavours of WAHA inbox and nothing else' do
      waha = [api_inbox, whatsapp_inbox]
      create(:inbox, account: account)
      api_inbox(session_name: 'u2-loja', owner: create(:account))

      expect(resolver.waha_inboxes.map(&:id)).to match_array(waha.map(&:id))
    end
  end
end
