import { useState } from 'react';
import { usersApi } from '../api/api';
import { ApiError } from '../api/client';
import { Modal } from './Modal';
import { IconAlertTriangle, IconUsers } from './icons';

interface Props {
  guests: number;
  onClose: () => void;
  onDone: (removed: number) => void;
}

export function PurgeGuestsDialog({ guests, onClose, onDone }: Props) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const confirm = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const res = await usersApi.purgeGuests(1);
      onDone(res.removed);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Could not remove guests. Please try again.');
      setBusy(false);
    }
  };

  return (
    <Modal
      title="Remove idle guests"
      onClose={busy ? () => undefined : onClose}
      width={480}
      headerIcon={<IconUsers size={16} />}
    >
      <p className="modal-lead">
        There {guests === 1 ? 'is' : 'are'} <strong>{guests.toLocaleString()}</strong> guest session
        {guests === 1 ? '' : 's'} from people who tapped “Explore as a guest”.
      </p>
      <ul className="modal-notes">
        <li>Guests are not customers or suppliers, so they are not listed in the table.</li>
        <li>This removes guest sessions not used in the last hour. Anyone browsing right now is kept.</li>
        <li>Guests cannot buy or sell, so no orders or listings are affected.</li>
        <li>Guest sessions unused for 7 days are also removed automatically.</li>
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
          {busy ? 'Removing…' : 'Remove idle guests'}
        </button>
      </div>
    </Modal>
  );
}
