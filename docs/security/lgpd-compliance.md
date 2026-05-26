# LGPD compliance — UniverZAP

Mapa de implementação dos artigos da Lei 13.709/2018 dentro da Plataforma.
Atualizado em **2026-05-26**. Mudanças vão para `git log` + bump da versão
em `lib/legal/versions.rb`.

## Artigos vs implementação

| Artigo | Direito / dever | Onde implementado |
|--------|-----------------|-------------------|
| Art. 7º | Bases legais | `/termos` + `/privacidade` |
| Art. 8º | Consentimento livre/informado | `LegalReAcceptBanner` (Vue) + `POST /api/v1/profile/accept_terms` |
| Art. 9º | Direito à informação | `/privacidade` (seções 2-4) |
| Art. 18 I | Confirmação de tratamento | `/conta/profile` (dashboard) |
| Art. 18 II | Acesso aos dados | `GET /api/v1/profile/lgpd_export` |
| Art. 18 III | Correção | `/conta/profile` (PUT) |
| Art. 18 IV | Anonimização/bloqueio | `DELETE /api/v1/profile/lgpd_delete` |
| Art. 18 V | Portabilidade | `GET /api/v1/profile/lgpd_export` (JSON download) |
| Art. 18 VI | Eliminação | `DELETE /api/v1/profile/lgpd_delete` |
| Art. 18 VII | Info sobre compartilhamento | `/privacidade` § 4 (sub-processadores) |
| Art. 18 VIII | Possibilidade de negar consentimento | `CookieConsentBanner` (futuro) |
| Art. 18 IX | Revogação | `/conta/profile` + `DELETE lgpd_delete` |
| Art. 41 | DPO | `privacidade@univerbeauty.com.br` |
| Art. 46 | Salvaguardas | AES-256-GCM + bcrypt + JWT + 2FA + Sentry scrub |
| Art. 48 | Comunicação de incidente | `docs/incident-template.md` |

## Salvaguardas técnicas (Art. 46)

| Item | Implementação | Caminho |
|------|---------------|---------|
| TLS 1.2+ | Coolify/Nginx termina TLS | infra |
| Senhas | bcrypt cost 11 (Devise default) | `config/initializers/devise.rb` |
| Credenciais em repouso | ActiveRecord encrypts em campos sensíveis | `app/models/channel/*` |
| 2FA TOTP | Devise + `otplib` | `app/controllers/api/v1/profile/mfa_controller.rb` |
| Multi-tenant isolation | `Current.account` em toda query scoped | `app/controllers/concerns/auth_helper.rb` |
| Webhook HMAC | SHA-256 + replay window 5min | `lib/univercart/signature.rb` |
| Magic-link single-use | Tabela `univercart_processed_events` + `Univercart::Redeem` | `lib/univercart/redeem.rb` |
| Idempotência webhook | `UnivercartProcessedEvent.id @id` | `app/models/univercart_processed_event.rb` |
| Sentry PII scrub | Recursive scrubber + 4 regex BR | `config/initializers/sentry.rb` |
| Audit log | Audited gem | `app/models/*.rb` (`audited` em models críticos) |
| Health probe sem PII | Detalhado só com `X-Health-Secret` | `app/controllers/health_controller.rb` |
| Backups | pg_dump via Coolify cron 6h | infra |

## Sub-processadores ativos

Lista publicada em `/privacidade` § 4. Bumpar a versão sempre que mudar:

- Coolify (Hetzner / Alemanha) — hosting + Postgres
- Sentry (EUA) — telemetria de erros (PII scrubada antes do envio)
- Anthropic Claude (EUA) — Athenas AI
- Univercart (Brasil) — cobrança
- WAHA / Meta WhatsApp (EUA) — canal WhatsApp

## Retenção

| Tipo | Retenção | Mecanismo |
|------|----------|-----------|
| Conta ativa | enquanto ativa | manual via dashboard |
| Conta excluída | 30 dias para purge final de FKs cascade | `Lgpd::UserDeleteService` |
| Audit log | 5 anos anonimizado | Audited::Audit + `anonymize_audits` |
| Magic-link redemption | 24h | cron diário (a implementar) |
| Webhook events | 90 dias | cron mensal (a implementar) |
| Sessions JWT | 30 dias | Devise + token_auth TTL |
| Mensagens (conversas) | retenção do tenant (default ilimitado) | conforme contrato |

## Endpoints LGPD (direitos do titular)

Todos exigem autenticação do próprio titular (`current_user`).

```http
POST /api/v1/profile/accept_terms
Body: { terms_version: "AAAA-MM-DD", privacy_version: "AAAA-MM-DD" }
→ 200 OK
```

```http
GET /api/v1/profile/lgpd_export
→ 200 application/json (download)
Filename: univerzap-export-<user_id>-<ts>.json
```

```http
DELETE /api/v1/profile/lgpd_delete
→ 200 OK (User destruído, audits anonimizados)
```

## Telemetria — scrubbing PII

Antes de qualquer evento sair para o Sentry, o `before_send` recursivamente:

1. Filtra **chaves sensíveis**: password, token, api_key, secret, jwt,
   authorization, cookie, cpf, cnpj, rg, ssn, etc.
2. Roda **regex de PII** em todo `String`: e-mail, telefone BR (com/sem 9),
   CPF (`123.456.789-00`), CNPJ (`12.345.678/0001-00`).
3. Limpa `event.user.email`, `event.user.username`, `event.user.ip_address`.
4. Remove headers `Cookie`, `Authorization`, `X-Api-Key`.

Implementação em `config/initializers/sentry.rb`.

## O que ainda falta (próxima fase)

- [ ] `LegalReAcceptBanner.vue` montado no dashboard
- [ ] `CookieConsentBanner.vue` com escolha "essenciais / todos"
- [ ] Cron diário: purge `MagicLinkRedemption > 24h`
- [ ] Cron mensal: drill de restore de backup
- [ ] Playwright `e2e/security-comprehensive.spec.ts`
- [ ] DPA (Data Processing Agreement) formal com cada operador (Art. 39)
- [ ] RIPD/DPIA formal (Art. 38)
