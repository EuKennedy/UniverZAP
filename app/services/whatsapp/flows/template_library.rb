# Modelos prontos de Flow por vertical, lidos de lib/whatsapp_flows/templates.
#
# O operador não desenha tela: escolhe "Agendamento" e sai com um Flow cujos
# campos já apontam para os atributos e etiquetas do vertical dele. As opções
# de um campo marcado com `$attribute` vêm da lista do atributo da conta, para
# o formulário oferecer os MESMOS serviços que o painel conhece.
class Whatsapp::Flows::TemplateLibrary
  TEMPLATES_DIR = Rails.root.join('lib/whatsapp_flows/templates')

  Template = Struct.new(:key, :name, :description, :category, :flow_json, :field_mappings, :attribute_definitions,
                        keyword_init: true)

  # Só os modelos do vertical da conta; sem vertical, todos — um salão que
  # ainda não escolheu vertical não pode ficar sem formulário por isso.
  def self.available(account)
    vertical = account.custom_attributes.to_h['vertical_template'].to_s
    pattern = vertical.present? ? "#{vertical}/*.yml" : '*/*.yml'
    Dir.glob(TEMPLATES_DIR.join(pattern)).map { |path| load(path) }
  end

  def self.find(key)
    path = TEMPLATES_DIR.join("#{key}.yml")
    return unless key.to_s.match?(%r{\A[a-z0-9_]+/[a-z0-9_]+\z}) && File.exist?(path)

    load(path)
  end

  def self.load(path)
    raw = YAML.safe_load(File.read(path))
    Template.new(
      key: "#{File.basename(File.dirname(path))}/#{File.basename(path, '.yml')}",
      name: raw['name'], description: raw['description'], category: raw['category'],
      flow_json: raw['flow_json'], field_mappings: raw['field_mappings'] || {},
      attribute_definitions: raw['attribute_definitions'] || []
    )
  end

  def initialize(account:, template:)
    @account = account
    @template = template
  end

  # Garante os atributos que o mapeamento vai preencher e devolve o Flow JSON
  # com as listas resolvidas. Cria só o que falta, nunca mexe no que existe.
  def build
    ensure_attribute_definitions!
    resolve(@template.flow_json.deep_dup)
  end

  private

  def ensure_attribute_definitions!
    @template.attribute_definitions.each do |attribute|
      @account.custom_attribute_definitions.find_or_create_by!(
        attribute_key: attribute['attribute_key'], attribute_model: attribute['attribute_model']
      ) do |record|
        record.attribute_display_name = attribute['attribute_display_name']
        record.attribute_display_type = attribute['attribute_display_type']
        record.attribute_values = attribute['attribute_values'] || []
      end
    end
  end

  def resolve(node)
    case node
    when Hash
      return option_list(node['$attribute']) if node.key?('$attribute')

      node.transform_values { |value| resolve(value) }
    when Array
      node.map { |value| resolve(value) }
    else
      node
    end
  end

  # Ids em ascii e sem espaço: é o que volta no complete e o que a Meta aceita
  # como id de opção. O título continua como o operador escreveu.
  def option_list(attribute_key)
    values = @account.custom_attribute_definitions.find_by(attribute_key: attribute_key)&.attribute_values
    values = Array(values).map(&:to_s).compact_blank
    values = fallback_values(attribute_key) if values.empty?
    values.map { |value| { 'id' => value.parameterize(separator: '_'), 'title' => value } }
  end

  def fallback_values(attribute_key)
    definition = @template.attribute_definitions.detect { |attribute| attribute['attribute_key'] == attribute_key }
    Array(definition&.dig('attribute_values')).map(&:to_s)
  end
end
