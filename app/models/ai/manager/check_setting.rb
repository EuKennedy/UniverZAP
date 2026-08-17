# O liga/desliga de uma verificação, por conta.
#
# A ausência de linha é "ligada". Isso é o que permite acrescentar verificação
# nova sem backfill e sem que ela nasça invisível: quem escreve a classe não
# precisa lembrar de escrever migration nenhuma, e nenhuma conta fica sem a
# verificação porque a linha não existia ainda.
class Ai::Manager::CheckSetting < ApplicationRecord
  self.table_name = 'ai_manager_check_settings'

  belongs_to :account

  validates :check_key, presence: true, uniqueness: { scope: :account_id }

  # As chaves que a conta desligou explicitamente. Uma consulta só, porque o
  # motor pergunta isso uma vez por rodada e não uma vez por verificação.
  def self.disabled_keys_for(account)
    where(account_id: account.id, enabled: false).pluck(:check_key).to_set
  end
end
