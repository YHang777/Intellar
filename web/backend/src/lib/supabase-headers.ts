// Supabase accepts two kinds of server key. A legacy service_role key is a
// JWT and goes in both headers; a new secret key (sb_secret_…) goes ONLY in
// `apikey` — sent as a Bearer token it is rejected as an invalid JWT.
export function supabaseAuthHeaders(key: string): Record<string, string> {
  const k = key.trim();
  const isJwt = k.split('.').length === 3 && k.startsWith('eyJ');
  return isJwt ? { apikey: k, Authorization: `Bearer ${k}` } : { apikey: k };
}

// For the health check: whether saved designs can reach Supabase, and with
// which kind of key. Reveals no secret.
export function supabaseKeyStyle(): { configured: boolean; keyStyle: string; urlHost: string } {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { env } = require('../config/env') as typeof import('../config/env');
  const key = env.supabaseServiceRoleKey.trim();
  let urlHost = '';
  try {
    urlHost = new URL(env.supabaseUrl).host;
  } catch {
    urlHost = env.supabaseUrl ? 'invalid' : '';
  }
  let keyStyle = 'none';
  if (key.startsWith('sb_secret_')) keyStyle = 'secret';
  else if (key.startsWith('sb_publishable_')) keyStyle = 'publishable (wrong key)';
  else if (key.split('.').length === 3 && key.startsWith('eyJ')) {
    try {
      const role = JSON.parse(Buffer.from(key.split('.')[1], 'base64').toString()).role;
      keyStyle = `jwt:${role}`;
    } catch {
      keyStyle = 'jwt';
    }
  } else if (key) keyStyle = 'unknown';
  return { configured: Boolean(key && urlHost), keyStyle, urlHost };
}
