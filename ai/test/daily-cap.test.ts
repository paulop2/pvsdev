import { describe, expect, it } from 'vitest';
import { addTokens, capKey, getUsedTokens, type CapStore } from '../src/daily-cap';

function memoryStore(initial: Record<string, string> = {}): CapStore {
  const data = { ...initial };
  return {
    get: async (key) => (key in data ? data[key] : null),
    put: async (key, value) => {
      data[key] = value;
    },
  };
}

describe('daily-cap', () => {
  it('gera chave por dia UTC', () => {
    expect(capKey(new Date('2026-09-21T23:59:00Z'))).toBe('cap:2026-09-21');
  });

  it('comeca em zero quando a chave nao existe', async () => {
    expect(await getUsedTokens(memoryStore(), 'cap:2026-09-21')).toBe(0);
  });

  it('soma tokens ao valor existente', async () => {
    const store = memoryStore({ 'cap:2026-09-21': '100' });
    await addTokens(store, 'cap:2026-09-21', 50);
    expect(await getUsedTokens(store, 'cap:2026-09-21')).toBe(150);
  });

  it('ignora valor corrompido', async () => {
    const store = memoryStore({ 'cap:2026-09-21': 'abc' });
    expect(await getUsedTokens(store, 'cap:2026-09-21')).toBe(0);
  });

  it('trata tokens negativos como zero', async () => {
    const store = memoryStore({ 'cap:2026-09-21': '10' });
    await addTokens(store, 'cap:2026-09-21', -5);
    expect(await getUsedTokens(store, 'cap:2026-09-21')).toBe(10);
  });
});
