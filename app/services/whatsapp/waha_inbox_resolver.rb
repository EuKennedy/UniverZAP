# Traduz "a caixa de entrada X da conta Y" para a sessão WAHA correspondente.
#
# Existe porque o session_name nunca pode chegar cru do request até a WAHA.
# Quem escolhe a sessão é o vínculo inbox -> canal, e a inbox é sempre buscada
# dentro de `account.inboxes`: uma inbox de outro tenant simplesmente não é
# encontrada e vira 404, em vez de virar uma chamada válida contra o número
# de outra empresa.
class Whatsapp::WahaInboxResolver
  class NotWahaInboxError < StandardError; end

  # O nome da sessão entra na URL da WAHA. No canal Channel::Whatsapp ele vem
  # do provider_config, preenchido à mão no formulário da inbox, então o
  # formato é restringido aqui para que um "../" gravado no banco não vire
  # path traversal contra a API da WAHA.
  SESSION_NAME_FORMAT = /\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}\z/

  def initialize(account)
    @account = account
  end

  # Só as inboxes que de fato falam com a WAHA. O seletor da tela é montado a
  # partir daqui, então uma conta sem conexão WAHA recebe lista vazia e a tela
  # mostra o estado vazio, em vez de um dropdown que não leva a lugar nenhum.
  def waha_inboxes
    @account.inboxes.includes(:channel).select { |inbox| session_name_for(inbox).present? }
  end

  def resolve!(inbox_id)
    inbox = @account.inboxes.find(inbox_id)
    session_name = session_name_for(inbox)
    raise NotWahaInboxError, I18n.t('inbox.whatsapp.waha.not_a_waha_inbox') if session_name.blank?

    [inbox, service_for(inbox, session_name)]
  end

  def session_name_for(inbox)
    name = raw_session_name(inbox)
    name.to_s.match?(SESSION_NAME_FORMAT) ? name : nil
  end

  private

  # Os dois jeitos de uma inbox virar WAHA nesta base: o canal de API criado
  # por WahaController#install_app, que guarda a sessão em additional_attributes,
  # e o canal de WhatsApp com provider waha, que guarda em provider_config.
  def raw_session_name(inbox)
    channel = inbox.channel
    case channel
    when Channel::Api
      attributes = channel.additional_attributes.to_h
      attributes['session_name'] if attributes['source'] == 'waha'
    when Channel::Whatsapp
      channel.provider_config.to_h['session_name'] if channel.provider == 'waha'
    end
  end

  # Channel::Whatsapp pode apontar para uma instância WAHA própria, com URL e
  # chave dele; o Channel::Api criado pelo WahaController usa a do ENV. Passar
  # nil deixa o serviço cair no ENV sozinho, que é o comportamento dele.
  def service_for(inbox, session_name)
    config = inbox.channel.is_a?(Channel::Whatsapp) ? inbox.channel.provider_config.to_h : {}
    Whatsapp::WahaSessionService.new(
      session_name: session_name,
      base_url: config['base_url'].presence,
      api_key: config['api_key'].presence
    )
  end
end
