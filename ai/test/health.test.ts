import { describe, expect, it } from 'vitest';
import worker from '../src/index';
import type { Env } from '../src/env';

const env = {
  CHAT_MODEL: 'test-model',
  DAILY_TOKEN_CAP: '1000',
  ALLOWED_ORIGINS: 'https://pvsouza.com',
  TURNSTILE_SECRET: 'secret',
} as unknown as Env;

describe('health', () => {
  it('responde ok em GET /health', async () => {
    const response = await worker.fetch(new Request('https://ai.pvsouza.com/health'), env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: 'ok' });
  });

  it('responde 404 em rota desconhecida', async () => {
    const response = await worker.fetch(new Request('https://ai.pvsouza.com/nope'), env);
    expect(response.status).toBe(404);
  });
});
