import { describe, expect, it, vi } from 'vitest';
import type { Ai } from '@cloudflare/workers-types';
import {
  createOpenAiCompatibleProvider,
  createProvider,
  createWorkersAiProvider,
  isProviderName,
  type ProviderRunArgs,
} from '../src/providers';

const encoder = new TextEncoder();

function upstream(text: string): ReadableStream<Uint8Array> {
  return new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode(text));
      controller.close();
    },
  });
}

async function readAll(stream: ReadableStream<Uint8Array>): Promise<string> {
  const decoder = new TextDecoder();
  const reader = stream.getReader();
  let output = '';
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    output += decoder.decode(value, { stream: true });
  }
  return output;
}

const args: ProviderRunArgs = {
  model: 'test-model',
  messages: [{ role: 'user', content: 'oi' }],
  maxTokens: 128,
};

function fakeAi(result: unknown): Ai {
  return { run: vi.fn(async () => result) } as unknown as Ai;
}

describe('isProviderName', () => {
  it('reconhece os providers suportados', () => {
    expect(isProviderName('workers-ai')).toBe(true);
    expect(isProviderName('groq')).toBe(true);
    expect(isProviderName('xai')).toBe(true);
    expect(isProviderName('cerebras')).toBe(true);
  });

  it('rejeita nomes desconhecidos', () => {
    expect(isProviderName('openai')).toBe(false);
    expect(isProviderName('')).toBe(false);
  });
});

describe('createWorkersAiProvider', () => {
  it('chama o binding AI com stream e devolve o stream', async () => {
    const ai = fakeAi(upstream('data: {"response":"ola"}\n'));
    const provider = createWorkersAiProvider(ai);
    expect(provider.name).toBe('workers-ai');
    const stream = await provider.run(args);
    expect(await readAll(stream)).toContain('ola');
    expect(ai.run).toHaveBeenCalledWith('test-model', {
      messages: args.messages,
      max_tokens: 128,
      stream: true,
    });
  });
});

describe('createOpenAiCompatibleProvider', () => {
  it('faz POST no endpoint chat/completions com auth e corpo do stream', async () => {
    const fetchImpl = vi.fn(async () => new Response(upstream('data: [DONE]\n')));
    const provider = createOpenAiCompatibleProvider({
      name: 'groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      apiKey: 'secret-key',
      fetchImpl: fetchImpl as unknown as typeof fetch,
    });
    expect(provider.name).toBe('groq');
    const stream = await provider.run(args);
    expect(await readAll(stream)).toContain('data: [DONE]');
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://api.groq.com/openai/v1/chat/completions');
    expect(init.method).toBe('POST');
    expect((init.headers as Record<string, string>).authorization).toBe('Bearer secret-key');
    expect(JSON.parse(init.body as string)).toEqual({
      model: 'test-model',
      messages: args.messages,
      max_tokens: 128,
      stream: true,
    });
  });

  it('falha quando o upstream responde com erro', async () => {
    const fetchImpl = vi.fn(async () => new Response('nope', { status: 429 }));
    const provider = createOpenAiCompatibleProvider({
      name: 'xai',
      baseUrl: 'https://api.x.ai/v1',
      apiKey: 'secret-key',
      fetchImpl: fetchImpl as unknown as typeof fetch,
    });
    await expect(provider.run(args)).rejects.toThrow('429');
  });

  it('falha quando a API key nao esta configurada', async () => {
    const fetchImpl = vi.fn();
    const provider = createOpenAiCompatibleProvider({
      name: 'cerebras',
      baseUrl: 'https://api.cerebras.ai/v1',
      apiKey: undefined,
      fetchImpl: fetchImpl as unknown as typeof fetch,
    });
    await expect(provider.run(args)).rejects.toThrow('not configured');
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});

describe('createProvider', () => {
  const env = {
    AI: fakeAi(upstream('data: [DONE]\n')),
    GROQ_API_KEY: 'g',
    XAI_API_KEY: 'x',
    CEREBRAS_API_KEY: 'c',
  };

  it('seleciona os endpoints OpenAI-compat por nome', async () => {
    const cases = [
      ['groq', 'https://api.groq.com/openai/v1/chat/completions'],
      ['xai', 'https://api.x.ai/v1/chat/completions'],
      ['cerebras', 'https://api.cerebras.ai/v1/chat/completions'],
    ] as const;
    for (const [name, url] of cases) {
      const fetchImpl = vi.fn(
        async (_url: string, _init?: RequestInit) => new Response(upstream('data: [DONE]\n')),
      );
      const provider = createProvider(
        env,
        name,
        fetchImpl as unknown as typeof fetch,
      );
      expect(provider.name).toBe(name);
      await provider.run(args);
      expect(fetchImpl.mock.calls[0]?.[0]).toBe(url);
    }
  });

  it('usa o binding AI para workers-ai', () => {
    const provider = createProvider(env, 'workers-ai');
    expect(provider.name).toBe('workers-ai');
  });
});
