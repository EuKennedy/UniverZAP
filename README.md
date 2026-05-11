<p align="center">
  <img src="./public/brand-assets/logo.svg" width="420" alt="UniverZAP" />
</p>

<h1 align="center">UniverZAP</h1>

<p align="center">
  Plataforma de atendimento e vendas conversacionais — WhatsApp não-oficial, Kanban, automações de disparo, integrações nativas com WooCommerce e agentes de IA.
</p>

<p align="center">
  <a href="https://staging.univerzap.cloud">staging.univerzap.cloud</a> ·
  <a href="https://github.com/EuKennedy/UniverZAP/issues">Issues</a> ·
  <a href="./NOTICE.md">Atribuição</a>
</p>

---

## O que é

UniverZAP é uma plataforma multi-tenant de atendimento e vendas via WhatsApp, construída a partir de um fork da plataforma open-source [Chatwoot](https://github.com/chatwoot/chatwoot) (MIT) e estendida com features pensadas para operações de e-commerce brasileiras.

Diferenças centrais em relação ao upstream:

- **Inboxes WhatsApp não-oficiais nativas**: WAHA, Evolution API e Z-API com setup por QR-code in-app, sem precisar de Meta Business.
- **Kanban de conversas**: pipeline visual (lead → qualificando → proposta → fechado) por inbox.
- **Automações de disparo**: campanhas com segmentação por tag/atributo, agendamento, throttling por canal.
- **Integração WooCommerce nativa**: webhooks para carrinho abandonado, leads não-convertidos, sync de catálogo.
- **Aba de contatos friendly**: timeline, dedup automático, import CSV decente.
- **Agentes de IA plugáveis**: Anthropic, OpenAI ou modelos locais com handoff humano transparente.
- **Multi-tenant**: cada `Account` é isolado; pronto para revender em SaaS white-label.

## Stack

| Camada | Tecnologia |
|--------|------------|
| Backend | Ruby 3.4.4, Rails 7.1, Sidekiq, Pundit, Devise |
| Frontend | Vue 3 (Composition API + `<script setup>`), Vite, Tailwind, Pinia |
| Dados | PostgreSQL 16 (`pgvector`), Redis 7 |
| Storage | Cloudflare R2 (S3-compatible) |
| Email | Mailgun |
| Deploy | Docker Compose + [Coolify](https://coolify.io) |
| Observabilidade | Sentry, Lograge, Sidekiq Web |

## Quick start (desenvolvimento local)

Pré-requisitos: `rbenv`, `pnpm`, Docker (para Postgres + Redis), `overmind`.

```bash
# 1. Clone
git clone https://github.com/EuKennedy/UniverZAP.git
cd UniverZAP

# 2. Instalar Ruby/Node
rbenv install $(cat .ruby-version)
bundle install
pnpm install

# 3. Configurar env
cp .env.example .env
# Editar .env com DBs locais, etc.

# 4. Subir dependências de dados
docker compose -f docker-compose.yaml up -d postgres redis

# 5. Preparar banco
bundle exec rails db:setup

# 6. Subir aplicação
pnpm dev
```

App em `http://localhost:3000`.

## Deploy (Coolify)

Veja [docs/DEPLOY-COOLIFY.md](docs/DEPLOY-COOLIFY.md) para o passo a passo completo.

Resumo: Coolify aponta para este repositório no GitHub → seleciona `docker-compose.production.yaml` → seta as ENV vars do `.env.example` → conecta domínio (`staging.univerzap.cloud`) → deploy automático em cada push para `main`.

## Roadmap

- [x] **Fase 0** — Saneamento + rebrand
- [x] **Fase 1** — Deploy base no Coolify
- [ ] **Fase 2** — Inbox WhatsApp não-oficial (WAHA, Evolution, Z-API) com QR code in-app
- [ ] **Fase 3** — Kanban de conversas por inbox
- [ ] **Fase 4** — Automações de disparo (campanhas, throttling, segmentação)
- [ ] **Fase 5** — Integração WooCommerce nativa
- [ ] **Fase 6** — Aba de contatos friendly (refresh visual + dedup)
- [ ] **Fase 7** — Agentes de IA nativos com handoff humano

## Atribuição e licença

Este projeto é um fork de [Chatwoot](https://github.com/chatwoot/chatwoot). O core é distribuído sob licença MIT — veja [LICENSE](LICENSE). Detalhes adicionais sobre atribuição, marcas e tratamento da pasta `enterprise/` estão em [NOTICE.md](NOTICE.md).

UniverZAP não é afiliado, endossado nem patrocinado por Chatwoot Inc.

---

<p align="center">
  © 2026 Kennedy Rodrigues · Construído para escalar.
</p>
