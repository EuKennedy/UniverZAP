require 'csv'

class Kanban::CsvExportService
  HEADERS = [
    'ID interno', 'Display ID', 'Título', 'Etapa', 'Prioridade',
    'Atendentes', 'Etiquetas', 'Contatos', 'Conversas',
    'Data início', 'Data vencimento', 'Estimativa (min)',
    'Concluída em', 'Criada em', 'Atualizada em'
  ].freeze

  def initialize(tasks, funnel)
    @tasks = tasks
    @funnel = funnel
  end

  def call
    CSV.generate(force_quotes: true) do |csv|
      csv << ['Funil', @funnel.name]
      csv << ['Exportado em', Time.current.iso8601]
      csv << []
      csv << HEADERS
      @tasks.each { |task| csv << row(task) }
    end
  end

  private

  def row(task)
    [
      task.id, task.display_id, task.title,
      task.funnel_stage&.name, task.priority,
      task.assignees.map(&:name).join('; '),
      task.task_labels.map(&:title).join('; '),
      task.contacts.map(&:name).join('; '),
      task.conversations.map { |c| "##{c.display_id}" }.join('; '),
      task.start_date, task.due_date, task.estimate_minutes,
      task.completed_at, task.created_at, task.updated_at
    ]
  end
end
