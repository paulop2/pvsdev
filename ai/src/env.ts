import type { Ai, KVNamespace, RateLimit } from '@cloudflare/workers-types';

export interface Env {
  AI: Ai;
  DAILY_CAP: KVNamespace;
  CHAT_RATE: RateLimit;
  CHAT_MODEL: string;
  DAILY_TOKEN_CAP: string;
  ALLOWED_ORIGINS: string;
  TURNSTILE_SECRET: string;
}
