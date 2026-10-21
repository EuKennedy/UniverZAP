# Telefone digitado ou colado ("(11) 99999-8888", "11999998888",
# "5511999998888") no formato E.164 que o contato guarda ("+5511999998888").
# Disparo, importação de CSV e extração de grupo passam por aqui: inventar uma
# segunda convenção é como a resposta a um disparo abre uma conversa separada
# em vez de cair na que o disparo criou.
module Broadcasts::PhoneNumber
  DEFAULT_COUNTRY_CODE = '55'.freeze

  module_function

  # Reaproveita o normalizador que o webhook do WhatsApp já aplica, para o
  # número terminar no mesmo formato que o provedor devolve.
  def normalize(raw)
    digits = raw.to_s.gsub(/\D/, '')
    return if digits.length < 10

    digits = "#{DEFAULT_COUNTRY_CODE}#{digits}" if local_number?(raw, digits)
    return "+#{digits}" unless brazilian_mobile?(digits)

    "+#{Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(digits)}"
  end

  # O mesmo celular brasileiro com e sem o nono dígito. Contatos antigos (ou
  # criados pela ponte da WAHA) podem estar gravados sem ele; procurar só pela
  # forma normalizada duplicava a cliente.
  def variants(e164)
    return [] if e164.blank?

    digits = e164.delete_prefix('+')
    return [e164] unless digits.start_with?(DEFAULT_COUNTRY_CODE) && digits.length == 13 && digits[4] == '9'

    [e164, "+#{digits[0, 4]}#{digits[5..]}"]
  end

  # Um + na frente quer dizer que o número já traz o código do país. Somar 55 a
  # tudo que é curto transformava um número dos EUA em um brasileiro, então o +
  # é o contrato: números internacionais são digitados com ele.
  def local_number?(raw, digits)
    digits.length <= 11 && !raw.to_s.strip.start_with?('+')
  end

  # O normalizador insere o nono dígito sempre que o resultado não tem 13
  # dígitos, o que transforma um fixo de 10 dígitos no celular de outra pessoa.
  # Só um número com cara de celular brasileiro é entregue a ele.
  def brazilian_mobile?(digits)
    return false unless digits.start_with?(DEFAULT_COUNTRY_CODE)

    digits.length == 13 || (digits.length == 12 && digits[4].to_i >= 6)
  end
end
