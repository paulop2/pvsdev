import type { Ai, KVNamespace, RateLimit } from '@cloudflare/workers-types';

export interface Env {
  AI: Ai;
  DAILY_CAP: KVNamespace;
  CHAT_RATE: RateLimit;
  CHAT_PROVIDER?: string;
  CHAT_MODEL?: string;
  GROQ_API_KEY?: string;
  GROQ_MODEL?: string;
  XAI_API_KEY?: string;
  XAI_MODEL?: string;
  CEREBRAS_API_KEY?: string;
  CEREBRAS_MODEL?: string;
  DAILY_TOKEN_CAP: string;
  ALLOWED_ORIGINS: string;
}
