import { describe, expect, it } from 'vitest';
import { COMPOSER_SHORTCUT_HINT, resolveComposerKey } from './chatKeyboard';

const base = { key: 'a', shiftKey: false, isRunning: false };

describe('resolveComposerKey', () => {
  it('envia com Enter quando nao ha geracao em andamento', () => {
    expect(resolveComposerKey({ ...base, key: 'Enter' })).toBe('send');
  });

  it('insere nova linha com Shift+Enter', () => {
    expect(resolveComposerKey({ ...base, key: 'Enter', shiftKey: true })).toBe(
      'newline',
    );
  });

  it('nao envia com Enter durante a geracao', () => {
    expect(resolveComposerKey({ ...base, key: 'Enter', isRunning: true })).toBe(
      'none',
    );
  });

  it('para a geracao com Escape apenas quando ela esta em andamento', () => {
    expect(
      resolveComposerKey({ ...base, key: 'Escape', isRunning: true }),
    ).toBe('stop');
    expect(resolveComposerKey({ ...base, key: 'Escape' })).toBe('none');
  });

  it('ignora outras teclas', () => {
    expect(resolveComposerKey({ ...base, key: 'a' })).toBe('none');
    expect(resolveComposerKey({ ...base, key: 'ArrowDown' })).toBe('none');
  });

  it('nao dispara acao durante composicao de IME', () => {
    expect(
      resolveComposerKey({ ...base, key: 'Enter', isComposing: true }),
    ).toBe('none');
    expect(
      resolveComposerKey({
        ...base,
        key: 'Escape',
        isRunning: true,
        isComposing: true,
      }),
    ).toBe('none');
  });
});

describe('COMPOSER_SHORTCUT_HINT', () => {
  it('descreve os tres atalhos do composer', () => {
    expect(COMPOSER_SHORTCUT_HINT).toContain('Enter');
    expect(COMPOSER_SHORTCUT_HINT).toContain('Shift+Enter');
    expect(COMPOSER_SHORTCUT_HINT).toContain('Escape');
  });
});
