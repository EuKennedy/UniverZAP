# Modelos prontos de fluxo por vertical, lidos de lib/chatflow_templates.
#
# Instalar um modelo cria um fluxo NORMAL, em rascunho e sem modo de teste: o
# dono lê os textos, ajusta e só então ativa. Número não oficial não pode
# começar a mandar mensagem porque alguém clicou em "usar modelo".
#
# No YAML, etiquetas são citadas pelo título (`label_titles`) — a conta pode
# ainda não ter a etiqueta; ela é criada na hora e vira `label_ids`.
class Chatflow::TemplateLibrary
  TEMPLATES_DIR = Rails.root.join('lib/chatflow_templates')

  Template = Struct.new(:key, :vertical, :name, :description, :category, :icon, :trigger_type, :trigger_config,
                        :start, :nodes, :edges, keyword_init: true) do
    def summary
      { key: key, vertical: vertical, name: name, description: description, category: category, icon: icon,
        trigger_type: trigger_type, nodes_count: nodes.size, kinds: nodes.map { |n| n['kind'] }.uniq }
    end
  end

  # Os modelos do vertical da conta; sem vertical, todos.
  def self.available(account)
    vertical = account.custom_attributes.to_h['vertical_template'].to_s
    pattern = vertical.present? ? "#{vertical}/*.yml" : '*/*.yml'
    paths = Dir.glob(TEMPLATES_DIR.join(pattern))
    paths = Dir.glob(TEMPLATES_DIR.join('*/*.yml')) if paths.empty?
    paths.sort.map { |path| load(path) }
  end

  def self.find(key)
    return unless key.to_s.match?(%r{\A[a-z0-9_]+/[a-z0-9_]+\z})

    path = TEMPLATES_DIR.join("#{key}.yml")
    load(path) if File.exist?(path)
  end

  def self.load(path)
    raw = YAML.safe_load(File.read(path))
    Template.new(
      key: "#{File.basename(File.dirname(path))}/#{File.basename(path, '.yml')}", vertical: File.basename(File.dirname(path)),
      name: raw['name'], description: raw['description'], category: raw['category'], icon: raw['icon'],
      trigger_type: raw['trigger_type'], trigger_config: raw['trigger_config'].to_h, start: raw['start'],
      nodes: Array(raw['nodes']), edges: Array(raw['edges'])
    )
  end

  def initialize(account:, template:)
    @account = account
    @template = template
  end

  def install!
    Chatflow.transaction do
      chatflow = @account.chatflows.create!(
        name: @template.name, description: @template.description, status: :draft,
        trigger_type: @template.trigger_type, trigger_config: trigger_config
      )
      nodes = create_nodes(chatflow)
      create_edges(chatflow, nodes)
      chatflow.update!(start_node: nodes[@template.start])
      chatflow
    end
  end

  private

  def trigger_config
    config = @template.trigger_config.except('label_titles')
    titles = @template.trigger_config['label_titles']
    config['label_ids'] = label_ids(titles) if titles.present?
    config.merge('position_x' => -320, 'position_y' => 0)
  end

  def create_nodes(chatflow)
    @template.nodes.to_h do |node|
      record = chatflow.nodes.create!(
        account: @account, kind: node['kind'], name: node['name'].to_s,
        position_x: node['x'].to_f, position_y: node['y'].to_f, config: node_config(node['config'].to_h)
      )
      [node['key'], record]
    end
  end

  def node_config(config)
    titles = config.delete('label_titles')
    config['label_ids'] = label_ids(titles) if titles
    config
  end

  def create_edges(chatflow, nodes)
    @template.edges.each do |source, handle, target|
      chatflow.edges.create!(account: @account, source_node: nodes.fetch(source), target_node: nodes.fetch(target),
                             source_handle: handle.to_s)
    end
  end

  def label_ids(titles)
    Array(titles).map { |title| @account.labels.find_or_create_by!(title: title).id }
  end
end
