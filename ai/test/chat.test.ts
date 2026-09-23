import { describe, expect, it, vi } from 'vitest';
import { estimateTokens, parseUpstreamFrame, toTextStream, type Usage } from '../src/chat';

function upstreamFrom(text: string): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode(text));
      controller.close();
    },
  });
}

function upstreamChunks(...chunks: string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream<Uint8Array>({
    start(controller) {
      for (const chunk of chunks) {
        controller.enqueue(encoder.encode(chunk));
      }
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

describe('parseUpstreamFrame', () => {
  it('extrai delta de um frame', () => {
    expect(parseUpstreamFrame('data: {"response":"ola"}')).toEqual({ kind: 'delta', text: 'ola' });
  });

  it('reconhece [DONE]', () => {
    expect(parseUpstreamFrame('data: [DONE]')).toEqual({ kind: 'done' });
  });

  it('ignora linhas vazias ou nao-data', () => {
    expect(parseUpstreamFrame('')).toEqual({ kind: 'ignore' });
    expect(parseUpstreamFrame(': keep-alive')).toEqual({ kind: 'ignore' });
    expect(parseUpstreamFrame('data: ')).toEqual({ kind: 'ignore' });
  });

  it('ignora JSON invalido sem lancar', () => {
    expect(parseUpstreamFrame('data: {oops')).toEqual({ kind: 'ignore' });
  });

  it('extrai delta no formato OpenAI-compat', () => {
    expect(parseUpstreamFrame('data: {"choices":[{"delta":{"content":"ola"}}]}')).toEqual({
      kind: 'delta',
      text: 'ola',
    });
  });

  it('ignora frames OpenAI-compat sem conteudo nem finish_reason', () => {
    expect(parseUpstreamFrame('data: {"choices":[{"delta":{"role":"assistant"}}]}')).toEqual({
      kind: 'ignore',
    });
  });

  it('reconhece finish_reason como fim do stream', () => {
    expect(
      parseUpstreamFrame('data: {"choices":[{"delta":{},"finish_reason":"stop"}]}'),
    ).toEqual({ kind: 'done' });
  });
});

describe('estimateTokens', () => {
  it('estima chars/4 arredondando para cima', () => {
    expect(estimateTokens(0)).toBe(0);
    expect(estimateTokens(1)).toBe(1);
    expect(estimateTokens(4)).toBe(1);
    expect(estimateTokens(5)).toBe(2);
  });
});

describe('toTextStream', () => {
  it('emite os deltas como texto puro e chama onUsage', async () => {
    const onUsage = vi.fn<(usage: Usage) => void>();
    const stream = toTextStream({
      upstream: upstreamFrom(
        'data: {"response":"ola"}\ndata: {"response":" mundo"}\ndata: [DONE]\n',
      ),
      promptChars: 8,
      onUsage,
    });
    const output = await readAll(stream);
    expect(output).toBe('ola mundo');
    expect(output).not.toContain('event:');
    expect(output).not.toContain('data:');
    expect(onUsage).toHaveBeenCalledWith({ prompt: 2, completion: 3 });
  });

  it('propaga erro quando o upstream termina sem [DONE]', async () => {
    const onError = vi.fn();
    const stream = toTextStream({
      upstream: upstreamFrom('data: {"response":"corte"}'),
      promptChars: 4,
      onUsage: () => undefined,
      onError,
    });
    await expect(readAll(stream)).rejects.toThrow('stream truncated');
    expect(onError).toHaveBeenCalledTimes(1);
    expect((onError.mock.calls[0]?.[0] as Error).message).toBe('stream truncated');
  });

  it('emite o delta quando ele e dividido entre chunks', async () => {
    const onUsage = vi.fn<(usage: Usage) => void>();
    const stream = toTextStream({
      upstream: upstreamChunks('data: {"res', 'ponse":"ola"}\ndata: [DONE]\n'),
      promptChars: 4,
      onUsage,
    });
    const output = await readAll(stream);
    expect(output).toBe('ola');
    expect(onUsage).toHaveBeenCalledWith({ prompt: 1, completion: 1 });
  });

  it('nao emite error depois de done quando onUsage rejeita', async () => {
    const onUsage = vi.fn(() => Promise.reject(new Error('boom')));
    const onError = vi.fn();
    const stream = toTextStream({
      upstream: upstreamFrom('data: {"response":"ola"}\ndata: [DONE]\n'),
      promptChars: 4,
      onUsage,
      onError,
    });
    const output = await readAll(stream);
    expect(output).toBe('ola');
    expect(onError).toHaveBeenCalledTimes(1);
    expect((onError.mock.calls[0]?.[0] as Error).message).toBe('boom');
  });

  it('traduz frames OpenAI-compat para texto puro', async () => {
    const stream = toTextStream({
      upstream: upstreamFrom(
        'data: {"choices":[{"delta":{"role":"assistant"}}]}\n' +
          'data: {"choices":[{"delta":{"content":"ola"}}]}\n' +
          'data: {"choices":[{"delta":{"content":" mundo"}}]}\n' +
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n' +
          'data: [DONE]\n',
      ),
      promptChars: 4,
      onUsage: () => undefined,
    });
    const output = await readAll(stream);
    expect(output).toBe('ola mundo');
  });

  it('conclui quando o upstream OpenAI termina sem [DONE]', async () => {
    const onError = vi.fn();
    const stream = toTextStream({
      upstream: upstreamFrom(
        'data: {"choices":[{"delta":{"content":"ola"}}]}\n' +
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n',
      ),
      promptChars: 4,
      onUsage: () => undefined,
      onError,
    });
    const output = await readAll(stream);
    expect(output).toBe('ola');
    expect(onError).not.toHaveBeenCalled();
  });
});
