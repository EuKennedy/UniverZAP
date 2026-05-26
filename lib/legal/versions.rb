# Single source of truth for legal document versions. Bumping a value here
# forces every signed-in user to re-accept on the next dashboard load
# (via LegalReAcceptBanner). Keep the changelog in sync — the public pages
# render it as a "What changed" section.
module Legal::Versions
  TERMS = '2026-05-26'.freeze
  PRIVACY = '2026-05-26'.freeze

  TERMS_CHANGELOG = [
    {
      version: '2026-05-26',
      date: '2026-05-26',
      highlights: [
        'Versão inicial publicada com cobertura LGPD (Lei 13.709/2018).',
        'Detalhamento de operadores (sub-processadores) e foro contratual.',
        'Cláusula explícita sobre WhatsApp Business API e riscos operacionais.'
      ]
    }
  ].freeze

  PRIVACY_CHANGELOG = [
    {
      version: '2026-05-26',
      date: '2026-05-26',
      highlights: [
        'Política inicial publicada conforme Art. 9º da LGPD.',
        'Bases legais, finalidades, retenção e direitos do titular declarados.',
        'Lista atualizada de sub-processadores: Coolify, Sentry, Anthropic, Univercart.'
      ]
    }
  ].freeze
end
