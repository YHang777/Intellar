import { fbDb, FieldValue } from '../config/firebase';

/**
 * Append-only record of critical actions (NFR7) in `audit_logs`. Clients
 * cannot read or write the collection (rules deny it); entries come from the
 * server and the admin console reads them through the admin API.
 */
export interface AuditEntry {
  actorId: string;
  action: string;
  targetType?: string;
  targetId?: string;
  details?: Record<string, unknown>;
}

export async function writeAudit(
  entry: AuditEntry,
  db: ReturnType<typeof fbDb> = fbDb()
): Promise<void> {
  await db.collection('audit_logs').add({
    actorId: entry.actorId,
    action: entry.action,
    targetType: entry.targetType ?? '',
    targetId: entry.targetId ?? '',
    details: entry.details ?? {},
    at: FieldValue.serverTimestamp(),
  });
}

export function auditQuietly(
  entry: AuditEntry,
  db?: ReturnType<typeof fbDb>,
  log: (m: string) => void = (m) => console.log(m)
): void {
  void (async () => {
    try {
      await writeAudit(entry, db ?? fbDb());
    } catch (err) {
      log(`[audit] ${entry.action} not recorded: ${(err as Error).message}`);
    }
  })();
}

/** Actions the mobile app may report for changes it makes directly. */
export const CLIENT_AUDIT_ACTIONS = new Set([
  'profile.update',
  'preferences.update',
  'settings.update',
  'product.create',
  'product.update',
  'product.delete',
  'design.delete',
]);
