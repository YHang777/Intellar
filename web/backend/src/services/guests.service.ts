import type { UserRecord } from 'firebase-admin/auth';
import { fbAuth } from '../config/firebase';
import { env } from '../config/env';

// "Explore as a guest" signs in anonymously: an Auth account with no
// sign-in provider and no email. Never a real customer or supplier.
export function isGuestAccount(auth: UserRecord | undefined): boolean {
  return Boolean(auth) && !auth!.email && (auth!.providerData?.length ?? 0) === 0;
}

// Last time the guest's app was open: the ID token refreshes hourly while
// it runs, so lastRefreshTime is the best activity signal.
function lastActiveMs(auth: UserRecord): number {
  const m = auth.metadata;
  const times = [m.lastRefreshTime, m.lastSignInTime, m.creationTime]
    .map((t) => (t ? Date.parse(t) : NaN))
    .filter((t) => Number.isFinite(t));
  return times.length ? Math.max(...times) : 0;
}

export function idleGuestUids(
  records: Iterable<UserRecord>,
  idleMs: number,
  now: number,
  adminUids: readonly string[] = env.adminUids
): string[] {
  const out: string[] = [];
  for (const r of records) {
    if (!isGuestAccount(r) || adminUids.includes(r.uid)) continue;
    if (now - lastActiveMs(r) >= idleMs) out.push(r.uid);
  }
  return out;
}

export interface PurgeGuestsResult {
  removed: number;
  remaining: number;
}

export async function purgeIdleGuests(idleMs: number, now = Date.now()): Promise<PurgeGuestsResult> {
  const all: UserRecord[] = [];
  let pageToken: string | undefined;
  do {
    const page = await fbAuth().listUsers(1000, pageToken);
    all.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);

  const uids = idleGuestUids(all, idleMs, now);
  let removed = 0;
  for (let i = 0; i < uids.length; i += 1000) {
    const res = await fbAuth().deleteUsers(uids.slice(i, i + 1000));
    removed += res.successCount;
  }
  const guests = all.filter(isGuestAccount).length;
  return { removed, remaining: guests - removed };
}
