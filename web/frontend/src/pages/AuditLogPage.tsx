import { useEffect, useState } from 'react';
import { auditApi } from '../api/api';
import { ApiError } from '../api/client';
import type { AuditLogEntry } from '../api/types';
import { IconAlertTriangle, IconRefresh } from '../components/icons';

const ACTIONS = [
  '',
  'order.paid',
  'order.status',
  'order.cancelled',
  'quote.created',
  'quote.contacted',
  '2fa.enabled',
  '2fa.disabled',
  'email.changed',
  'profile.update',
  'preferences.update',
  'settings.update',
  'product.create',
  'product.update',
  'product.delete',
  'design.delete',
];

function describeError(err: unknown): string {
  if (!(err instanceof ApiError)) return 'Could not load the audit log.';
  if (err.code === 'UNAUTHENTICATED') return 'Session expired. Sign in again.';
  if (err.code === 'NOT_ADMIN') return 'Admin access required.';
  if (err.code === 'NETWORK_ERROR') return 'Cannot reach the admin API.';
  if (err.status === 500) {
    return 'The audit index may still be building. Try again in a few minutes.';
  }
  return err.message || `Request failed (${err.status}).`;
}

function formatDateTime(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
}

function formatDetails(details: Record<string, unknown>): string {
  const parts = Object.entries(details).map(([k, v]) => `${k}: ${String(v)}`);
  return parts.length ? parts.join(' · ') : '—';
}

export function AuditLogPage() {
  const [logs, setLogs] = useState<AuditLogEntry[]>([]);
  const [action, setAction] = useState('');
  const [actorId, setActorId] = useState('');
  const [appliedActor, setAppliedActor] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    auditApi
      .list({ action: action || undefined, actorId: appliedActor || undefined })
      .then((res) => {
        if (!cancelled) setLogs(res.logs);
      })
      .catch((err) => {
        if (!cancelled) setError(describeError(err));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [action, appliedActor, reloadKey]);

  return (
    <div className="page">
      <div className="page-intro">
        <div>
          <h2>Audit log</h2>
          <p className="subtitle">
            Critical actions across the marketplace — purchases, cancellations, order updates,
            account security and listing changes. Newest first.
          </p>
        </div>
        <button
          className="btn btn-secondary btn-sm"
          onClick={() => setReloadKey((k) => k + 1)}
          disabled={loading}
        >
          <IconRefresh size={14} />
          {loading ? 'Loading…' : 'Reload'}
        </button>
      </div>

      <section className="panel">
        <div className="panel-header" style={{ gap: 12, flexWrap: 'wrap' }}>
          <select
            className="input"
            style={{ maxWidth: 240 }}
            value={action}
            onChange={(e) => setAction(e.target.value)}
            aria-label="Filter by action"
          >
            {ACTIONS.map((a) => (
              <option key={a} value={a}>
                {a || 'All actions'}
              </option>
            ))}
          </select>
          <form
            style={{ display: 'flex', gap: 8 }}
            onSubmit={(e) => {
              e.preventDefault();
              setAppliedActor(actorId.trim());
            }}
          >
            <input
              className="input"
              placeholder="Filter by user ID"
              value={actorId}
              onChange={(e) => setActorId(e.target.value)}
              aria-label="Filter by user ID"
            />
            <button className="btn btn-secondary btn-sm" type="submit">
              Apply
            </button>
          </form>
        </div>

        {error && (
          <div className="alert error-box" role="alert">
            <IconAlertTriangle size={16} />
            <span style={{ flex: 1 }}>{error}</span>
          </div>
        )}

        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>When</th>
                <th>Action</th>
                <th>User</th>
                <th>Target</th>
                <th>Details</th>
              </tr>
            </thead>
            <tbody>
              {loading && logs.length === 0 ? (
                <tr>
                  <td className="table-state" colSpan={5}>
                    <span className="spinner" /> Loading…
                  </td>
                </tr>
              ) : logs.length === 0 ? (
                <tr>
                  <td className="table-state" colSpan={5}>
                    No audit entries match these filters.
                  </td>
                </tr>
              ) : (
                logs.map((log) => (
                  <tr key={log.id}>
                    <td>{formatDateTime(log.at)}</td>
                    <td>
                      <code>{log.action}</code>
                    </td>
                    <td>
                      <button
                        className="link-button"
                        onClick={() => {
                          setActorId(log.actorId);
                          setAppliedActor(log.actorId);
                        }}
                        title="Show only this user"
                      >
                        {log.actorId || '—'}
                      </button>
                    </td>
                    <td>{log.targetType ? `${log.targetType} ${log.targetId}` : '—'}</td>
                    <td>{formatDetails(log.details)}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
