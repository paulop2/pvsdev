import { describe, expect, it } from 'vitest';
import type { UIMessage, UIMessageChunk } from 'ai';
import { messageText, toWorkerMessages, TurnstileChatTransport } from './chatTransport';

function message(role: 'user' | 'assistant' | 'system', parts: UIMessage['parts']): UIMessage {
  return { id: `${role}-${parts.length}`, role, parts } as UIMessage;
}

describe('messageText', () => {
  it('concatena os parts de texto', () => {
    expect(
      messageText(
        message('assistant', [
          { type: 'text', text: 'ola' },
          { type: 'text', text: ' mundo' },
        ]),
      ),
    ).toBe('ola mundo');
  });

  it('ignora parts que nao sao texto', () => {
    expect(
      messageText(
        message('user', [
          { type: 'text', text: 'veja' },
          { type: 'file', mediaType: 'image/png', url: 'data:image/png;base64,xx' },
        ]),
      ),
    ).toBe('veja');
  });
});

describe('toWorkerMessages', () => {
  it('converte parts de texto para o contrato do Worker', () => {
    expect(
      toWorkerMessages([
        message('user', [{ type: 'text', text: 'oi' }]),
        message('assistant', [{ type: 'text', text: 'ola' }]),
      ]),
    ).toEqual([
      { role: 'user', content: 'oi' },
      { role: 'assistant', content: 'ola' },
    ]);
  });

  it('descarta mensagens vazias e papeis desconhecidos', () => {
    expect(
      toWorkerMessages([
        message('user', [{ type: 'text', text: '   ' }]),
        message('system', [{ type: 'text', text: 'instrucao' }]),
        message('user', [{ type: 'text', text: 'oi' }]),
      ]),
    ).toEqual([{ role: 'user', content: 'oi' }]);
  });

  it('limita as ultimas 12 mensagens', () => {
    const messages = Array.from({ length: 15 }, (_, index) =>
      message(index % 2 === 0 ? 'user' : 'assistant', [{ type: 'text', text: `m${index}` }]),
    );
    const converted = toWorkerMessages(messages);
    expect(converted).toHaveLength(12);
    expect(converted[0]).toEqual({ role: 'assistant', content: 'm3' });
    expect(converted[11]).toEqual({ role: 'user', content: 'm14' });
  });
});

async function readChunks(stream: ReadableStream<UIMessageChunk>): Promise<UIMessageChunk[]> {
  const chunks: UIMessageChunk[] = [];
  const reader = stream.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
  }
  return chunks;
}

describe('TurnstileChatTransport', () => {
  it('anexa o token, converte as mensagens e reseta apos a requisicao', async () => {
    const requests: Array<{ url: string; body: unknown }> = [];
    const fetchMock = (async (input: RequestInfo | URL, init?: RequestInit) => {
      requests.push({ url: String(input), body: JSON.parse(String(init?.body ?? '{}')) });
      return new Response('ola mundo', {
        status: 200,
        headers: { 'content-type': 'text/plain' },
      });
    }) as typeof fetch;
    let settled = 0;
    const transport = new TurnstileChatTransport({
      api: 'https://ai.example/chat',
      getToken: () => 'tok-123',
      onRequestSettled: () => {
        settled += 1;
      },
      fetch: fetchMock,
    });

    const stream = await transport.sendMessages({
      trigger: 'submit-message',
      chatId: 'c1',
      messageId: undefined,
      messages: [message('user', [{ type: 'text', text: 'oi' }])],
      abortSignal: undefined,
    });
    const chunks = await readChunks(stream);

    expect(requests).toEqual([
      {
        url: 'https://ai.example/chat',
        body: { messages: [{ role: 'user', content: 'oi' }], turnstileToken: 'tok-123' },
      },
    ]);
    const deltas = chunks
      .filter((chunk): chunk is Extract<UIMessageChunk, { type: 'text-delta' }> => chunk.type === 'text-delta')
      .map((chunk) => chunk.delta)
      .join('');
    expect(deltas).toBe('ola mundo');
    expect(settled).toBe(1);
  });
});
