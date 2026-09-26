import { loadConfig } from './config';
import { createHandler } from './handler';
import { createProvider } from './providers';
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
      provider: createProvider(env, config.provider),
      checkRate: async (ip) => {
        const result = await env.CHAT_RATE.limit({ key: ip });
        return result.success;
      },
      getUsedTokens: () => getUsedTokens(store, capKey(new Date())),
      addTokens: (tokens) => addTokens(store, capKey(new Date()), tokens),
      log: (message) => console.log(message),
    });
    return handler(request);
  },
} satisfies ExportedHandler<Env>;
