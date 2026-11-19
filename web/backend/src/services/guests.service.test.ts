import test from 'node:test';
import assert from 'node:assert/strict';
import type { UserRecord } from 'firebase-admin/auth';
import { idleGuestUids, isGuestAccount } from './guests.service';

const NOW = Date.parse('2026-11-20T12:00:00Z');
const hoursAgo = (h: number) => new Date(NOW - h * 3600 * 1000).toUTCString();

function rec(uid: string, opts: { email?: string; providers?: number; refreshedHoursAgo?: number }): UserRecord {
  return {
    uid,
    email: opts.email,
    providerData: Array.from({ length: opts.providers ?? 0 }, () => ({ providerId: 'password' })),
    metadata: {
      creationTime: hoursAgo(500),
      lastSignInTime: hoursAgo(500),
      lastRefreshTime: opts.refreshedHoursAgo === undefined ? null : hoursAgo(opts.refreshedHoursAgo),
    },
  } as unknown as UserRecord;
}

test('a guest is an account with no email and no sign-in provider', () => {
  assert.equal(isGuestAccount(rec('g', {})), true);
  assert.equal(isGuestAccount(rec('u', { email: 'a@b.co', providers: 1 })), false);
  assert.equal(isGuestAccount(rec('p', { providers: 1 })), false);
  assert.equal(isGuestAccount(undefined), false);
});

test('only guests idle at least the limit are picked; real users never', () => {
  const uids = idleGuestUids(
    [
      rec('active-guest', { refreshedHoursAgo: 0.2 }),
      rec('idle-guest', { refreshedHoursAgo: 3 }),
      rec('never-refreshed-guest', {}),
      rec('real-user', { email: 'a@b.co', providers: 1, refreshedHoursAgo: 900 }),
      rec('admin-guest', { refreshedHoursAgo: 900 }),
    ],
    3600 * 1000,
    NOW,
    ['admin-guest']
  );
  assert.deepEqual(uids.sort(), ['idle-guest', 'never-refreshed-guest']);
});
