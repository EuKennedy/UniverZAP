require 'rails_helper'

RSpec.describe Whatsapp::TemplateManagementService do
  let(:account) { create(:account) }
  # A factory sobrescreve provider_config com os próprios valores, então o WABA
  # do teste é o dela, não um inventado aqui.
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:service) { described_class.new(channel) }
  let(:base) { "https://graph.facebook.com/v14.0/#{channel.provider_config['business_account_id']}/message_templates" }

  def valid(overrides = {})
    { name: 'teste_integracao', category: 'UTILITY', language: 'pt_BR', body: 'Tudo certo.' }.merge(overrides)
  end

  describe 'criar' do
    it 'submete e devolve o que a Meta respondeu' do
      stub_request(:post, base).to_return(
        status: 200, body: { id: 't-1', status: 'PENDING' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      result = service.create(**valid)

      expect(result.success?).to be(true)
      expect(result.template[:status]).to eq('PENDING')
      # A resposta da criação não traz o nome, e sem ele o operador não acha o
      # template de novo na lista.
      expect(result.template[:name]).to eq('teste_integracao')
    end

    # A Meta só aceita minúscula, número e underscore, e devolve um erro que não
    # explica isso. Recusar aqui é mais barato que uma ida de rede e mais claro
    # que a resposta deles.
    it 'recusa um nome que a Meta não aceita, sem chamar ninguém' do
      result = service.create(**valid(name: 'Promoção de Natal'))

      expect(result.error).to eq('name_format')
      expect(WebMock).not_to have_requested(:post, base)
    end

    # AUTHENTICATION é código de verificação, não é o que campanha manda, e
    # liberar por engano queima uma categoria mais barata em uso indevido.
    it 'aceita apenas as categorias que campanha usa' do
      expect(service.create(**valid(category: 'AUTHENTICATION')).error).to eq('category_unknown')
      expect(service.create(**valid(body: '   ')).error).to eq('body_blank')
    end

    # O erro da Meta é acionável aqui: nome repetido, categoria que não combina
    # com o texto. Quem lê é quem corrige.
    it 'repassa o motivo que a Meta deu' do
      stub_request(:post, base).to_return(
        status: 400, body: { error: { message: 'template name already exists' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      expect(service.create(**valid).error).to include('already exists')
    end

    # O controller repassa o que o cliente mandou. Sem argumento opcional, um
    # pedido sem `language` levantaria ArgumentError e viraria 500 — em vez de
    # uma recusa que diz o que faltou.
    it 'recusa um pedido incompleto em vez de estourar' do
      result = service.create(body: 'Oi.')

      expect(result.success?).to be(false)
      expect(result.error).to eq('name_format')
    end

    # Rede fora não pode subir exceção para dentro do controller.
    it 'não deixa uma falha de rede escapar' do
      stub_request(:post, base).to_timeout

      result = service.create(**valid)

      expect(result.success?).to be(false)
      expect(result.error).to eq('unreachable')
    end
  end

  describe 'listar' do
    it 'traz o estado de cada template, com o motivo da recusa' do
      stub_request(:get, base).to_return(
        status: 200,
        body: { data: [{ id: 't-1', name: 'promo', status: 'REJECTED', category: 'MARKETING',
                         language: 'pt_BR', rejected_reason: 'INVALID_FORMAT' }] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      row = service.list.template.first

      expect(row[:status]).to eq('REJECTED')
      # Sem isto o operador vê "recusado" e não tem por onde começar.
      expect(row[:rejected_reason]).to eq('INVALID_FORMAT')
    end
  end

  describe 'remover' do
    it 'apaga pelo nome' do
      stub_request(:delete, "#{base}?name=promo").to_return(status: 200, body: '{}')

      expect(service.destroy('promo').success?).to be(true)
    end
  end
end
