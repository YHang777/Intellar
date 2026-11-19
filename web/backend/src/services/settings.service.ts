import type { RequestHandler } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import { fbDb } from '../config/firebase';
import { authenticate } from '../middleware/authenticate';
import type { AppSettings } from '../types/models';

export interface SettingsDeps {
  get: () => Promise<AppSettings>;
  update: (patch: SettingsPatch, adminUid: string) => Promise<AppSettings>;
  authorize: RequestHandler;
  log?: (message: string) => void;
}

export function defaultSettingsDeps(): SettingsDeps {
  return {
    get: () => getSettings(),
    update: (patch, adminUid) => updateSettings(patch, adminUid),
    authorize: authenticate,
    log: (message) => console.log(message),
  };
}

/** Matches the Flutter app's `AppConfigData` default when no doc exists yet. */
export const DEFAULT_TAX_RATE = 0.06;
export const DEFAULT_COMMISSION_RATE = 0.03;
export const MAX_COMMISSION_RATE = 0.3;

export interface SettingsPatch {
  taxRate?: number;
  commissionRate?: number;
}

function asCommission(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return DEFAULT_COMMISSION_RATE;
  if (value < 0 || value > MAX_COMMISSION_RATE) return DEFAULT_COMMISSION_RATE;
  return value;
}

const SETTINGS_DOC = ['appConfig', 'marketplace'] as const;

function asFraction(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return DEFAULT_TAX_RATE;
  if (value < 0 || value > 1) return DEFAULT_TAX_RATE;
  return value;
}

function toIso(value: unknown): string | null {
  if (value && typeof value === 'string' && value) return value;
  if (value && typeof (value as { toDate?: () => Date }).toDate === 'function') {
    return (value as { toDate: () => Date }).toDate().toISOString();
  }
  if (value instanceof Date) return value.toISOString();
  return null;
}

function asNullableString(value: unknown): string | null {
  return typeof value === 'string' && value ? value : null;
}

export function toSettings(raw: Record<string, unknown> | undefined): AppSettings {
  const data = raw ?? {};
  return {
    taxRate: asFraction(data.taxRate),
    commissionRate: asCommission(data.commissionRate),
    updatedAt: toIso(data.updatedAt),
    updatedBy: asNullableString(data.updatedBy),
  };
}

export async function getSettings(dbOverride?: Firestore): Promise<AppSettings> {
  const db = dbOverride ?? fbDb();
  const snap = await db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]).get();
  if (!snap.exists) {
    return { taxRate: DEFAULT_TAX_RATE, commissionRate: DEFAULT_COMMISSION_RATE, updatedAt: null, updatedBy: null };
  }
  return toSettings(snap.data());
}

export async function updateSettings(
  patch: SettingsPatch | number,
  adminUid: string,
  dbOverride?: Firestore
): Promise<AppSettings> {
  const db = dbOverride ?? fbDb();
  const ref = db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]);
  const nowIso = new Date().toISOString();
  const p: SettingsPatch = typeof patch === 'number' ? { taxRate: patch } : patch;
  const fields: Record<string, unknown> = { updatedAt: nowIso, updatedBy: adminUid };
  if (p.taxRate !== undefined) fields.taxRate = p.taxRate;
  if (p.commissionRate !== undefined) fields.commissionRate = p.commissionRate;
  // set + merge, not update: the settings doc may not exist yet.
  await ref.set(fields, { merge: true });
  const snap = await ref.get();
  return toSettings(snap.exists ? snap.data() : fields);
}
