import { describe, expect, it } from 'vitest';
import { validateChatRequest } from '../src/validation';
import { loadConfig } from '../src/config';

const config = loadConfig({});

const valid = {
  messages: [{ role: 'user', content: 'ola' }],
  turnstileToken: 'token',
};

describe('validateChatRequest', () => {
  it('aceita payload valido', () => {
    const result = validateChatRequest(valid, config);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.messages).toHaveLength(1);
      expect(result.value.turnstileToken).toBe('token');
    }
  });

  it('rejeita corpo nao-objeto', () => {
    expect(validateChatRequest(null, config).ok).toBe(false);
    expect(validateChatRequest('x', config).ok).toBe(false);
  });

  it('rejeita turnstileToken ausente', () => {
    const result = validateChatRequest({ messages: valid.messages }, config);
    expect(result.ok).toBe(false);
  });

  it('rejeita lista de mensagens vazia', () => {
    expect(validateChatRequest({ ...valid, messages: [] }, config).ok).toBe(false);
  });

  it('rejeita papel invalido', () => {
    const result = validateChatRequest(
      { ...valid, messages: [{ role: 'system', content: 'x' }] },
      config,
    );
    expect(result.ok).toBe(false);
  });

  it('rejeita ultima mensagem que nao e do usuario', () => {
    const result = validateChatRequest(
      {
        ...valid,
        messages: [
          { role: 'user', content: 'a' },
          { role: 'assistant', content: 'b' },
        ],
      },
      config,
    );
    expect(result.ok).toBe(false);
  });

  it('rejeita mais de 12 mensagens', () => {
    const messages = Array.from({ length: 13 }, (_, i) => ({
      role: i % 2 === 0 ? 'user' : 'assistant',
      content: 'x',
    }));
    const result = validateChatRequest({ ...valid, messages }, config);
    expect(result.ok).toBe(false);
  });

  it('rejeita mensagem com mais de 4000 chars', () => {
    const result = validateChatRequest(
      { ...valid, messages: [{ role: 'user', content: 'x'.repeat(4001) }] },
      config,
    );
    expect(result.ok).toBe(false);
  });

  it('rejeita total acima de 16000 chars', () => {
    const result = validateChatRequest(
      {
        ...valid,
        messages: [
          { role: 'user', content: 'x'.repeat(4000) },
          { role: 'assistant', content: 'y'.repeat(4000) },
          { role: 'user', content: 'z'.repeat(4000) },
          { role: 'assistant', content: 'w'.repeat(4000) },
          { role: 'user', content: 'v'.repeat(1) },
        ],
      },
      config,
    );
    expect(result.ok).toBe(false);
  });
});
