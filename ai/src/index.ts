import { loadConfig } from './config';
import { createHandler } from './handler';
import { verifyTurnstile } from './turnstile';
import { addTokens, capKey, getUsedTokens, type CapStore } from './daily-cap';
import type { Env } from './env';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const config = loadConfig(env);
    const store: CapStore = {
      get: (key) => env.DAILY_CAP.get(key),
      put: (key, value) => env.DAILY_CAP.put(key, value),
    };
    const handler = createHandler({
      config,
      verifyTurnstile: (token, ip) =>
        verifyTurnstile({ secret: env.TURNSTILE_SECRET, token, ip }),
      checkRate: async (ip) => {
        const result = await env.CHAT_RATE.limit({ key: ip });
        return result.success;
      },
      getUsedTokens: () => getUsedTokens(store, capKey(new Date())),
      addTokens: (tokens) => addTokens(store, capKey(new Date()), tokens),
      runModel: async ({ model, messages, maxTokens }) => {
        const stream = await env.AI.run(model, {
          messages,
          max_tokens: maxTokens,
          stream: true,
        });
        return stream as unknown as ReadableStream<Uint8Array>;
      },
      log: (message) => console.log(message),
    });
    return handler(request);
  },
} satisfies ExportedHandler<Env>;
