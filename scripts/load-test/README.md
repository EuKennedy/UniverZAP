# Load testing

Artillery script that simulates worst-case operator load against the
dashboard + Athenas endpoints. Use BEFORE marketing-fueled traffic
spikes (Black Friday, evening promos, paid ad bursts).

## Quick start

```bash
npm install -g artillery

ARTILLERY_TARGET="https://app.univerzap.cloud" \
ARTILLERY_TOKEN="<api_access_token>" \
ARTILLERY_ACCOUNT_ID="<account_id>" \
artillery run scripts/load-test/conversations.yml
```

## Reading the report

Artillery prints a percentile breakdown at the end. The two numbers
that matter for a sales-MVP grade UniverZAP install:

| Metric | Target | What it means |
|---|---|---|
| `p95 response time` | < 800ms | 95% of requests finish under 800ms |
| `errors` | 0 | Any 5xx during the spike phase is a fail |

If `p95 > 800ms` during the peak phase, the bottleneck is almost
always Postgres connection saturation OR an N+1 in the conversation
serializer. Check `/health?detail=1` mid-run to see which.

## Targeting staging only

NEVER run this against a production tenant. The `ARTILLERY_TOKEN`
hits the real API, creates load, and triggers real Athenas calls
that burn USD. Always point at a staging environment with seeded
data and a per-test daily USD cap set to `0.5`.

## What's missing

- WebSocket / ActionCable load (artillery-engine-socketio plugin).
- WAHA webhook fan-out simulation — needs a separate script that
  POSTs signed payloads to `/webhooks/waha`.
- File upload paths.

These get added once the steady-state HTTP profile passes
consistently.
