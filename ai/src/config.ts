import { isProviderName, PROVIDER_SPECS, type ProviderName } from './providers';

export interface Config {
  provider: ProviderName;
  model: string;
  dailyTokenCap: number;
  allowedOrigins: string[];
  maxMessages: number;
  maxCharsPerMessage: number;
  maxTotalChars: number;
  maxTokens: number;
}

export const LIMITS = {
  maxMessages: 12,
  maxCharsPerMessage: 4000,
  maxTotalChars: 16000,
  maxTokens: 1024,
} as const;

export const DEFAULT_PROVIDER: ProviderName = 'workers-ai';

export const DEFAULT_DAILY_TOKEN_CAP = 100000;

export const DEFAULT_ALLOWED_ORIGINS = [
  'https://pvsouza.com',
  'https://www.pvsouza.com',
  'http://localhost:3000',
];

export interface ConfigEnv {
  CHAT_PROVIDER?: string;
  CHAT_MODEL?: string;
  GROQ_MODEL?: string;
  XAI_MODEL?: string;
  CEREBRAS_MODEL?: string;
  DAILY_TOKEN_CAP?: string;
  ALLOWED_ORIGINS?: string;
}

function resolveProvider(raw: string | undefined): ProviderName {
  const requested = raw?.trim() ?? '';
  return isProviderName(requested) ? requested : DEFAULT_PROVIDER;
}

function resolveModel(env: ConfigEnv, provider: ProviderName): string {
  const spec = PROVIDER_SPECS[provider];
  const override = env[spec.modelEnv];
  return typeof override === 'string' && override.trim().length > 0
    ? override.trim()
    : spec.defaultModel;
}

export function loadConfig(env: ConfigEnv): Config {
  const rawOrigins = env.ALLOWED_ORIGINS;
  const origins =
    rawOrigins === undefined || rawOrigins.trim().length === 0
      ? [...DEFAULT_ALLOWED_ORIGINS]
      : rawOrigins
          .split(',')
          .map((origin) => origin.trim())
          .filter((origin) => origin.length > 0);
  const parsedCap = Number.parseInt(env.DAILY_TOKEN_CAP ?? '', 10);
  const dailyTokenCap =
    Number.isFinite(parsedCap) && parsedCap > 0 ? parsedCap : DEFAULT_DAILY_TOKEN_CAP;
  const provider = resolveProvider(env.CHAT_PROVIDER);
  return {
    provider,
    model: resolveModel(env, provider),
    dailyTokenCap,
    allowedOrigins: origins,
    ...LIMITS,
  };
}
