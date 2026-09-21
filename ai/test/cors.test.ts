import { describe, expect, it } from 'vitest';
import { corsHeaders, isAllowedOrigin } from '../src/cors';

const allowed = ['https://pvsouza.com', 'http://localhost:3000'];

describe('cors', () => {
  it('reconhece origem permitida', () => {
    expect(isAllowedOrigin('https://pvsouza.com', allowed)).toBe(true);
  });

  it('rejeita origem nula ou desconhecida', () => {
    expect(isAllowedOrigin(null, allowed)).toBe(false);
    expect(isAllowedOrigin('https://evil.example', allowed)).toBe(false);
  });

  it('ecoa a origem permitida nos headers', () => {
    const headers = corsHeaders('https://pvsouza.com', allowed);
    expect(headers['Access-Control-Allow-Origin']).toBe('https://pvsouza.com');
    expect(headers['Access-Control-Allow-Methods']).toBe('POST, OPTIONS');
    expect(headers['Access-Control-Allow-Headers']).toBe('content-type');
  });

  it('nao ecoa origem desconhecida', () => {
    const headers = corsHeaders('https://evil.example', allowed);
    expect(headers['Access-Control-Allow-Origin']).toBeUndefined();
  });
});
