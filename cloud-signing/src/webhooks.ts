import { createHmac, hkdfSync } from 'node:crypto';
import type { Infrastructure } from './infrastructure.js';
import type { Config } from './config.js';
import { permittedWebhook } from './security.js';

export interface WebhookDeliveryDeps {
  /** Injectable for tests; production uses the global fetch. */
  fetchImpl?: typeof fetch;
  /** Injectable clock for deterministic timestamps in tests. */
  now?: () => number;
}

/**
 * Delivers pending webhook notifications with a transactional claim + lease so
 * multiple worker replicas never double-send. Behavior (attempts cap, backoff,
 * re-validation, signature scheme) is pinned by test/webhooks.test.ts.
 */
export async function deliverWebhooks(
  infra: Pick<Infrastructure, 'pool'>,
  config: Pick<Config, 'WEBHOOK_ALLOWLIST'>,
  key: Buffer,
  deps: WebhookDeliveryDeps = {},
): Promise<void> {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const now = deps.now ?? Date.now;
  // Transactional claim with a lease supports multiple worker replicas.
  const records = await infra.pool.query(`UPDATE webhook_deliveries SET attempts=attempts+1,next_attempt_at=now()+interval '5 minutes'
    WHERE job_id IN (SELECT job_id FROM webhook_deliveries WHERE delivered_at IS NULL AND attempts<8 AND next_attempt_at<=now()
      ORDER BY next_attempt_at FOR UPDATE SKIP LOCKED LIMIT 10) RETURNING *`);
  for (const row of records.rows as { job_id: string; url: string; payload: unknown }[]) {
    // Re-validated at delivery time: a delivery row can only exist for an
    // operator-registered EXACT-match HTTPS endpoint, and anything else
    // (private/link-local/localhost, http, credentials, non-matching strings)
    // is skipped without a network call.
    if (!permittedWebhook(row.url, config.WEBHOOK_ALLOWLIST)) continue;
    const timestamp = String(Math.floor(now() / 1000)); const payload = JSON.stringify(row.payload);
    const webhookKey = Buffer.from(hkdfSync('sha256', key, '', `vexsign.webhook.v1:${row.url}`, 32));
    const signature = createHmac('sha256', webhookKey).update(`${timestamp}.${payload}`).digest('hex');
    try {
      // `redirect: 'error'` blocks redirect-based SSRF: a registered endpoint
      // that starts redirecting fails the delivery instead of following the
      // hop to an internal address. Deployment egress firewall must still
      // block private/link-local addresses and DNS rebinding.
      const response = await fetchImpl(row.url, { method: 'POST', body: payload, redirect: 'error', signal: AbortSignal.timeout(10_000),
        headers: { 'content-type': 'application/json', 'x-vexsign-timestamp': timestamp, 'x-vexsign-signature': signature, 'x-vexsign-event-id': row.job_id } });
      await response.body?.cancel();
      if (response.ok) await infra.pool.query('UPDATE webhook_deliveries SET delivered_at=now() WHERE job_id=$1', [row.job_id]);
    } catch { /* Persisted lease enables retry without logging secret endpoint URLs. */ }
  }
}
