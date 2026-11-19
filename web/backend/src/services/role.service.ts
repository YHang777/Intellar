import type { Firestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { fbDb } from '../config/firebase';
import { ApiError } from '../lib/errors';

export type AccountRole = 'homeowner' | 'supplier';

export interface RoleChangeResult {
  uid: string;
  role: AccountRole;
  changed: boolean;
}

/**
 * Fixes an account that signed up with the wrong role. Only allowed while the
 * account has no orders (as buyer or seller) and no listings — once there is
 * trading history, switching would strand listings or orders on the wrong
 * side of the app.
 */
export async function changeUserRole(
  uid: string,
  role: AccountRole,
  dbOverride?: Firestore
): Promise<RoleChangeResult> {
  const db = dbOverride ?? fbDb();
  const ref = db.collection('users').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new ApiError(404, 'USER_NOT_FOUND', 'That account has no profile yet.');
  }
  const data = (snap.data() ?? {}) as Record<string, unknown>;
  const current = String(data.role ?? '').toLowerCase();
  if (current === role) return { uid, role, changed: false };

  const [bought, sold, listedA, listedB] = await Promise.all([
    db.collection('orders').where('customerId', '==', uid).limit(1).get(),
    db.collection('orders').where('supplierIds', 'array-contains', uid).limit(1).get(),
    db.collection('products').where('supplierId', '==', uid).limit(1).get(),
    db.collection('products').where('supplier.id', '==', uid).limit(1).get(),
  ]);
  if (!bought.empty || !sold.empty) {
    throw new ApiError(
      409,
      'ROLE_LOCKED',
      'This account already has orders, so its role can no longer be changed.'
    );
  }
  if (!listedA.empty || !listedB.empty) {
    throw new ApiError(
      409,
      'ROLE_LOCKED',
      'This account has product listings. Remove them before changing its role.'
    );
  }

  const name = String(data.name ?? '');
  const phone = String(data.phone ?? '');
  const address = String(data.address ?? '');
  const update: Record<string, unknown> = {
    role,
    // A new seller starts unverified and applies with their IC as usual.
    verificationStatus: 'none',
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (role === 'supplier') {
    update.businessName = String(data.businessName ?? '') || name;
    update.businessPhone = String(data.businessPhone ?? '') || phone;
    update.businessAddress = String(data.businessAddress ?? '') || address;
  } else {
    update.businessName = '';
    update.businessPhone = '';
    update.businessAddress = '';
  }
  await ref.update(update);
  return { uid, role, changed: true };
}
