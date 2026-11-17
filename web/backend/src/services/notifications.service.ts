import { fbDb, fbMessaging, FieldValue } from '../config/firebase';

/**
 * One notification = an inbox row under `users/{uid}/notifications` plus an
 * FCM push to every device token under `users/{uid}/fcmTokens/{token}`.
 *
 * The user's `notificationSettings` decide delivery:
 *   - transactional kinds (orders, quotes) always land in the inbox; the
 *     push is skipped when `orderUpdates` is off;
 *   - promotions / recommendations are dropped entirely when switched off.
 */

export type NotificationKind =
  | 'order_update'
  | 'new_order'
  | 'quote'
  | 'promotion'
  | 'recommendation';

export interface NotificationInput {
  kind: NotificationKind;
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushMessage {
  tokens: string[];
  title: string;
  body: string;
  data: Record<string, string>;
}

export interface PushResult {
  invalidTokens: string[];
}

export interface NotificationDeps {
  db: () => ReturnType<typeof fbDb>;
  push: (msg: PushMessage) => Promise<PushResult>;
  log?: (message: string) => void;
}

export function defaultNotificationDeps(): NotificationDeps {
  return {
    db: fbDb,
    push: async ({ tokens, title, body, data }) => {
      if (tokens.length === 0) return { invalidTokens: [] };
      const res = await fbMessaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data,
        android: {
          priority: 'high',
          notification: { channelId: 'intellar_default' },
        },
      });
      const invalidTokens: string[] = [];
      res.responses.forEach((r, i) => {
        const code = r.error?.code ?? '';
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token' ||
          code === 'messaging/invalid-argument'
        ) {
          invalidTokens.push(tokens[i]);
        }
      });
      return { invalidTokens };
    },
    log: (message) => console.log(message),
  };
}

const SETTING_FOR: Record<NotificationKind, string> = {
  order_update: 'orderUpdates',
  new_order: 'orderUpdates',
  quote: 'orderUpdates',
  promotion: 'promotions',
  recommendation: 'recommendations',
};

const TRANSACTIONAL = new Set<NotificationKind>(['order_update', 'new_order', 'quote']);

export interface NotifyOutcome {
  stored: boolean;
  pushed: number;
}

export async function notifyUser(
  deps: NotificationDeps,
  uid: string,
  input: NotificationInput
): Promise<NotifyOutcome> {
  const db = deps.db();
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) return { stored: false, pushed: 0 };
  const settings = (userSnap.data()?.notificationSettings ?? {}) as Record<string, unknown>;
  const enabled = settings[SETTING_FOR[input.kind]] !== false;
  if (!enabled && !TRANSACTIONAL.has(input.kind)) return { stored: false, pushed: 0 };

  const ref = userRef.collection('notifications').doc();
  await ref.set({
    kind: input.kind,
    title: input.title,
    body: input.body,
    data: input.data ?? {},
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  if (!enabled) return { stored: true, pushed: 0 };

  const tokenSnap = await userRef.collection('fcmTokens').get();
  const tokens = tokenSnap.docs.map((d) => d.id).filter((t) => t.length > 0);
  if (tokens.length === 0) return { stored: true, pushed: 0 };
  try {
    const { invalidTokens } = await deps.push({
      tokens,
      title: input.title,
      body: input.body,
      data: { ...(input.data ?? {}), kind: input.kind, notificationId: ref.id },
    });
    await Promise.all(
      invalidTokens.map((t) => userRef.collection('fcmTokens').doc(t).delete())
    );
    return { stored: true, pushed: tokens.length - invalidTokens.length };
  } catch (err) {
    deps.log?.(`[notify] push failed for ${uid}: ${(err as Error).message}`);
    return { stored: true, pushed: 0 };
  }
}

/** Fire-and-forget wrapper for hooks inside other flows (never throws). */
export function notifyQuietly(
  deps: NotificationDeps,
  uid: string,
  input: NotificationInput
): void {
  void notifyUser(deps, uid, input).catch((err) =>
    deps.log?.(`[notify] ${input.kind} for ${uid} failed: ${(err as Error).message}`)
  );
}

export function orderStatusMessage(
  status: string,
  orderNumber: string
): { title: string; body: string } | null {
  switch (status) {
    case 'confirmed':
      return {
        title: 'Order confirmed',
        body: `The seller confirmed order ${orderNumber} and is preparing it.`,
      };
    case 'waitingCollection':
      return {
        title: 'Ready for collection',
        body: `Order ${orderNumber} is ready — collect it from the seller's store.`,
      };
    case 'collected':
      return {
        title: 'Order collected',
        body: `Order ${orderNumber} is complete. Thanks for shopping with Intellar!`,
      };
    default:
      return null;
  }
}
