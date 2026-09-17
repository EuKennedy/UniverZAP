# O manual do produto, lido da MESMA página que as pessoas leem.
#
# A fonte é app/views/docs/show.html.erb, servida em /docs: 16 seções em
# português, cada uma num `<section id>` com o título no `<h2>`. Derivar daqui
# em vez de copiar o texto para uma segunda tabela é o ponto: manual e agente
# discordarem é pior que não ter agente nenhum, e a maneira mais confiável de
# discordarem é alguém editar a página e esquecer da cópia.
#
# O ERB é lido como arquivo e não renderizado: a página não depende de nenhuma
# variável de instância, e renderizar traria o layout, o CSS e o JS de busca
# junto — lixo que ocuparia o orçamento de recuperação sem ensinar nada.
class Ai::Wiki::Manual
  SOURCE = Rails.root.join('app/views/docs/show.html.erb')

  # Seções que não ensinam nada a quem pergunta como usar o produto. `versoes` é
  # changelog e `suporte` é um cartão de contato; as duas roubariam vaga no
  # orçamento de 6.000 caracteres de uma seção que responde de verdade.
  SKIP = %w[versoes suporte].freeze

  Section = Struct.new(:slug, :title, :body, keyword_init: true)

  def self.sections
    new.sections
  end

  def sections
    @sections ||= document.css('section[id]').filter_map { |node| section_for(node) }
  end

  private

  def document
    # O ERB tem tags <%= %> apenas no cabeçalho e no rodapé; o Nokogiri as trata
    # como texto e elas nunca caem dentro de uma <section>, que é tudo que lemos.
    # Encoding explícito: o manual é em português e a leitura sem ele depende do
    # ambiente. Um acento lido errado vira pergunta sem resposta no ranking.
    @document ||= Nokogiri::HTML(File.read(SOURCE, mode: 'r:UTF-8'))
  end

  def section_for(node)
    slug = node['id'].to_s
    return nil if slug.blank? || SKIP.include?(slug)

    title = node.at_css('h2')&.text.to_s.strip
    body = readable(node)
    return nil if title.blank? || body.blank?

    Section.new(slug: slug, title: title, body: body)
  end

  # Texto corrido, com as quebras que a estrutura implica. Sem isso uma tabela de
  # conceitos vira uma linha só de palavras coladas, e o modelo lê "Caixa de
  # entradaCanal conectadoContato" como se fosse um termo.
  def readable(node)
    copy = node.dup
    copy.at_css('h2')&.remove
    copy.css('br').each { |br| br.replace("\n") }
    copy.css('li, p, h3, h4, tr, div').each { |block| block.add_next_sibling("\n") }
    copy.css('td, th').each { |cell| cell.add_next_sibling(' — ') }

    copy.text.gsub(/[ \t]+/, ' ').gsub(/ *\n */, "\n").gsub(/\n{3,}/, "\n\n").strip
  end
end
