import test from 'node:test';
import assert from 'node:assert/strict';
import { supabaseAuthHeaders } from './supabase-headers';

test('a legacy JWT service key goes in both headers', () => {
  const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig';
  assert.deepEqual(supabaseAuthHeaders(jwt), { apikey: jwt, Authorization: `Bearer ${jwt}` });
});

test('a new secret key goes only in apikey', () => {
  assert.deepEqual(supabaseAuthHeaders(' sb_secret_abc123 '), { apikey: 'sb_secret_abc123' });
});

test('only the origin of SUPABASE_URL is used', async () => {
  const { supabaseOrigin } = await import('./supabase-headers');
  assert.equal(supabaseOrigin('https://abc.supabase.co/rest/v1/'), 'https://abc.supabase.co');
  assert.equal(supabaseOrigin(' https://abc.supabase.co '), 'https://abc.supabase.co');
  assert.equal(supabaseOrigin(''), '');
});
