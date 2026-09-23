import { describe, expect, it } from 'vitest';
import {
  normalizeThreadTitle,
  THREAD_TITLE_FALLBACK,
  threadTitleFallback,
} from './chatThreads';

describe('threadTitleFallback', () => {
  it('usa o titulo quando presente', () => {
    expect(threadTitleFallback('Projetos')).toBe('Projetos');
  });

  it('usa o fallback para titulo ausente ou vazio', () => {
    expect(threadTitleFallback(undefined)).toBe(THREAD_TITLE_FALLBACK);
    expect(threadTitleFallback(null)).toBe(THREAD_TITLE_FALLBACK);
    expect(threadTitleFallback('   ')).toBe(THREAD_TITLE_FALLBACK);
  });
});

describe('normalizeThreadTitle', () => {
  it('apara espacos nas extremidades', () => {
    expect(normalizeThreadTitle('  Projetos  ', undefined)).toBe('Projetos');
  });

  it('recusa titulo vazio', () => {
    expect(normalizeThreadTitle('   ', 'Projetos')).toBeNull();
  });

  it('recusa titulo inalterado', () => {
    expect(normalizeThreadTitle('Projetos', 'Projetos')).toBeNull();
    expect(normalizeThreadTitle(' Projetos ', 'Projetos')).toBeNull();
    expect(normalizeThreadTitle('Projetos', undefined)).toBe('Projetos');
  });

  it('aceita um titulo novo', () => {
    expect(normalizeThreadTitle('Stack', 'Projetos')).toBe('Stack');
  });
});
