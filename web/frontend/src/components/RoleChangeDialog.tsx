import { useState } from 'react';
import { usersApi } from '../api/api';
import { ApiError } from '../api/client';
import type { AdminUserRow } from '../api/types';
import { Modal } from './Modal';
import { IconAlertTriangle, IconUsers } from './icons';

type AccountRole = 'homeowner' | 'supplier';

const LABEL: Record<AccountRole, string> = { homeowner: 'Customer', supplier: 'Supplier' };

interface Props {
  user: AdminUserRow;
  next: AccountRole;
  onClose: () => void;
  onChanged: (user: AdminUserRow, next: AccountRole) => void;
}

export function RoleChangeDialog({ user, next, onClose, onChanged }: Props) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const from = user.role === 'supplier' ? 'Supplier' : 'Customer';

  const confirm = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      await usersApi.setRole(user.uid, next);
      onChanged(user, next);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Role change failed. Please try again.');
      setBusy(false);
    }
  };

  return (
    <Modal
      title="Change role"
      onClose={busy ? () => undefined : onClose}
      width={480}
      headerIcon={<IconUsers size={16} />}
    >
      <p className="modal-lead">
        Change <strong>{user.email}</strong> from <strong>{from}</strong> to{' '}
        <strong>{LABEL[next]}</strong>?
      </p>
      <ul className="modal-notes">
        <li>Use this only for an account that signed up with the wrong role.</li>
        <li>It is refused once the account has orders or product listings.</li>
        <li>
          {next === 'supplier'
            ? 'They start unverified and must apply with their IC before getting the Verified badge.'
            : 'Their business details are cleared.'}
        </li>
        <li>If they are signed in, they should sign out and back in.</li>
      </ul>

      {error && (
        <div className="alert error-box" role="alert">
          <IconAlertTriangle size={16} />
          <span>{error}</span>
        </div>
      )}

      <div className="modal-actions">
        <button className="btn btn-ghost" onClick={onClose} disabled={busy}>
          Cancel
        </button>
        <button className="btn btn-primary" onClick={() => void confirm()} disabled={busy}>
          {busy && <span className="spinner spinner-inline" />}
          {busy ? 'Changing…' : `Make ${LABEL[next]}`}
        </button>
      </div>
    </Modal>
  );
}
