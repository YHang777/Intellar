/**
 * Sends verification emails through the Brevo v3 transactional API
 * (https://api.brevo.com/v3/smtp/email) — faithful port of
 * `server/lib/verification_mailer.dart`. Free tier: 300 emails/day; the
 * sender address must be verified in the Brevo console.
 */

/** Safe to log; NOT shown to end users (handlers surface a generic failure). */
export class VerificationEmailException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'VerificationEmailException';
  }
}

import { BRAND, emailButton, emailCode, emailLayout, emailNote, escapeHtml } from './brand';

const SEND_TIMEOUT_MS = 20_000;

export interface VerificationMailerOptions {
  apiKey: string;
  senderEmail: string;
  senderName?: string;
  publicBaseUrl: string;
  /** Injectable for tests (defaults to global fetch). */
  fetchImpl?: typeof fetch;
}

export class VerificationMailer {
  constructor(private readonly opts: VerificationMailerOptions) {}

  get isConfigured(): boolean {
    return this.opts.apiKey.trim().length > 0;
  }

  /**
   * Override the configured public base URL (e.g. when the server derives
   * its own hostname from the incoming request instead of trusting env).
   */
  async sendVerificationEmail({
    email,
    token,
    baseUrlOverride,
  }: {
    email: string;
    token: string;
    baseUrlOverride?: string;
  }): Promise<void> {
    const link = `${this.resolveBase(baseUrlOverride)}/verify-email/confirm?token=${encodeURIComponent(token)}`;
    await this.send({
      email,
      subject: 'Verify your email — Intellar',
      html: emailHtml(link),
    });
  }

  /**
   * Deletion confirmation email — same Brevo endpoint, timeout and exception
   * type as `sendVerificationEmail`; only the link, subject and body differ.
   */
  async sendDeletionEmail({
    email,
    token,
    baseUrlOverride,
  }: {
    email: string;
    token: string;
    baseUrlOverride?: string;
  }): Promise<void> {
    const link = `${this.resolveBase(baseUrlOverride)}/account/delete/confirm?token=${encodeURIComponent(token)}`;
    await this.send({
      email,
      subject: 'Confirm account deletion — Intellar',
      html: deletionHtml(link),
    });
  }

  async sendSecurityCode({
    email,
    code,
    purpose,
  }: {
    email: string;
    code: string;
    purpose: 'login' | 'email_change';
  }): Promise<void> {
    await this.send({
      email,
      subject:
        purpose === 'login'
          ? `${code} is your Intellar sign-in code`
          : `${code} is your Intellar email change code`,
      html: codeHtml(code, purpose),
    });
  }

  private resolveBase(baseUrlOverride?: string): string {
    return baseUrlOverride && baseUrlOverride.trim().length > 0
      ? baseUrlOverride.trim()
      : this.opts.publicBaseUrl;
  }

  /** Shared Brevo v3 send — one place for endpoint, timeout and errors. */
  private async send({
    email,
    subject,
    html,
  }: {
    email: string;
    subject: string;
    html: string;
  }): Promise<void> {
    const doFetch = this.opts.fetchImpl ?? fetch;

    let resp: Response;
    try {
      resp = await doFetch('https://api.brevo.com/v3/smtp/email', {
        method: 'POST',
        headers: {
          'api-key': this.opts.apiKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          sender: {
            name: this.opts.senderName ?? 'Intellar',
            email: this.opts.senderEmail,
          },
          to: [{ email }],
          subject,
          htmlContent: html,
        }),
        signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      throw new VerificationEmailException(`Brevo request failed: ${message}`);
    }
    if (resp.status < 200 || resp.status >= 300) {
      let snippet = '';
      try {
        snippet = await resp.text();
      } catch {
        snippet = '';
      }
      if (snippet.length > 200) snippet = snippet.slice(0, 200);
      throw new VerificationEmailException(`Brevo HTTP ${resp.status}: ${snippet}`);
    }
  }
}

function emailHtml(link: string): string {
  return emailLayout({
    preheader: 'Confirm your email to start designing with Intellar.',
    eyebrow: 'Verify your email',
    title: 'Welcome to Intellar!',
    body:
      '<p style="margin:0">Thanks for creating an account. Confirm your email address to start ' +
      'designing your space, getting AI suggestions and shopping from local suppliers.</p>' +
      emailButton(link, 'Verify my email') +
      emailNote(
        `This link expires in 24 hours. If the button does not work, copy this link into your browser:<br>` +
          `<a href="${link}" style="color:${BRAND.green};word-break:break-all">${escapeHtml(link)}</a>`
      ),
    footnote: "You received this email because this address was used to sign up for Intellar. If that wasn't you, you can ignore it.",
  });
}

function codeHtml(code: string, purpose: 'login' | 'email_change'): string {
  const login = purpose === 'login';
  return emailLayout({
    preheader: `${code} is your Intellar ${login ? 'sign-in' : 'email change'} code.`,
    eyebrow: login ? 'Two-step sign-in' : 'Confirm new email',
    title: 'Your security code',
    body:
      `<p style="margin:0">${login
        ? 'Enter this code in the Intellar app to finish signing in.'
        : 'Enter this code in the Intellar app to confirm this new email address for your account.'}</p>` +
      emailCode(code) +
      `<p style="margin:12px 0 0;font-size:13px;color:${BRAND.muted}">The code expires in 10 minutes.</p>` +
      emailNote(
        "Didn't ask for this code? Someone may know your password. Change it from the app under " +
          'Profile &rsaquo; Change Password.',
        'warn'
      ),
    footnote: 'Never share this code with anyone, including people who say they work for Intellar.',
  });
}

function deletionHtml(link: string): string {
  return emailLayout({
    preheader: 'Confirm that you want to delete your Intellar account.',
    eyebrow: 'Account deletion',
    eyebrowColor: BRAND.red,
    title: 'Confirm account deletion',
    body:
      '<p style="margin:0">You asked to delete your Intellar account. Confirm with the button ' +
      'below. The link expires in 24 hours.</p>' +
      emailButton(link, 'Confirm account deletion', BRAND.red) +
      emailNote(
        '<strong>You have a 7-day recovery window.</strong> After you confirm, your account and ' +
          'personal data are deleted once 7 days pass, and your order history is kept as anonymized ' +
          'records. You can keep your account at any time during the window by signing in and ' +
          'cancelling the deletion.'
      ),
    footnote: "If you didn't ask to delete your account, ignore this email and nothing will change.",
  });
}
