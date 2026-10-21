# Transforma o fluxo de uma campanha em WhatsappStatusPost agendados.
#
# Só olha uma janela curta à frente (HORIZON): uma campanha que recomeça a
# cada 7 dias não tem fim, então em vez de gerar o ano inteiro o PlannerJob
# passa de tempos em tempos e completa o que entrou na janela. Cada saída tem
# uma chave (ciclo, passo, repostagem) com índice único, então rodar duas
# vezes nunca agenda o mesmo status duas vezes.
class Whatsapp::StatusCampaigns::Planner
  HORIZON = 14.days

  Occurrence = Struct.new(:at, :step, :round, :repost, keyword_init: true) do
    def key
      "c#{round}-s#{step.id}-r#{repost}"
    end
  end

  def initialize(campaign, now: Time.current)
    @campaign = campaign
    @now = now
  end

  # As saídas futuras dentro da janela, em ordem. Também alimenta a prévia
  # "próximas postagens" do editor, sem gravar nada.
  def occurrences(until_at: @now + HORIZON)
    return [] if @campaign.starts_on.blank?

    all = cycle_starts(until_at).flat_map { |start, round| occurrences_of_cycle(start, round) }
    all.select { |occurrence| occurrence.at > @now && occurrence.at <= until_at }.sort_by(&:at)
  end

  def plan!
    return unless @campaign.status_active?

    occurrences.each { |occurrence| schedule(occurrence) }
    finish_if_done!
  end

  private

  def occurrences_of_cycle(start, round)
    @campaign.steps.flat_map do |step|
      step.times_on(start, @campaign.zone).each_with_index.map do |at, repost|
        Occurrence.new(at: at, step: step, round: round, repost: repost)
      end
    end
  end

  # Os começos de ciclo que podem ter saídas na janela. Ciclos que começaram
  # antes de hoje entram também, porque um passo do dia 5 ainda pode estar no
  # futuro.
  def cycle_starts(until_at)
    first = @campaign.starts_on
    return [[first, 0]] unless @campaign.cycling?

    last_day = [until_at.to_date, @campaign.ends_on].compact.min
    (first_round..((last_day - first).to_i / @campaign.cycle_days)).map do |round|
      [first + (round * @campaign.cycle_days).days, round]
    end
  end

  def first_round
    span = @campaign.steps.map(&:day_offset).max.to_i + 1
    [((@now.to_date - @campaign.starts_on).to_i - span) / @campaign.cycle_days, 0].max
  end

  def schedule(occurrence)
    return if @campaign.posts.exists?(occurrence_key: occurrence.key)

    step = occurrence.step
    post = @campaign.account.whatsapp_status_posts.new(
      user_id: @campaign.user_id, campaign: @campaign, campaign_step: step, occurrence_key: occurrence.key,
      kind: step.kind, body: step.body, background_color: step.background_color, font: step.font,
      inbox_ids: @campaign.inbox_ids, status: :scheduled, scheduled_at: occurrence.at
    )
    post.media = step.media.blob if step.media.attached?
    post.save!
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Sem ciclo, a campanha acaba quando não sobra nenhuma saída futura: nem na
  # janela, nem agendada.
  def finish_if_done!
    return if @campaign.cycling?
    return if occurrences(until_at: @now + 5.years).any? || @campaign.posts.status_scheduled.exists?

    @campaign.update!(status: :finished)
  end
end
