import { describe, expect, it } from 'vitest';
import { DEFAULT_PROVIDER, loadConfig } from '../src/config';
import { PROVIDER_SPECS } from '../src/providers';

describe('loadConfig', () => {
  it('usa Workers AI por padrao', () => {
    const config = loadConfig({});
    expect(config.provider).toBe(DEFAULT_PROVIDER);
    expect(config.model).toBe(PROVIDER_SPECS['workers-ai'].defaultModel);
  });

  it('seleciona Groq, Grok e Cerebras por configuracao', () => {
    expect(loadConfig({ CHAT_PROVIDER: 'groq' }).provider).toBe('groq');
    expect(loadConfig({ CHAT_PROVIDER: 'xai' }).provider).toBe('xai');
    expect(loadConfig({ CHAT_PROVIDER: 'cerebras' }).provider).toBe('cerebras');
  });

  it('resolve o modelo padrao do provider selecionado', () => {
    expect(loadConfig({ CHAT_PROVIDER: 'groq' }).model).toBe(PROVIDER_SPECS.groq.defaultModel);
    expect(loadConfig({ CHAT_PROVIDER: 'xai' }).model).toBe(PROVIDER_SPECS.xai.defaultModel);
    expect(loadConfig({ CHAT_PROVIDER: 'cerebras' }).model).toBe(
      PROVIDER_SPECS.cerebras.defaultModel,
    );
  });

  it('aceita override de modelo por provider', () => {
    expect(loadConfig({ CHAT_PROVIDER: 'groq', GROQ_MODEL: 'llama-3.1-8b' }).model).toBe(
      'llama-3.1-8b',
    );
    expect(loadConfig({ CHAT_PROVIDER: 'xai', XAI_MODEL: 'grok-4-mini' }).model).toBe(
      'grok-4-mini',
    );
    expect(loadConfig({ CHAT_MODEL: 'custom-model' }).model).toBe('custom-model');
  });

  it('ignora provider desconhecido e cai no padrao', () => {
    const config = loadConfig({ CHAT_PROVIDER: 'openai', CHAT_MODEL: 'custom-model' });
    expect(config.provider).toBe(DEFAULT_PROVIDER);
    expect(config.model).toBe('custom-model');
  });
});
