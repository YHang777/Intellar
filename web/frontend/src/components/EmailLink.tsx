import type { KeyboardEvent } from 'react';

export function gmailComposeUrl(email: string): string {
  return `https://mail.google.com/mail/?view=cm&fs=1&to=${encodeURIComponent(email)}`;
}

// Double-click (or Enter) opens a new Gmail message to this address.
export function EmailLink({ email }: { email: string }) {
  if (!email) return <span className="mono">—</span>;
  const open = () => window.open(gmailComposeUrl(email), '_blank', 'noopener,noreferrer');
  const onKey = (e: KeyboardEvent<HTMLSpanElement>) => {
    if (e.key === 'Enter') open();
  };
  return (
    <span
      className="mono email-link"
      role="link"
      tabIndex={0}
      title="Double-click to email in Gmail"
      onDoubleClick={open}
      onKeyDown={onKey}
    >
      {email}
    </span>
  );
}
