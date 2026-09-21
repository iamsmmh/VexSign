import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac, hkdfSync, randomBytes } from 'node:crypto';
import { deliverWebhooks } from '../src/webhooks.js';
import type { Infrastructure } from '../src/infrastructure.js';

// A mock pool that returns a configurable webhook-delivery worklist and records
// every query, mirroring the mock style in jobs.test.ts.
function pool(rows: { job_id: string; url: string; payload: unknown }[]) {
  const calls: { sql: string; params?: unknown[] }[] = [];
  return {
    calls,
    infra: {
      pool: {
        query: async (sql: string, params?: unknown[]) => {
          calls.push({ sql, params });
          if (sql.includes('webhook_deliveries SET attempts')) return { rows };
          return { rows: [], rowCount: 1 };
        },
        connect: async () => { throw new Error('not used'); },
      },
    } as unknown as Pick<Infrastructure, 'pool'>,
  };
}

const key = randomBytes(32);
const allowlist = 'https://hooks.example.test/signing';
const config = { WEBHOOK_ALLOWLIST: allowlist } as const;
const FIXED_NOW = 1_790_000_000_000;

test('delivery claim caps attempts at 8 with a 5 minute lease', async () => {
  const db = pool([]);
  await deliverWebhooks(db.infra, config, key, { fetchImpl: async () => new Response() });
  const claim = db.calls[0]!.sql;
  assert.match(claim, /attempts<8/);
  assert.match(claim, /interval '5 minutes'/);
  assert.match(claim, /FOR UPDATE SKIP LOCKED/);
});

test('non-allowlisted URLs are skipped without any network call (SSRF gate)', async () => {
  const db = pool([{ job_id: 'j1', url: 'https://attacker.example/steal', payload: {} }]);
  let fetched = 0;
  await deliverWebhooks(db.infra, config, key, { fetchImpl: async () => { fetched++; return new Response(); } });
  assert.equal(fetched, 0);
  assert.ok(!db.calls.some(c => c.sql.includes('delivered_at=now()')));
});

test('non-HTTPS, credentialed and fragment URLs are structurally undeliverable', async () => {
  // These fail permittedWebhook no matter what the operator allowlist says.
  const structurallyBlocked = [
    'http://127.0.0.1/', 'http://localhost/', 'http://[::1]/', 'http://0.0.0.0/',
    'http://169.254.169.254/latest/meta-data/',
    'file:///etc/passwd', 'ftp://hooks.example.test/', 'data:text/plain,hi',
    'https://user:pass@hooks.example.test/signing', 'https://hooks.example.test/signing#x',
  ];
  for (const url of structurallyBlocked) {
    const db = pool([{ job_id: 'j1', url, payload: {} }]);
    let fetched = 0;
    await deliverWebhooks(db.infra, { WEBHOOK_ALLOWLIST: url }, key, { fetchImpl: async () => { fetched++; return new Response(); } });
    assert.equal(fetched, 0, `${url} must never be fetched`);
  }
});

test('internal-address URLs that never match the operator allowlist are not fetched', async () => {
  // HTTPS to private/loopback/link-local hosts is stopped by the exact-match
  // allowlist (plus the deployment egress firewall): a delivery row carrying any
  // of these cannot exist for a normally-registered endpoint.
  const internal = [
    'https://127.0.0.1/x', 'https://localhost/x', 'https://[::1]/x',
    'https://10.0.0.1/x', 'https://192.168.1.1/x', 'https://172.16.0.1/x',
    'https://169.254.169.254/latest/meta-data/',
  ];
  for (const url of internal) {
    const db = pool([{ job_id: 'j1', url, payload: {} }]);
    let fetched = 0;
    await deliverWebhooks(db.infra, config, key, { fetchImpl: async () => { fetched++; return new Response(); } });
    assert.equal(fetched, 0, `${url} must never be fetched`);
  }
});

test('successful delivery marks delivered_at and signs the payload per URL', async () => {
  const payload = { jobId: 'j1', state: 'completed' };
  const db = pool([{ job_id: 'j1', url: allowlist, payload }]);
  const seen: { url: string; init: RequestInit }[] = [];
  await deliverWebhooks(db.infra, config, key, {
    now: () => FIXED_NOW,
    fetchImpl: async (url, init) => { seen.push({ url: String(url), init: init! }); return new Response(null, { status: 200 }); },
  });

  assert.equal(seen.length, 1);
  const { url, init } = seen[0]!;
  assert.equal(url, allowlist);
  assert.equal(init.method, 'POST');
  assert.equal(init.redirect, 'error', 'redirects must be refused (redirect-SSRF protection)');
  assert.equal(init.body, JSON.stringify(payload));

  const headers = init.headers as Record<string, string>;
  const timestamp = String(Math.floor(FIXED_NOW / 1000));
  assert.equal(headers['x-vexsign-timestamp'], timestamp);
  assert.equal(headers['x-vexsign-event-id'], 'j1');
  const webhookKey = Buffer.from(hkdfSync('sha256', key, '', `vexsign.webhook.v1:${allowlist}`, 32));
  const expected = createHmac('sha256', webhookKey).update(`${timestamp}.${JSON.stringify(payload)}`).digest('hex');
  assert.equal(headers['x-vexsign-signature'], expected, 'signature must be verifiable by the receiver');

  const mark = db.calls.find(c => c.sql.includes('delivered_at=now()'));
  assert.ok(mark, 'ok responses must mark the delivery complete');
  assert.deepEqual(mark!.params, ['j1']);
});

test('non-ok responses and fetch errors leave the lease for retry', async () => {
  const row = { job_id: 'j1', url: allowlist, payload: {} };

  const failing = pool([row]);
  await deliverWebhooks(failing.infra, config, key, { fetchImpl: async () => new Response(null, { status: 500 }) });
  assert.ok(!failing.calls.some(c => c.sql.includes('delivered_at=now()')), '5xx must not mark delivered');

  const throwing = pool([row]);
  // Simulates what fetch does with redirect: 'error' when the endpoint redirects:
  // it rejects, and the delivery must simply stay leased for a later attempt.
  await deliverWebhooks(throwing.infra, config, key, { fetchImpl: async () => { throw new TypeError('redirect not allowed'); } });
  assert.ok(!throwing.calls.some(c => c.sql.includes('delivered_at=now()')), 'redirect refusal must not mark delivered');
});
