// Supabase accepts two kinds of server key. A legacy service_role key is a
// JWT and goes in both headers; a new secret key (sb_secret_…) goes ONLY in
// `apikey` — sent as a Bearer token it is rejected as an invalid JWT.
export function supabaseAuthHeaders(key: string): Record<string, string> {
  const k = key.trim();
  const isJwt = k.split('.').length === 3 && k.startsWith('eyJ');
  return isJwt ? { apikey: k, Authorization: `Bearer ${k}` } : { apikey: k };
}
