# UniverZAP — On-Call Runbook

> Last reviewed: keep current with every infra change. Owners: founders + ops.

This is the field manual for anything that pages you between business
hours. Every section starts with the **symptom**, then the **first
five minutes** of triage, then the **fix** in order from cheapest to
most surgical.

---

## 0. First five minutes — every incident

1. **Acknowledge** the page. Don't leave it pending: silence breeds
   parallel actions.
2. Open `https://app.univerzap.cloud/status` and check
   `/health?detail=1`. If "operational" → look at customer reports
   first; if "degraded" → jump to the failing service section below.
3. Open Sentry → filter `environment:production`, sort by recent.
   First-class signals: 5xx surges, deploys, new exception classes.
4. Open Coolify dashboard → check container health and last deploy
   commit SHA. If the deploy happened in the last 30 minutes, the
   prime suspect is your own change.
5. If customers are blocked, post in `#status` (or WhatsApp group)
   even before the fix lands. Silence is more damaging than a "we
   are investigating".

---

## 1. WhatsApp messages not landing (WAHA path)

**Symptom.** Customer says "mandei mensagem e não chegou".

**Triage.**

- Open `/health/sidekiq`. 503 → Sidekiq isn't processing. Jump to §3.
- Open Coolify logs of the Rails container, filter `[WAHA events]`.
  Look for `reason=` lines or stack traces.
- In WAHA dashboard, confirm the session is `WORKING`. If status is
  `FAILED` or `STOPPED`, the inbox needs a re-scan QR.

**Fix.**

- WAHA session in FAILED: regenerate QR via inbox settings, the user
  rescans, messages resume. Past messages are lost — WAHA doesn't
  buffer beyond 24h.
- Sidekiq queue stuck: see §3.
- Same `source_id` getting dropped silently: check
  `redis-cli get whatsapp:message_source:<id>`. If the key is present
  but no Message row exists, run `Whatsapp::MessageDedupLock.new(id).release!`
  to free the slot and let the retry land.

---

## 2. Athenas autopilot stopped replying

**Symptom.** Conversations show inbound messages but no autopilot
reply.

**Triage.**

- Check Sidekiq → filter `Ai::AutopilotReplyJob`. Look for `failed`
  jobs or backed-up retries.
- Check Sentry for `Ai::ClaudeService::Error` or
  `Ai::CreditLedger::QuotaExhaustedError`.
- Open the conversation in the dashboard and check the saldo meter
  (bottom-right). Zero balance → operator hit the paywall.
- Hit `/api/v1/accounts/<id>/ai/credits` (admin auth) → check
  `daily_usd_spent` vs `daily_usd_cap`. If spent ≥ cap, daily limit
  hit.

**Fix.**

- Balance exhausted: nudge customer to recarregar; or run the
  manual credit snippet (see `docs/MAGIC_LINK_GENERATOR.md`).
- Daily cap exceeded: raise via
  `Account.find(<id>).update!(custom_attributes:
  account.custom_attributes.merge('athenas_daily_usd_cap' => '20.0'))`
  for that specific tenant, or bump `ATHENAS_DAILY_USD_CAP` env in
  Coolify.
- WAHA session down (no incoming events): see §1.

---

## 3. Sidekiq queue stuck or workers dead

**Symptom.** `/health/sidekiq` returns 503. Jobs aren't draining.

**Triage.**

- `coolify` exec into the Sidekiq container, then
  `bundle exec sidekiqmon`. Check process count + queue latency.
- Tail the logs: `coolify logs -f univerzap-sidekiq`. Watch for
  `RAM`, `OOM`, `KILL` markers — common after a Coolify deploy that
  didn't drain.

**Fix.**

- Hard restart Sidekiq via Coolify. Pair with
  `stop_grace_period: 70s` on the service spec so the next deploy
  doesn't reproduce the issue.
- If a single bad job is blocking the queue, find it in
  `Sidekiq::DeadSet` and delete: `Sidekiq::DeadSet.new.each { |j| j.delete if j.klass == 'Webhooks::WahaEventsJob' && j.error_class == 'X' }`.

---

## 4. Database hot path latency / connection saturation

**Symptom.** Dashboard pages take seconds to load. Status page shows
database `latency_ms > 200`.

**Triage.**

- Coolify Postgres metrics: connection count, slow query log, disk
  IO.
- `psql ... -c "SELECT pid, state, query FROM pg_stat_activity
   WHERE state != 'idle';"` to surface hot queries.
- Check for missing index on a new join — recent migrations are the
  usual culprit.

**Fix.**

- Kill the offending query: `SELECT pg_terminate_backend(<pid>)`.
- If it's a recurring background job, find the job and rate-limit /
  refactor it before re-enabling.
- For app-level connection exhaustion, restart the Rails web
  container; deeper fix is bumping `DATABASE_POOL` ENV.

---

## 5. Univercart billing webhook not crediting tokens

**Symptom.** Customer paid but saldo Athenas didn't change.

**Triage.**

- Coolify logs of Rails web container, filter
  `[univercart.webhook]`.
- Check `UnivercartProcessedEvent.last(20)` in Rails console — is
  the event id present?
- Check signature: missing or invalid → 400 / 401 logged.

**Fix.**

- If signature failed, double-check `UNIVERCART_WEBHOOK_SECRET` in
  Coolify env. The webhook receiver expects `X-Univercart-Signature`
  in `sha256=<hmac>` form.
- If event arrived but no credit applied,
  `Ai::CreditLedger.new(account).credit_purchase!(cents_brl: <X>,
  external_payment_id: <transactionId>, description: 'Manual fix')`
  resolves it. Then file a follow-up to make the handler more
  defensive.

---

## 6. Sentry suddenly silent

**Symptom.** Spike in customer complaints but Sentry shows nothing.

**Triage.**

- `SENTRY_DSN` env still set on every container? Validate via Rails
  console: `ENV['SENTRY_DSN'].present?`.
- Sentry quota: open the Sentry project and check ingestion rate.
- Coolify recently restarted? The initializer is gated on the DSN
  being present at boot.

**Fix.**

- Re-set the env if it disappeared (Coolify Secret).
- Manually test: in Rails console,
  `Sentry.capture_message('manual smoke test')`. Wait 30s and look
  for it in Sentry.

---

## 7. Deploys keep losing messages

**Symptom.** Every Coolify deploy correlates with a burst of "I sent
a message and it didn't arrive" reports.

**Triage.**

- Check Coolify service config: `stop_grace_period` should be 70s
  or higher. Anything lower means Sidekiq gets SIGKILL'd mid-job.
- Check Sidekiq's own `:timeout:` in `config/sidekiq.yml` (currently
  60s).

**Fix.**

- Bump `stop_grace_period` to 90s if you observe in-flight job
  failures around deploy time.
- Avoid deploys during business hours for now — until we add
  rolling deploys or a multi-instance setup.

---

## 8. Magic-link signup fails

**Symptom.** Customer clicks the Univercart link, sees "Link inválido
ou expirado" or "Sessão expirada".

**Triage.**

- Check the JWT exp claim — the link is single-use and only valid
  for 30 minutes.
- Confirm the redeem flag in Redis: the second click consumes the
  jti and refuses subsequent attempts.

**Fix.**

- Re-issue a new link from the manual snippet
  (`docs/MAGIC_LINK_GENERATOR.md`).
- If the buyer never receives the link, check `UnivercartSubscription`
  for the buyer — webhook should have created it on `entitlement.granted`.

---

## Escalation

| What | Who | Channel |
|---|---|---|
| Sustained > 5min outage | Kennedy (CTO) | WhatsApp direct |
| Athenas / Claude API down | Kennedy | Slack + Anthropic status page |
| LGPD data event | Kennedy | Email + advogado contato |
| Univercart billing event | Kennedy + Univercart support | Both |

When in doubt, page Kennedy first and let him route from there.
