# Several tool executors behind one `call(name, input)`.
#
# A salon sells products AND books chairs, so an agent has to be able to hold
# the workspace's HTTP integrations and its agenda in the SAME turn. Before
# this, the router picked one and returned, and an agent with a UniverCart tool
# could never reach its calendar no matter how the customer asked.
#
# Routing is by tool name, resolved once at construction: a name belongs to
# exactly one executor, and an unknown one is reported rather than guessed at.
class Ai::Agent::CompositeExecutor
  # `parts` is [[definitions, executor], ...] in the order they should be
  # offered to the model.
  def initialize(parts)
    @parts = parts.reject { |definitions, _| definitions.blank? }
    @owner = {}
    @parts.each do |definitions, executor|
      definitions.each { |definition| @owner[definition[:name].to_s] ||= executor }
    end
  end

  def definitions
    @parts.flat_map(&:first)
  end

  def any?
    @parts.any?
  end

  def call(name, input)
    executor = @owner[name.to_s]
    return { error: true, message: "A ferramenta #{name} não existe." }.to_json if executor.nil?

    executor.call(name, input)
  end

  # True once ANY of them wrote. The turn is non-replayable if a single booking
  # or cart POST was attempted, not only if the last one was.
  def performed_write?
    @parts.any? { |_, executor| executor.respond_to?(:performed_write?) && executor.performed_write? }
  end
end
