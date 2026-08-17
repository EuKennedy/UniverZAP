# O catálogo de verificações do Gerente.
#
# Uma lista escrita à mão em vez de `Base.descendants`. Descendants só conhece o
# que já foi carregado, e em desenvolvimento nada foi: a lista voltaria vazia, a
# tela de configuração apareceria sem nenhum interruptor e ninguém entenderia por
# quê. Escrita à mão, o catálogo é o mesmo em qualquer ambiente e em qualquer
# ordem de boot.
#
# Referências dentro do método e não numa constante congelada, para que carregar
# este arquivo não force o carregamento das quatro classes durante o boot.
module Ai::Manager::Checks
  module_function

  def all
    [PromisedTimeMismatch, LoosePromise, DiedOnPrice, UngroundedNumber]
  end

  def find(key)
    all.find { |check| check.key == key.to_s }
  end

  # As verificações que esta conta deixou ligadas. A ausência de linha em
  # ai_manager_check_settings é "ligada", então uma verificação nova entra em
  # operação para todo mundo sem backfill.
  def enabled_for(account)
    disabled = Ai::Manager::CheckSetting.disabled_keys_for(account)
    all.reject { |check| disabled.include?(check.key) }
  end
end
