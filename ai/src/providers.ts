import type { Ai } from '@cloudflare/workers-types';
import type { ModelMessage } from './chat';

export const PROVIDER_NAMES = ['workers-ai', 'groq', 'xai', 'cerebras'] as const;

export type ProviderName = (typeof PROVIDER_NAMES)[number];

export type ApiKeyEnv = 'GROQ_API_KEY' | 'XAI_API_KEY' | 'CEREBRAS_API_KEY';

export type ModelEnv = 'CHAT_MODEL' | 'GROQ_MODEL' | 'XAI_MODEL' | 'CEREBRAS_MODEL';

export interface ProviderSpec {
  defaultModel: string;
  modelEnv: ModelEnv;
  baseUrl?: string;
  apiKeyEnv?: ApiKeyEnv;
}

export const PROVIDER_SPECS: Record<ProviderName, ProviderSpec> = {
  'workers-ai': {
    defaultModel: '@cf/deepseek-ai/deepseek-v4-flash-0731',
    modelEnv: 'CHAT_MODEL',
  },
  groq: {
    defaultModel: 'llama-3.3-70b-versatile',
    modelEnv: 'GROQ_MODEL',
    baseUrl: 'https://api.groq.com/openai/v1',
    apiKeyEnv: 'GROQ_API_KEY',
  },
  xai: {
    defaultModel: 'grok-4',
    modelEnv: 'XAI_MODEL',
    baseUrl: 'https://api.x.ai/v1',
    apiKeyEnv: 'XAI_API_KEY',
  },
  cerebras: {
    defaultModel: 'llama-3.3-70b',
    modelEnv: 'CEREBRAS_MODEL',
    baseUrl: 'https://api.cerebras.ai/v1',
    apiKeyEnv: 'CEREBRAS_API_KEY',
  },
};

export interface ProviderRunArgs {
  model: string;
  messages: ModelMessage[];
  maxTokens: number;
}

export interface LlmProvider {
  readonly name: ProviderName;
  run(args: ProviderRunArgs): Promise<ReadableStream<Uint8Array>>;
}

export function isProviderName(value: string): value is ProviderName {
  return (PROVIDER_NAMES as readonly string[]).includes(value);
}

export function createWorkersAiProvider(ai: Ai): LlmProvider {
  return {
    name: 'workers-ai',
    async run({ model, messages, maxTokens }) {
      const stream = await ai.run(model, {
        messages,
        max_tokens: maxTokens,
        stream: true,
      });
      return stream as unknown as ReadableStream<Uint8Array>;
    },
  };
}

export interface OpenAiCompatibleOptions {
  name: Exclude<ProviderName, 'workers-ai'>;
  baseUrl: string;
  apiKey: string | undefined;
  fetchImpl?: typeof fetch;
}

export function createOpenAiCompatibleProvider(options: OpenAiCompatibleOptions): LlmProvider {
  const doFetch = options.fetchImpl ?? fetch;
  return {
    name: options.name,
    async run({ model, messages, maxTokens }) {
      const apiKey = options.apiKey;
      if (typeof apiKey !== 'string' || apiKey.trim().length === 0) {
        throw new Error(`provider ${options.name} is not configured`);
      }
      const response = await doFetch(`${options.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model,
          messages,
          max_tokens: maxTokens,
          stream: true,
        }),
      });
      if (!response.ok || response.body === null) {
        throw new Error(`provider ${options.name} responded with status ${response.status}`);
      }
      return response.body;
    },
  };
}

export interface ProviderFactoryEnv {
  AI: Ai;
  GROQ_API_KEY?: string;
  XAI_API_KEY?: string;
  CEREBRAS_API_KEY?: string;
}

export function createProvider(
  env: ProviderFactoryEnv,
  name: ProviderName,
  fetchImpl?: typeof fetch,
): LlmProvider {
  if (name === 'workers-ai') {
    return createWorkersAiProvider(env.AI);
  }
  const spec = PROVIDER_SPECS[name];
  if (spec.baseUrl === undefined || spec.apiKeyEnv === undefined) {
    throw new Error(`provider ${name} is misconfigured`);
  }
  return createOpenAiCompatibleProvider({
    name,
    baseUrl: spec.baseUrl,
    apiKey: env[spec.apiKeyEnv],
    fetchImpl,
  });
}
