import { describe, expect, it } from 'vitest';
import { resolveMessageKind } from './chatMessages';

describe('resolveMessageKind', () => {
  it('renderiza o composer de edicao quando a mensagem esta em edicao', () => {
    expect(resolveMessageKind({ role: 'user', composer: { isEditing: true } })).toBe('edit');
  });

  it('distingue mensagem de usuario da mensagem do assistente', () => {
    expect(resolveMessageKind({ role: 'user', composer: { isEditing: false } })).toBe('user');
    expect(resolveMessageKind({ role: 'assistant', composer: { isEditing: false } })).toBe('assistant');
  });

  it('trata mensagens de sistema como do assistente', () => {
    expect(resolveMessageKind({ role: 'system', composer: { isEditing: false } })).toBe('assistant');
  });
});
