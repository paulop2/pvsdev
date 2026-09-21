import { describe, expect, it, vi } from 'vitest';
import { createHandler, type HandlerDeps } from '../src/handler';
import { loadConfig } from '../src/config';
import type { ModelMessage, Usage } from '../src/chat';

const encoder = new TextEncoder();

function upstream(text: string): ReadableStream<Uint8Array> {
  return new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode(text));
      controller.close();
    },
  });
}

function makeDeps(overrides: Partial<HandlerDeps> = {}): HandlerDeps {
  const config = loadConfig({
    CHAT_MODEL: 'test-model',
    DAILY_TOKEN_CAP: '1000',
    ALLOWED_ORIGINS: 'https://pvsouza.com',
  });
  const deps: HandlerDeps = {
    config,
    verifyTurnstile: async () => true,
    checkRate: async () => true,
    getUsedTokens: async () => 0,
    addTokens: async () => undefined,
    runModel: async () => upstream('data: {"response":"ola"}\ndata: [DONE]\n'),
    log: () => undefined,
    ...overrides,
  };
  return deps;
}

const validBody = {
  messages: [{ role: 'user', content: 'oi' }],
  turnstileToken: 'token',
};

function chatRequest(body: unknown, origin = 'https://pvsouza.com'): Request {
  return new Request('https://ai.pvsouza.com/chat', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin },
    body: JSON.stringify(body),
  });
}

describe('createHandler', () => {
  it('responde preflight 204 com headers CORS', async () => {
    const handler = createHandler(makeDeps());
    const response = await handler(
      new Request('https://ai.pvsouza.com/chat', {
        method: 'OPTIONS',
        headers: { origin: 'https://pvsouza.com' },
      }),
    );
    expect(response.status).toBe(204);
    expect(response.headers.get('access-control-allow-origin')).toBe('https://pvsouza.com');
  });

  it('bloqueia origem fora da allowlist', async () => {
    const runModel = vi.fn();
    const handler = createHandler(makeDeps({ runModel }));
    const response = await handler(chatRequest(validBody, 'https://evil.example'));
    expect(response.status).toBe(403);
    expect((await response.json<{ code: string }>()).code).toBe('origin_not_allowed');
    expect(runModel).not.toHaveBeenCalled();
  });

  it('rejeita JSON invalido com 400', async () => {
    const runModel = vi.fn();
    const handler = createHandler(makeDeps({ runModel }));
    const response = await handler(
      new Request('https://ai.pvsouza.com/chat', {
        method: 'POST',
        headers: { 'content-type': 'application/json', origin: 'https://pvsouza.com' },
        body: '{oops',
      }),
    );
    expect(response.status).toBe(400);
    expect((await response.json<{ code: string }>()).code).toBe('invalid_request');
    expect(runModel).not.toHaveBeenCalled();
  });

  it('rejeita payload invalido com 400', async () => {
    const runModel = vi.fn();
    const handler = createHandler(makeDeps({ runModel }));
    const response = await handler(chatRequest({ messages: [] }));
    expect(response.status).toBe(400);
    expect(runModel).not.toHaveBeenCalled();
  });

  it('bloqueia Turnstile invalido com 403 e nao chama a IA', async () => {
    const runModel = vi.fn();
    const handler = createHandler(makeDeps({ verifyTurnstile: async () => false, runModel }));
    const response = await handler(chatRequest(validBody));
    expect(response.status).toBe(403);
    expect((await response.json<{ code: string }>()).code).toBe('turnstile_failed');
    expect(runModel).not.toHaveBeenCalled();
  });

  it('responde 429 com Retry-After quando o rate limita', async () => {
    const runModel = vi.fn();
    const handler = createHandler(makeDeps({ checkRate: async () => false, runModel }));
    const response = await handler(chatRequest(validBody));
    expect(response.status).toBe(429);
    expect(response.headers.get('retry-after')).toBe('60');
    expect((await response.json<{ code: string }>()).code).toBe('rate_limited');
    expect(runModel).not.toHaveBeenCalled();
  });

  it('responde 429 quando o teto diario foi atingido e nao chama a IA', async () => {
    const runModel = vi.fn();
    const handler = createHandler(makeDeps({ getUsedTokens: async () => 1000, runModel }));
    const response = await handler(chatRequest(validBody));
    expect(response.status).toBe(429);
    expect((await response.json<{ code: string }>()).code).toBe('daily_cap_exceeded');
    expect(runModel).not.toHaveBeenCalled();
  });

  it('responde 502 quando a IA falha antes do stream', async () => {
    const handler = createHandler(
      makeDeps({
        runModel: async () => {
          throw new Error('upstream down');
        },
      }),
    );
    const response = await handler(chatRequest(validBody));
    expect(response.status).toBe(502);
    expect((await response.json<{ code: string }>()).code).toBe('upstream_error');
  });

  it('injeta o system prompt como primeira mensagem', async () => {
    const seen: ModelMessage[][] = [];
    const handler = createHandler(
      makeDeps({
        runModel: async ({ messages }) => {
          seen.push(messages);
          return upstream('data: {"response":"ok"}\ndata: [DONE]\n');
        },
      }),
    );
    await handler(chatRequest(validBody));
    expect(seen[0][0].role).toBe('system');
    expect(seen[0][1]).toEqual({ role: 'user', content: 'oi' });
  });

  it('transmite SSE e registra o uso de tokens', async () => {
    const addTokens = vi.fn<(tokens: number) => Promise<void>>(async () => undefined);
    const handler = createHandler(makeDeps({ addTokens }));
    const response = await handler(chatRequest(validBody));
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('text/event-stream');
    const text = await response.text();
    expect(text).toContain('event: token');
    expect(text).toContain('event: done');
    expect(addTokens).toHaveBeenCalledTimes(1);
  });

  it('responde 405 para metodo diferente de POST', async () => {
    const handler = createHandler(makeDeps());
    const response = await handler(
      new Request('https://ai.pvsouza.com/chat', {
        method: 'GET',
        headers: { origin: 'https://pvsouza.com' },
      }),
    );
    expect(response.status).toBe(405);
  });

  it('responde 404 em rota desconhecida', async () => {
    const handler = createHandler(makeDeps());
    const response = await handler(
      new Request('https://ai.pvsouza.com/nope', {
        method: 'GET',
        headers: { origin: 'https://pvsouza.com' },
      }),
    );
    expect(response.status).toBe(404);
  });
});
