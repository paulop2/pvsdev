import { describe, expect, it } from 'vitest';
import { SYSTEM_PROMPT } from '../src/system-prompt';

describe('SYSTEM_PROMPT', () => {
  it('e uma string nao vazia', () => {
    expect(typeof SYSTEM_PROMPT).toBe('string');
    expect(SYSTEM_PROMPT.trim().length).toBeGreaterThan(50);
  });

  it('define a persona do portfolio e o idioma', () => {
    expect(SYSTEM_PROMPT.toLowerCase()).toContain('portfolio');
    expect(SYSTEM_PROMPT.toLowerCase()).toContain('idioma');
  });
});
