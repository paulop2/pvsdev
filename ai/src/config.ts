export interface Config {
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

export const DEFAULT_MODEL = '@cf/deepseek-ai/deepseek-v4-flash-0731';
export const DEFAULT_DAILY_TOKEN_CAP = 100000;
export const DEFAULT_ALLOWED_ORIGINS = [
  'https://pvsouza.com',
  'https://www.pvsouza.com',
  'http://localhost:3000',
];

export function loadConfig(env: {
  CHAT_MODEL?: string;
  DAILY_TOKEN_CAP?: string;
  ALLOWED_ORIGINS?: string;
}): Config {
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
  return {
    model: env.CHAT_MODEL ?? DEFAULT_MODEL,
    dailyTokenCap,
    allowedOrigins: origins,
    ...LIMITS,
  };
}
