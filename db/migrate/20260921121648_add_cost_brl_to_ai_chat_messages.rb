# O preço da resposta, na moeda em que o operador pensa.
#
# A tabela já guardava cost_usd, mas a conversão mora em Ai::PricingCalculator
# junto do markup — deixar o navegador converter seria espalhar a regra de preço
# por duas casas, e a primeira mudança de câmbio faria a tela e a fatura
# discordarem.
class AddCostBrlToAiChatMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_chat_messages, :cost_brl, :float, default: 0.0
  end
end
