import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac, randomBytes } from 'node:crypto';
import { permittedWebhook, capability, verifyCapability } from '../src/security.js';
import { signRequest, checkRequest, batchRequest } from '../src/contracts.js';
import { submitJobs, APIError, type Submission } from '../src/jobs.js';
import type { Infrastructure } from '../src/infrastructure.js';

// MARK: SSRF / private-network vectors
//
// Webhook endpoints are operator-registered EXACT matches validated twice:
// at submission (app.ts) and again at delivery (webhooks.ts). These tests pin
// that nothing loopback/private/link-local/non-HTTPS can pass either gate.

test('webhook gate structurally rejects non-HTTPS, credentialed, fragment and malformed URLs', () => {
  // The allowlist is the URL itself: admission here would mean the gate itself
  // failed, regardless of what an operator registered.
  const targets = [
    'http://127.0.0.1/hook', 'http://localhost/hook', 'http://[::1]/hook',
    'http://0.0.0.0/hook', 'http://10.0.0.1/hook', 'http://192.168.0.10/hook',
    'http://172.16.5.5/hook',
    'http://169.254.169.254/latest/meta-data/', // cloud metadata service
    'http://169.254.169.254.nip.io/',
    'file:///etc/passwd', 'ftp://internal/hook', 'data:text/plain,hi',
    'javascript:alert(1)',
    'https://user:pass@hooks.example.test/hook',
    'https://hooks.example.test/hook#fragment',
    'not a url',
  ];
  for (const url of targets) {
    assert.equal(permittedWebhook(url, url), false, `${url} must be rejected`);
  }
  // Absent webhook is a valid request shape (webhooks are optional).
  assert.equal(permittedWebhook(undefined, 'https://x.example/'), true);
  assert.equal(permittedWebhook('', 'https://x.example/'), true);
});

test('private and link-local HTTPS hosts cannot reach a normally registered endpoint', () => {
  const allowlist = 'https://hooks.example.test/signing';
  const internal = [
    'https://127.0.0.1/hook', 'https://localhost/hook', 'https://localhost:8443/hook',
    'https://[::1]/hook', 'https://0.0.0.0/hook',
    'https://10.0.0.1/hook', 'https://192.168.0.10/hook', 'https://172.16.5.5/hook',
    'https://169.254.169.254/latest/meta-data/',
    'https://hooks.example.test.evil/signing', // lookalike
  ];
  for (const url of internal) {
    assert.equal(permittedWebhook(url, allowlist), false, `${url} must not match the allowlist`);
  }
});

test('webhook gate demands exact registration — no near-matches', () => {
  const allowlist = 'https://hooks.example.test/signing';
  const nearMisses = [
    'http://hooks.example.test/signing',                     // scheme downgrade
    'https://hooks.example.test/signing/',                   // trailing slash
    'https://hooks.example.test/Signing',                    // path case
    'https://hooks.example.test:8443/signing',               // different port
    'https://hooks.example.test/signing?x=1',                // query string
    'https://hooks.example.test.evil/signing',               // suffix lookalike
    'https://sub.hooks.example.test/signing',                // subdomain
  ];
  for (const url of nearMisses) {
    assert.equal(permittedWebhook(url, allowlist), false, `${url} must not match the allowlist`);
  }
  assert.equal(permittedWebhook(allowlist, `${allowlist}, https://other.example/x`), true);
});

// MARK: capability expiry

test('OTA capabilities expire and cannot be minted beyond the 7 day window', () => {
  const now = 1_790_000_000_000; const key = randomBytes(32);

  const oneMinute = capability('a', Math.floor(now / 1000) + 60, key);
  assert.ok(verifyCapability('a', oneMinute, key, now));
  assert.equal(verifyCapability('a', oneMinute, key, now + 60_001), false, 'expired token must fail');

  const sixDays = capability('a', Math.floor(now / 1000) + 6 * 86400, key);
  assert.ok(verifyCapability('a', sixDays, key, now), 'six days is inside the window');

  const eightDays = capability('a', Math.floor(now / 1000) + 8 * 86400, key);
  assert.equal(verifyCapability('a', eightDays, key, now), false, 'tokens beyond 7 days must be refused');
});

// MARK: malformed contracts

test('contracts reject malformed and oversized submissions', () => {
  const valid = { ipaId: '6f9b9b7c-1c2e-4f5a-9f0b-0c1d2e3f4a5b', p12Id: '6f9b9b7c-1c2e-4f5a-9f0b-0c1d2e3f4a5c', provisionId: '6f9b9b7c-1c2e-4f5a-9f0b-0c1d2e3f4a5d', password: 'x' };
  assert.ok(signRequest.safeParse(valid).success, 'valid uuid-keyed request passes');

  assert.equal(signRequest.safeParse({ ...valid, password: 'x'.repeat(1025) }).success, false, 'password over 1024');
  assert.equal(signRequest.safeParse({ ...valid, webhook: 'x'.repeat(2049) }).success, false, 'webhook over 2048');
  assert.equal(signRequest.safeParse({ ...valid, extra: true }).success, false, 'strict object rejects extra fields');
  assert.equal(signRequest.safeParse({ ...valid, ipaId: 'not-a-uuid' }).success, false);
  assert.equal(checkRequest.safeParse(valid).success, false, 'check-cert request must omit ipaId');
  assert.ok(checkRequest.safeParse({ p12Id: valid.p12Id, provisionId: valid.provisionId, password: 'x' }).success);

  const job = { ...valid, idempotencyKey: '6f9b9b7c-1c2e-4f5a-9f0b-0c1d2e3f4a5e' };
  assert.equal(batchRequest.safeParse({ jobs: Array.from({ length: 21 }, () => job) }).success, false, 'batches above 20 rejected');
  assert.ok(batchRequest.safeParse({ jobs: Array.from({ length: 20 }, () => job) }).success);
  assert.equal(batchRequest.safeParse({ jobs: [{ ...job, idempotencyKey: 'nope' }] }).success, false, 'idempotencyKey must be a uuid');
});

// MARK: idempotency + owner isolation (mock DB, same style as jobs.test.ts)

const baseRequest: Submission = {
  ipaId: 'ipa-a', p12Id: 'p12-a', provisionId: 'provision-a',
  password: 'sensitive-test-value', idempotencyKey: 'idempotency-a',
};

function requestHash(key: Buffer, kind: string, request: Submission): string {
  return createHmac('sha256', key).update(JSON.stringify([
    kind, request.ipaId ?? null, request.p12Id, request.provisionId, request.password, request.webhook ?? null,
  ])).digest('hex');
}

function database(options: { assetRows?: { id: string; kind: string }[]; prior?: Record<string, unknown> } = {}) {
  const calls: { sql: string; params: unknown[] }[] = [];
  const client = {
    async query(sql: string, params: unknown[] = []) {
      calls.push({ sql, params });
      if (sql.includes('count(*)')) return { rows: [{ count: 0 }] };
      if (sql.includes('idempotency_key=$2')) return { rows: options.prior ? [options.prior] : [], rowCount: options.prior ? 1 : 0 };
      if (sql.includes('SELECT id, kind FROM assets')) return { rows: options.assetRows ?? [{ id: 'ipa-a', kind: 'ipa' }, { id: 'p12-a', kind: 'p12' }, { id: 'provision-a', kind: 'provision' }] };
      return { rows: [], rowCount: 1 };
    },
    release() {},
  };
  return { calls, infra: { pool: { connect: async () => client } } as unknown as Infrastructure };
}

test('idempotent resubmission returns the original job without inserting', async () => {
  const key = randomBytes(32);
  const hash = requestHash(key, 'sign', baseRequest);
  const db = database({ prior: { id: 'existing-job', state: 'running', request_hash: hash } });

  const [result] = await submitJobs(db.infra, key, 'tenant-a', 'sign', [baseRequest]);
  assert.equal(result?.id, 'existing-job');
  assert.equal(result?.state, 'running');
  assert.ok(!db.calls.some(c => c.sql.startsWith('INSERT INTO jobs')), 'no duplicate job row');
  assert.equal(db.calls.at(-1)?.sql, 'COMMIT');
});

test('asset lookups are owner-scoped; foreign rows never satisfy a request', async () => {
  const key = randomBytes(32);
  // The DB returns rows with matching kinds but different ids (e.g. another
  // tenant's assets) — matches() must fail them.
  const db = database({ assetRows: [{ id: 'someone-elses-ipa', kind: 'ipa' }, { id: 'p12-a', kind: 'p12' }, { id: 'provision-a', kind: 'provision' }] });

  await assert.rejects(
    submitJobs(db.infra, key, 'tenant-a', 'sign', [baseRequest]),
    (error: unknown) => error instanceof APIError && error.statusCode === 404,
  );
  const assetQuery = db.calls.find(c => c.sql.includes('SELECT id, kind FROM assets'));
  assert.ok(assetQuery, 'submission must verify asset ownership');
  assert.equal(assetQuery!.params[0], 'tenant-a', 'asset lookup must be scoped to the requesting owner');
  assert.equal(db.calls.at(-1)?.sql, 'ROLLBACK');
});
