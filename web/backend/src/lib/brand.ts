import type { Response } from 'express';

// One look for everything Intellar sends outside the app: transactional
// emails and the pages their links open. Matches the app: navy text, green
// accent, rounded white cards, the Intellar logo.

export const BRAND = {
  name: 'Intellar',
  tagline: 'AI & AR Interior Design',
  green: '#2E7D32',
  greenLight: '#E8F5E9',
  navy: '#1A1A2E',
  text: '#4A4F5C',
  muted: '#8A8F99',
  red: '#C62828',
  redLight: '#FDECEA',
  bg: '#F3F5F2',
  publicBase: process.env.SHARE_BASE_URL || 'https://interior-design-recommendation.onrender.com',
};

export const logoUrl = () => `${BRAND.publicBase}/admin/brand-logo.png`;

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ── emails (tables + inline styles: what Gmail, Outlook and Apple Mail agree on) ──

export function emailButton(href: string, label: string, color = BRAND.green): string {
  return `
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:28px 0 8px">
  <tr><td bgcolor="${color}" style="border-radius:10px">
    <a href="${href}" target="_blank" style="display:inline-block;padding:14px 30px;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:10px">${label}</a>
  </td></tr>
</table>`;
}

export function emailCode(code: string): string {
  const digits = code
    .split('')
    .map((d) => `<span style="display:inline-block;width:38px">${escapeHtml(d)}</span>`)
    .join('');
  return `
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:24px 0 8px">
  <tr><td align="center" bgcolor="${BRAND.greenLight}" style="border-radius:12px;padding:20px 8px;font-family:Consolas,Menlo,monospace;font-size:34px;font-weight:700;color:${BRAND.navy};letter-spacing:2px">${digits}</td></tr>
</table>`;
}

export function emailNote(html: string, tone: 'info' | 'warn' = 'info'): string {
  const bg = tone === 'warn' ? BRAND.redLight : '#F4F6F8';
  return `
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:20px 0 0">
  <tr><td bgcolor="${bg}" style="border-radius:10px;padding:14px 16px;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;font-size:13px;line-height:1.6;color:${BRAND.text}">${html}</td></tr>
</table>`;
}

export function emailLayout({
  preheader,
  eyebrow,
  title,
  body,
  footnote,
  eyebrowColor = BRAND.green,
}: {
  preheader: string;
  eyebrowColor?: string;
  eyebrow: string;
  title: string;
  body: string;
  footnote: string;
}): string {
  const font = 'Segoe UI,Roboto,Helvetica,Arial,sans-serif';
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light only">
<title>${escapeHtml(title)}</title>
</head>
<body style="margin:0;padding:0;background:${BRAND.bg}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">${escapeHtml(preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${BRAND.bg}">
  <tr><td align="center" style="padding:32px 16px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px">
      <tr><td align="center" style="padding:0 0 20px">
        <img src="${logoUrl()}" width="72" height="72" alt="Intellar" style="display:block;border:0;border-radius:16px">
      </td></tr>
      <tr><td bgcolor="#ffffff" style="border-radius:18px;padding:36px 32px;border:1px solid #E6E9E4">
        <div style="font-family:${font};font-size:12px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:${eyebrowColor};margin:0 0 10px">${escapeHtml(eyebrow)}</div>
        <h1 style="font-family:${font};font-size:24px;line-height:1.3;color:${BRAND.navy};margin:0 0 14px">${escapeHtml(title)}</h1>
        <div style="font-family:${font};font-size:15px;line-height:1.65;color:${BRAND.text}">${body}</div>
      </td></tr>
      <tr><td align="center" style="padding:22px 12px 0;font-family:${font};font-size:12px;line-height:1.6;color:${BRAND.muted}">
        ${footnote}<br><br>
        <strong style="color:${BRAND.navy}">${BRAND.name}</strong> &middot; ${BRAND.tagline}<br>
        This is an automated message, please do not reply.
      </td></tr>
    </table>
  </td></tr>
</table>
</body>
</html>`;
}

// ── web pages opened from email links ──

const ICONS = {
  success: `<svg viewBox="0 0 24 24" width="34" height="34" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>`,
  error: `<svg viewBox="0 0 24 24" width="34" height="34" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M7 7l10 10M17 7L7 17"/></svg>`,
  info: `<svg viewBox="0 0 24 24" width="34" height="34" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 7.6v.2"/></svg>`,
};

export function renderBrandPage(
  res: Response,
  {
    tone,
    title,
    message,
    note,
    status = 200,
    openApp = false,
  }: {
    tone: 'success' | 'error' | 'info';
    title: string;
    message: string;
    note?: string;
    status?: number;
    openApp?: boolean;
  }
): void {
  const appLink = 'intent://open/login#Intent;scheme=intellar;package=com.example.interior_design_recommendation;end';
  res
    .status(status)
    .type('html')
    .set('Cache-Control', 'no-store')
    .send(`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} · Intellar</title>
<link rel="icon" href="/admin/favicon.png">
<style>
  :root { --bg:${BRAND.bg}; --card:#fff; --text:${BRAND.text}; --title:${BRAND.navy}; --muted:${BRAND.muted};
    --green:${BRAND.green}; --green-soft:${BRAND.greenLight}; --red:${BRAND.red}; --red-soft:${BRAND.redLight};
    --line:#E6E9E4; --note:#F4F6F8; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#14161A; --card:#1E2127; --text:#C9CDD4; --title:#F2F3F5; --muted:#8C929C;
      --green-soft:#1F3323; --red-soft:#3A2224; --line:#2C3038; --note:#262A31; }
  }
  * { box-sizing:border-box; }
  body { margin:0; min-height:100vh; display:flex; flex-direction:column; align-items:center;
    background:var(--bg); color:var(--text); font-family:"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }
  header { width:100%; max-width:520px; padding:28px 20px 8px; display:flex; align-items:center; gap:12px; }
  header img { width:44px; height:44px; border-radius:12px; background:#fff; }
  header b { display:block; color:var(--title); font-size:17px; }
  header span { font-size:12px; color:var(--muted); }
  main { flex:1; width:100%; max-width:520px; padding:12px 16px 24px; display:flex; align-items:flex-start; }
  .card { width:100%; background:var(--card); border:1px solid var(--line); border-radius:20px;
    padding:36px 28px 30px; text-align:center; box-shadow:0 10px 30px rgba(20,30,20,.07); }
  .icon { width:72px; height:72px; border-radius:50%; display:inline-flex; align-items:center;
    justify-content:center; margin-bottom:18px; }
  .success { background:var(--green-soft); color:var(--green); }
  .error { background:var(--red-soft); color:var(--red); }
  .info { background:var(--note); color:var(--title); }
  h1 { margin:0 0 10px; color:var(--title); font-size:24px; }
  p { margin:0 auto; max-width:380px; line-height:1.6; font-size:15px; }
  .note { margin-top:20px; background:var(--note); border-radius:12px; padding:14px 16px; font-size:13.5px; }
  .btn { display:none; margin-top:24px; padding:13px 24px; border-radius:12px; background:var(--green);
    color:#fff; font-weight:600; text-decoration:none; }
  footer { padding:8px 16px 28px; font-size:12px; color:var(--muted); text-align:center; }
</style>
</head>
<body>
<header>
  <img src="/admin/brand-logo.png" alt="">
  <div><b>${BRAND.name}</b><span>${BRAND.tagline}</span></div>
</header>
<main>
  <div class="card">
    <div class="icon ${tone}">${ICONS[tone]}</div>
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(message)}</p>
    ${note ? `<p class="note">${escapeHtml(note)}</p>` : ''}
    ${openApp ? `<a class="btn" id="open" href="${appLink}">Open the Intellar app</a>` : ''}
  </div>
</main>
<footer>&copy; ${new Date().getFullYear()} ${BRAND.name} &middot; You can close this page.</footer>
${openApp ? `<script>if(/Android/i.test(navigator.userAgent)){document.getElementById('open').style.display='inline-block';}</script>` : ''}
</body>
</html>`);
}
