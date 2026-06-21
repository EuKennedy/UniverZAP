# Public product documentation. No authentication, no session, no cookies.
# Self-contained HTML page (own <style>), dark-first, brand palette.
# Versioned so crawlers/users see the published doc version + changelog.
class DocsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  layout false

  VERSION = '2026.06'.freeze

  CHANGELOG = [
    { version: '2026.06', date: '2026-06-21', notes: 'Anexos em Tarefas, documentação pública /docs, metas personalizadas.' },
    { version: '2026.05', date: '2026-05-28', notes: 'Onboarding guiado estilo ClickUp, Chatflow humanizado, paleta UniverZAP #13CB8D.' },
    { version: '2026.04', date: '2026-04-30', notes: 'Construtor de Chatflow, funis Kanban, assistentes Athenas IA.' },
    { version: '2026.03', date: '2026-03-31', notes: 'Campanhas com variáveis de template, relatórios e metas.' }
  ].freeze

  def show
    @version = VERSION
    @changelog = CHANGELOG
  end
end
