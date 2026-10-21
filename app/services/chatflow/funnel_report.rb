# Funil por bloco de um fluxo, a partir das execuções (visited_node_ids).
#
# Para cada etapa:
#   entered  — execuções que passaram por ela;
#   waiting  — paradas nela agora (esperando resposta, relógio ou pausadas);
#   dropped  — terminaram nela (o fluxo acabou ali ou foi interrompido);
#   advanced — seguiram adiante (entered - waiting - dropped).
# Numa etapa "Fim", terminar é o esperado: conta como `completed`, não como saída.
class Chatflow::FunnelReport
  def initialize(chatflow, since: 30.days.ago)
    @chatflow = chatflow
    @since = since
  end

  def perform
    { totals: totals, nodes: nodes, since: @since.iso8601 }
  end

  private

  def scope
    @chatflow.executions.where(created_at: @since..)
  end

  def totals
    counts = scope.group(:status).count
    {
      started: counts.values.sum,
      completed: counts.fetch('completed', 0),
      aborted: counts.fetch('aborted', 0),
      live: counts.fetch('active', 0) + counts.fetch('waiting_input', 0),
      paused: counts.fetch('paused', 0)
    }
  end

  def nodes
    entered = count_by_node('unnest(visited_node_ids)')
    last = ended_on_node
    waiting = scope.where(status: %i[active waiting_input paused]).group(:current_node_id).count
    ends = @chatflow.nodes.kind_end_flow.pluck(:id)

    @chatflow.nodes.pluck(:id).map do |id|
      node_row(id, entered.fetch(id, 0), waiting.fetch(id, 0), last.fetch(id, 0), ends.include?(id))
    end
  end

  def node_row(id, total, here, stopped, end_node)
    { node_id: id, entered: total, waiting: here, dropped: end_node ? 0 : stopped,
      completed: end_node ? stopped : 0, advanced: [total - here - stopped, 0].max }
  end

  # A última etapa visitada das execuções que já terminaram.
  def ended_on_node
    scope.where(status: %i[completed aborted]).where.not(visited_node_ids: [])
         .group(Arel.sql('visited_node_ids[array_length(visited_node_ids, 1)]')).count
  end

  def count_by_node(expression)
    ChatflowExecution.from(scope.select(Arel.sql("#{expression} AS node_id")), :visits)
                     .group('visits.node_id').count
  end
end
