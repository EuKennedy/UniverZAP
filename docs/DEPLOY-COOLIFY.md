# Deploy UniverZAP no Coolify

Guia passo-a-passo para colocar o UniverZAP rodando em `staging.univerzap.cloud` numa VPS Hostinger 16GB com Coolify já instalado.

---

## Pré-requisitos

- VPS com Coolify ≥ v4 instalado e acessível.
- GitHub do Coolify conectado ao repositório `EuKennedy/UniverZAP`.
- Domínio `univerzap.cloud` gerenciado no Cloudflare.
- Conta Mailgun configurada para o domínio `mg.univerzap.cloud`.
- **Opcional**: Bucket Cloudflare R2 para anexos. Sem ele, o storage cai pro disco da VPS via volume `storage_data` (default). Migrar pra R2 depois é um script de ~1h.

---

## 1. DNS

No Cloudflare → DNS → Records, criar:

| Tipo  | Nome      | Conteúdo                  | Proxy |
|-------|-----------|---------------------------|-------|
| A     | staging   | `<IP_DA_VPS>`             | DNS only |

> Mantenha o proxy desabilitado até o primeiro deploy concluir e o certificado Let's Encrypt ser emitido pelo Coolify. Depois pode ativar o proxy.

---

## 2. Criar a aplicação no Coolify

1. **+ New → Application → Public Repository (ou GitHub App)**
2. Repositório: `https://github.com/EuKennedy/UniverZAP`
3. Branch: `univerzap/phase-0-saneamento` (depois migramos pra `main`)
4. Build Pack: **Docker Compose**
5. Docker Compose Location: `docker-compose.production.yaml`
6. Base Directory: `/`

---

## 3. Variáveis de ambiente

No painel da aplicação → **Environment Variables**, importar o `.env.example` (Coolify tem botão "Import Environment Variables") e ajustar:

### Obrigatórias
```
SECRET_KEY_BASE              # gerar com: openssl rand -hex 64
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
POSTGRES_PASSWORD            # senha forte
REDIS_PASSWORD               # senha forte (mesma que será usada no REDIS_URL)
REDIS_URL                    # redis://:<REDIS_PASSWORD>@redis:6379
```

### Domínio (Coolify Magic FQDN)
```
SERVICE_FQDN_RAILS_3000=staging.univerzap.cloud
FRONTEND_URL=https://staging.univerzap.cloud
HELPCENTER_URL=https://staging.univerzap.cloud
```

### Mailgun
```
SMTP_USERNAME=postmaster@mg.univerzap.cloud
SMTP_PASSWORD=<mailgun smtp password>
MAILGUN_INGRESS_SIGNING_KEY=<mailgun webhook signing key>
```

### Storage (default: disco local da VPS)
Não precisa configurar nada — o `.env.example` ships com `ACTIVE_STORAGE_SERVICE=local` e o compose monta o volume `storage_data` em `/app/storage`.

#### Migrando pra Cloudflare R2 depois
Quando uso de anexos passar de ~50GB ou escalar pra múltiplas instâncias:

1. Criar bucket R2 + API token + CORS (ver seção Troubleshooting).
2. Trocar/adicionar no Coolify Environment Variables:
   ```
   ACTIVE_STORAGE_SERVICE=cloudflare
   STORAGE_BUCKET_NAME=univerzap-staging-attachments
   STORAGE_ACCESS_KEY_ID=<R2 access key id>
   STORAGE_SECRET_ACCESS_KEY=<R2 secret>
   STORAGE_ENDPOINT=https://<r2_account_id>.r2.cloudflarestorage.com
   STORAGE_REGION=auto
   DIRECT_UPLOADS_ENABLED=true
   ```
3. Copiar arquivos existentes do volume `storage_data` pro bucket (`rclone` resolve em ~1h).
4. Redeploy.

> Onde achar o `<r2_account_id>`: Cloudflare Dashboard → R2 → no canto superior direito do menu de buckets.

### VAPID (push notifications)
```
VAPID_PUBLIC_KEY=<gerado em https://d3v.one/vapid-key-generator/>
VAPID_PRIVATE_KEY=<idem>
```

---

## 4. Configurar persistência

No painel → **Storage**, verificar que os volumes nomeados estão criados (Coolify cria automático na primeira deploy):

- `storage_data` — anexos locais (fallback, mesmo usando R2).
- `postgres_data` — dados do Postgres.
- `redis_data` — AOF do Redis.

---

## 5. Configurar domínio no serviço `rails`

No painel → **Domains** do container `rails`:

- Domain: `https://staging.univerzap.cloud`
- Port: `3000`
- "Generate Let's Encrypt SSL Certificate": ✅

---

## 6. Primeiro deploy

1. Salvar tudo.
2. Clicar em **Deploy**.
3. Acompanhar logs em **Deployments → Latest**.
4. O entrypoint do Rails roda automaticamente `db:create db:migrate` (ver `docker/entrypoints/rails.sh`).

Tempo esperado da primeira build: **~6-9 minutos** (assets Vite + bundle install + migrate).

---

## 7. Pós-deploy

### Criar o super admin
Coolify → container `rails` → **Terminal**:

```bash
bundle exec rails c
> User.create!(name: 'Kennedy', email: 'kennedy.rodrigues1104@gmail.com', password: 'TROQUE_ME', custom_attributes: { type: 'SuperAdmin' })
> SuperAdmin.create!(email: 'kennedy.rodrigues1104@gmail.com')
```

Acesso ao super admin: `https://staging.univerzap.cloud/super_admin`.

### Testes rápidos de smoke
- `https://staging.univerzap.cloud/api` → deve retornar JSON com versão.
- `https://staging.univerzap.cloud/app/auth/signin` → tela de login com logo UniverZAP.
- Logar como super admin → criar conta de teste.

---

## 8. Webhook automático (Auto-deploy)

No Coolify → **Webhooks**:

- Webhook URL será gerada automaticamente.
- Cole no GitHub → `EuKennedy/UniverZAP` → **Settings → Webhooks → Add webhook**.
  - Payload URL: a do Coolify.
  - Content type: `application/json`.
  - Events: "Just the push event".
  - Branch: `main` (depois que migrarmos a partir de `univerzap/phase-0-saneamento`).

Toda nova push em `main` ⇒ deploy automático.

---

## Troubleshooting

### "Could not find an executable" no entrypoint
Build cacheada com versão antiga. Coolify → **Redeploy with cache cleared**.

### Postgres "FATAL: password authentication failed"
`POSTGRES_PASSWORD` foi alterada depois do volume existir. Opções:
1. Mudar a senha dentro do Postgres via `psql`, ou
2. Apagar o volume `postgres_data` (perde dados) e redeploy.

### Sidekiq não processa jobs
Checar se `REDIS_URL` aponta para o serviço interno (`redis:6379`) e se `REDIS_PASSWORD` bate.

### Anexos não aparecem
Conferir CORS no R2 bucket:
```json
[
  {
    "AllowedOrigins": ["https://staging.univerzap.cloud"],
    "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3600
  }
]
```
