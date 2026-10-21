# Variáveis que o operador escreve no status e que viram texto na hora de
# publicar, uma vez por conexão: o mesmo post em duas lojas sai com o nome de
# cada uma, e um modelo semanal sai com o dia certo sem ninguém editar.
#
# Chave desconhecida fica como está, para o erro de digitação aparecer no
# status em vez de sumir em silêncio.
module Whatsapp::StatusPosts::Variables
  WEEKDAYS = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze
  KEYS = %w[conexao empresa dia_semana data].freeze
  PATTERN = /\{\{\s*(\w+)\s*\}\}/

  def self.render(text, account:, inbox_name:, at: Time.zone.now)
    values = {
      'conexao' => inbox_name.to_s,
      'empresa' => account.name.to_s,
      'dia_semana' => WEEKDAYS[at.wday],
      'data' => at.strftime('%d/%m')
    }
    text.to_s.gsub(PATTERN) { values.fetch(Regexp.last_match(1), Regexp.last_match(0)) }
  end
end
