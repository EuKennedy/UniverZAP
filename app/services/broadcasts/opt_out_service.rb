# "Não quero mais receber": a cliente escreveu que não quer mensagens e daqui
# em diante nenhum disparo, sequência ou mensagem agendada sai para ela.
#
# Marca o contato (`opt_out_disparos = true`, atributo criado se faltar, para
# aparecer na ficha e nos filtros), cancela o que estava agendado e pula os
# disparos pendentes. Voltar atrás é desmarcar o atributo no contato.
#
# A detecção é de propósito estreita: frases inteiras de descadastro, ou a
# mensagem ser SÓ "sair"/"parar"/"stop". "Vou sair mais cedo" não descadastra.
class Broadcasts::OptOutService
  ATTRIBUTE = Broadcasts::RecipientGuard::OPT_OUT_ATTRIBUTE
  PHRASES = [
    /\bnao (quero|desejo) (mais )?receber\b/,
    /\b(para|pare|parar) de (me )?(mandar|enviar)\b/,
    /\bnao (me )?(mande|mandem|envie|enviem) mais\b/,
    /\bdescadastr/,
    /\b(me )?(tira|tirem|remova|remover|exclua|excluir) (o )?(meu numero|meu contato|da lista|dessa lista|desta lista)\b/,
    /\bsair da lista\b/,
    /\bcancelar (a )?inscricao\b/
  ].freeze
  # "cancelar" sozinho fica de fora: no salão quase sempre é cancelar o horário.
  SINGLE_WORDS = %w[sair parar pare stop descadastrar].freeze

  def self.opt_out_text?(text)
    normalized = I18n.transliterate(text.to_s).downcase.gsub(/[^a-z\s]/, ' ').squish
    return false if normalized.blank?
    return true if SINGLE_WORDS.include?(normalized)

    PHRASES.any? { |pattern| normalized.match?(pattern) }
  end

  def initialize(contact)
    @contact = contact
  end

  def perform
    return false if Broadcasts::RecipientGuard.opted_out?(@contact)

    ensure_definition
    @contact.update!(custom_attributes: (@contact.custom_attributes || {}).merge(ATTRIBUTE => true))
    ScheduledMessage.pending.where(contact_id: @contact.id).find_each { |scheduled| scheduled.cancel!('opted_out') }
    BroadcastRecipient.status_pending.where(contact_id: @contact.id)
                      .update_all(status: BroadcastRecipient.statuses[:skipped], skip_reason: 'opted_out', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    true
  end

  private

  def ensure_definition
    @contact.account.custom_attribute_definitions.find_or_create_by!(attribute_key: ATTRIBUTE, attribute_model: 'contact_attribute') do |record|
      record.attribute_display_name = I18n.t('scheduled_messages.opt_out.attribute_name')
      record.attribute_display_type = 'checkbox'
      record.attribute_description = I18n.t('scheduled_messages.opt_out.attribute_description')
    end
  end
end
