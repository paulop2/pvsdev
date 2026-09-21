const SITEVERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';

export interface TurnstileOptions {
  secret: string;
  token: string;
  ip: string | null;
  fetchImpl?: (input: string, init?: RequestInit) => Promise<Response>;
}

export async function verifyTurnstile(options: TurnstileOptions): Promise<boolean> {
  if (
    typeof options.secret !== 'string' ||
    options.secret.trim().length === 0 ||
    typeof options.token !== 'string' ||
    options.token.trim().length === 0
  ) {
    return false;
  }
  const secret = options.secret.trim();
  const token = options.token.trim();
  const doFetch = options.fetchImpl ?? fetch;
  const body = new URLSearchParams();
  body.set('secret', secret);
  body.set('response', token);
  if (options.ip !== null && options.ip.length > 0) {
    body.set('remoteip', options.ip);
  }
  try {
    const response = await doFetch(SITEVERIFY_URL, { method: 'POST', body });
    if (!response.ok) {
      return false;
    }
    const data = (await response.json()) as { success?: boolean };
    return data.success === true;
  } catch {
    return false;
  }
}
