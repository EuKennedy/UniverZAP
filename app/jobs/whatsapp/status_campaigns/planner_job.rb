# Mantém a janela de agendados das campanhas ativas sempre cheia. Sem um
# `campaign_id`, passa por todas (cron); com ele, replaneja só aquela (ao
# ativar ou editar), para o calendário mostrar o resultado na hora.
class Whatsapp::StatusCampaigns::PlannerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(campaign_id = nil)
    scope = WhatsappStatusCampaign.status_active.includes(steps: { media_attachment: :blob })
    scope = scope.where(id: campaign_id) if campaign_id
    scope.find_each { |campaign| Whatsapp::StatusCampaigns::Planner.new(campaign).plan! }
  end
end
