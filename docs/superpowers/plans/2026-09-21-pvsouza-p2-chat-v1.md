# pvsouza.com — P2 Chat v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar o Chat v1: um Worker de IA em `ai/` com streaming SSE (Workers AI), Turnstile + rate limit + teto diario de tokens, e a UI de chat no site estatico em `/chat`.

**Architecture:** O Worker separa logica pura (config, CORS, validacao, parsing SSE, teto) da orquestracao, expondo `createHandler(deps)` com dependencias injetaveis; `index.ts` monta as dependencias reais a partir do `env` (binding `AI`, KV, Rate Limiting, secret). A UI e um client component que consome o endpoint via `fetch` + leitura de `ReadableStream`, com um parser SSE puro e testavel. Toda a decisao e coberta por `vitest` com fakes; o smoke E2E real fica como checklist manual.

**Tech Stack:** TypeScript, Cloudflare Workers (Wrangler 4, `@cloudflare/workers-types`), Workers AI binding (`@cf/deepseek-ai/deepseek-v4-flash-0731`), KV, Rate Limiting binding, Turnstile, `vitest`; Next.js 15 (App Router, `output: export`), React 19, `react-markdown` + `remark-gfm`.

**Spec:** `docs/superpowers/specs/2026-09-21-pvsouza-p2-chat-v1-design.md`

## Global Constraints

- Runtime do Worker: Cloudflare Workers (ES modules). Sem dependencia de Node APIs.
- Site: Next.js 15 estatico (`output: 'export'`); **nenhuma API route** e adicionada ao site.
- TypeScript `strict` em todo o codigo.
- **Sem comentarios no codigo-fonte.**
- Segredos apenas via `wrangler secret` / `.dev.vars` (ignorado). Nunca no repositorio.
- Checks obrigatorios do repo: `npm run build` e `npm run typecheck` (na raiz).
- Testes do Worker: `npm test` dentro de `ai/` (`vitest run`). Teste do parser do site: `npm test` na raiz.
- Identidade Git existente; nenhuma atribuicao de ferramenta de IA em commits.
- Ordem de checagem do Worker: metodo -> CORS/origem -> validacao -> Turnstile -> rate limit -> teto diario -> Workers AI.
- Codigos de erro (spec secao 5): `invalid_request` 400, `origin_not_allowed` 403, `turnstile_failed` 403, `not_found` 404, `rate_limited` 429, `daily_cap_exceeded` 429, `method_not_allowed` 405, `upstream_error` 502.
- Limites: 12 mensagens, 4000 chars/mensagem, 16000 chars totais, `max_tokens` 1024, cap diario 100000 tokens, rate 10 req/min.
- `usage` sempre presente no evento `done` (estimado `~chars/4` quando o upstream nao devolve).

## File Structure

```text
ai/
  package.json
  tsconfig.json
  vitest.config.ts
  wrangler.toml
  .dev.vars.example
  src/
    env.ts              tipos do Env (bindings/vars/secret)
    config.ts           loadConfig(env) + limites
    cors.ts             isAllowedOrigin, corsHeaders
    validation.ts       validateChatRequest
    turnstile.ts        verifyTurnstile
    daily-cap.ts        capKey, getUsedTokens, addTokens
    system-prompt.ts    SYSTEM_PROMPT (persona)
    chat.ts             parseUpstreamFrame, toSseStream
    handler.ts          createHandler(deps)
    index.ts            wiring real (env) + export default
  test/
    health.test.ts
    cors.test.ts
    validation.test.ts
    turnstile.test.ts
    daily-cap.test.ts
    chat.test.ts
    handler.test.ts
components/
  chatStream.ts         parser SSE puro do cliente
  chatStream.test.ts
  Chat.tsx              client component do chat
app/
  chat/page.tsx
styles/
  chat.module.css
app/page.tsx            (modificar: card Chat vira Link)
package.json            (modificar: deps react-markdown/remark-gfm/vitest + script test)
vitest.config.ts        (novo: teste do parser do site)
.gitignore              (modificar: ignorar artefatos de ai/)
```

---

### Task 1: Scaffold do Worker e `/health`

**Files:**
- Create: `ai/package.json`, `ai/tsconfig.json`, `ai/vitest.config.ts`, `ai/wrangler.toml`, `ai/.dev.vars.example`, `ai/src/env.ts`, `ai/src/config.ts`, `ai/src/index.ts`
- Create: `ai/test/health.test.ts`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nada.
- Produces: `Env` (interface), `loadConfig(env): Config`, `Config` (interface com `model`, `dailyTokenCap`, `allowedOrigins`, `maxMessages`, `maxCharsPerMessage`, `maxTotalChars`, `maxTokens`), worker default `{ fetch }`.

- [ ] **Step 1: Criar os arquivos de scaffold**

`ai/package.json`:

```json
{
  "name": "pvsouza-ai",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.0.0",
    "typescript": "^5.6.0",
    "vitest": "^4.1.0",
    "wrangler": "^4.0.0"
  }
}
```

`ai/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "lib": ["ES2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "isolatedModules": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*.ts", "test/**/*.ts", "vitest.config.ts"]
}
```

`ai/vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts'],
  },
});
```

`ai/wrangler.toml`:

```toml
name = "pvsouza-ai"
main = "src/index.ts"
compatibility_date = "2026-09-01"

[ai]
binding = "AI"

[[kv_namespaces]]
binding = "DAILY_CAP"
id = "REPLACE_WITH_KV_NAMESPACE_ID"

[[ratelimits]]
name = "CHAT_RATE"
namespace_id = "1001"

[ratelimits.simple]
limit = 10
period = 60

[vars]
CHAT_MODEL = "@cf/deepseek-ai/deepseek-v4-flash-0731"
DAILY_TOKEN_CAP = "100000"
ALLOWED_ORIGINS = "https://pvsouza.com,https://www.pvsouza.com,http://localhost:3000"
```

`ai/.dev.vars.example`:

```text
TURNSTILE_SECRET=replace-with-turnstile-secret
```

`ai/src/env.ts`:

```ts
import type { Ai, KVNamespace, RateLimit } from '@cloudflare/workers-types';

export interface Env {
  AI: Ai;
  DAILY_CAP: KVNamespace;
  CHAT_RATE: RateLimit;
  CHAT_MODEL: string;
  DAILY_TOKEN_CAP: string;
  ALLOWED_ORIGINS: string;
  TURNSTILE_SECRET: string;
}
```

`ai/src/config.ts`:

```ts
export interface Config {
  model: string;
  dailyTokenCap: number;
  allowedOrigins: string[];
  maxMessages: number;
  maxCharsPerMessage: number;
  maxTotalChars: number;
  maxTokens: number;
}

export const LIMITS = {
  maxMessages: 12,
  maxCharsPerMessage: 4000,
  maxTotalChars: 16000,
  maxTokens: 1024,
} as const;

export const DEFAULT_MODEL = '@cf/deepseek-ai/deepseek-v4-flash-0731';
export const DEFAULT_DAILY_TOKEN_CAP = 100000;
export const DEFAULT_ALLOWED_ORIGINS = [
  'https://pvsouza.com',
  'https://www.pvsouza.com',
  'http://localhost:3000',
];

export function loadConfig(env: {
  CHAT_MODEL?: string;
  DAILY_TOKEN_CAP?: string;
  ALLOWED_ORIGINS?: string;
}): Config {
  const rawOrigins = env.ALLOWED_ORIGINS;
  const origins =
    rawOrigins === undefined || rawOrigins.trim().length === 0
      ? [...DEFAULT_ALLOWED_ORIGINS]
      : rawOrigins
          .split(',')
          .map((origin) => origin.trim())
          .filter((origin) => origin.length > 0);
  const parsedCap = Number.parseInt(env.DAILY_TOKEN_CAP ?? '', 10);
  const dailyTokenCap =
    Number.isFinite(parsedCap) && parsedCap > 0 ? parsedCap : DEFAULT_DAILY_TOKEN_CAP;
  return {
    model: env.CHAT_MODEL ?? DEFAULT_MODEL,
    dailyTokenCap,
    allowedOrigins: origins,
    ...LIMITS,
  };
}
```

`ai/src/index.ts` (temporario; sera completado na Task 8):

```ts
import { loadConfig } from './config';
import type { Env } from './env';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const config = loadConfig(env);
    if (url.pathname === '/health' && request.method === 'GET') {
      return new Response(JSON.stringify({ status: 'ok' }), {
        status: 200,
        headers: { 'content-type': 'application/json; charset=utf-8' },
      });
    }
    if (url.pathname === '/chat') {
      return new Response(JSON.stringify({ code: 'not_found', model: config.model }), {
        status: 501,
        headers: { 'content-type': 'application/json; charset=utf-8' },
      });
    }
    return new Response(JSON.stringify({ code: 'not_found' }), {
      status: 404,
      headers: { 'content-type': 'application/json; charset=utf-8' },
    });
  },
} satisfies ExportedHandler<Env>;
```

Modify `.gitignore` — append:

```gitignore

# ai worker
/ai/node_modules/
/ai/.wrangler/
/ai/.dev.vars
```

- [ ] **Step 2: Instalar dependencias do Worker**

Run (em `ai/`): `npm install`
Expected: cria `ai/node_modules` e `ai/package-lock.json` sem erro.

- [ ] **Step 3: Escrever o teste que falha**

`ai/test/health.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import worker from '../src/index';
import type { Env } from '../src/env';

const env = {
  CHAT_MODEL: 'test-model',
  DAILY_TOKEN_CAP: '1000',
  ALLOWED_ORIGINS: 'https://pvsouza.com',
  TURNSTILE_SECRET: 'secret',
} as unknown as Env;

describe('health', () => {
  it('responde ok em GET /health', async () => {
    const response = await worker.fetch(new Request('https://ai.pvsouza.com/health'), env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: 'ok' });
  });

  it('responde 404 em rota desconhecida', async () => {
    const response = await worker.fetch(new Request('https://ai.pvsouza.com/nope'), env);
    expect(response.status).toBe(404);
  });
});
```

- [ ] **Step 4: Rodar o teste e ver que passa**

Run (em `ai/`): `npm test`
Expected: 2 testes passando.

- [ ] **Step 5: Commit**

```bash
git add ai .gitignore
git commit -m "feat(p2-chat): scaffold do worker de IA e health"
```

---

### Task 2: CORS

**Files:**
- Create: `ai/src/cors.ts`, `ai/test/cors.test.ts`

**Interfaces:**
- Consumes: `Config.allowedOrigins`.
- Produces: `isAllowedOrigin(origin: string | null, allowed: string[]): boolean`, `corsHeaders(origin: string | null, allowed: string[]): Record<string, string>`.

- [ ] **Step 1: Escrever o teste que falha**

`ai/test/cors.test.ts`:

```ts
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
```

- [ ] **Step 2: Rodar e ver que falha**

Run (em `ai/`): `npm test -- cors`
Expected: FAIL (modulo `../src/cors` nao encontrado).

- [ ] **Step 3: Implementar**

`ai/src/cors.ts`:

```ts
export function isAllowedOrigin(origin: string | null, allowed: string[]): boolean {
  return origin !== null && allowed.includes(origin);
}

export function corsHeaders(origin: string | null, allowed: string[]): Record<string, string> {
  const headers: Record<string, string> = {
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'content-type',
    Vary: 'Origin',
  };
  if (origin !== null && allowed.includes(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
  }
  return headers;
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run (em `ai/`): `npm test -- cors`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ai/src/cors.ts ai/test/cors.test.ts
git commit -m "feat(p2-chat): CORS allowlist do worker"
```

---

### Task 3: Validacao do payload

**Files:**
- Create: `ai/src/validation.ts`, `ai/test/validation.test.ts`

**Interfaces:**
- Consumes: `Config` (Task 1).
- Produces: `ChatMessage { role: 'user' | 'assistant'; content: string }`, `ChatRequest { messages: ChatMessage[]; turnstileToken: string }`, `validateChatRequest(body: unknown, config: Config): { ok: true; value: ChatRequest } | { ok: false; error: string }`.

- [ ] **Step 1: Escrever o teste que falha**

`ai/test/validation.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { validateChatRequest } from '../src/validation';
import { loadConfig } from '../src/config';

const config = loadConfig({});

const valid = {
  messages: [{ role: 'user', content: 'ola' }],
  turnstileToken: 'token',
};

describe('validateChatRequest', () => {
  it('aceita payload valido', () => {
    const result = validateChatRequest(valid, config);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.messages).toHaveLength(1);
      expect(result.value.turnstileToken).toBe('token');
    }
  });

  it('rejeita corpo nao-objeto', () => {
    expect(validateChatRequest(null, config).ok).toBe(false);
    expect(validateChatRequest('x', config).ok).toBe(false);
  });

  it('rejeita turnstileToken ausente', () => {
    const result = validateChatRequest({ messages: valid.messages }, config);
    expect(result.ok).toBe(false);
  });

  it('rejeita lista de mensagens vazia', () => {
    expect(validateChatRequest({ ...valid, messages: [] }, config).ok).toBe(false);
  });

  it('rejeita papel invalido', () => {
    const result = validateChatRequest(
      { ...valid, messages: [{ role: 'system', content: 'x' }] },
      config,
    );
    expect(result.ok).toBe(false);
  });

  it('rejeita ultima mensagem que nao e do usuario', () => {
    const result = validateChatRequest(
      {
        ...valid,
        messages: [
          { role: 'user', content: 'a' },
          { role: 'assistant', content: 'b' },
        ],
      },
      config,
    );
    expect(result.ok).toBe(false);
  });

  it('rejeita mais de 12 mensagens', () => {
    const messages = Array.from({ length: 13 }, (_, i) => ({
      role: i % 2 === 0 ? 'user' : 'assistant',
      content: 'x',
    }));
    const result = validateChatRequest({ ...valid, messages }, config);
    expect(result.ok).toBe(false);
  });

  it('rejeita mensagem com mais de 4000 chars', () => {
    const result = validateChatRequest(
      { ...valid, messages: [{ role: 'user', content: 'x'.repeat(4001) }] },
      config,
    );
    expect(result.ok).toBe(false);
  });

  it('rejeita total acima de 16000 chars', () => {
    const result = validateChatRequest(
      {
        ...valid,
        messages: [
          { role: 'user', content: 'x'.repeat(4000) },
          { role: 'assistant', content: 'y'.repeat(4000) },
          { role: 'user', content: 'z'.repeat(4000) },
          { role: 'assistant', content: 'w'.repeat(4000) },
          { role: 'user', content: 'v'.repeat(1) },
        ],
      },
      config,
    );
    expect(result.ok).toBe(false);
  });
});
```

- [ ] **Step 2: Rodar e ver que falha**

Run (em `ai/`): `npm test -- validation`
Expected: FAIL (modulo `../src/validation` nao encontrado).

- [ ] **Step 3: Implementar**

`ai/src/validation.ts`:

```ts
import type { Config } from './config';

export type Role = 'user' | 'assistant';

export interface ChatMessage {
  role: Role;
  content: string;
}

export interface ChatRequest {
  messages: ChatMessage[];
  turnstileToken: string;
}

export type ValidationResult =
  | { ok: true; value: ChatRequest }
  | { ok: false; error: string };

export function validateChatRequest(body: unknown, config: Config): ValidationResult {
  if (typeof body !== 'object' || body === null) {
    return { ok: false, error: 'body must be an object' };
  }
  const record = body as Record<string, unknown>;
  const token = record.turnstileToken;
  if (typeof token !== 'string' || token.trim().length === 0) {
    return { ok: false, error: 'turnstileToken is required' };
  }
  const messages = record.messages;
  if (!Array.isArray(messages) || messages.length === 0) {
    return { ok: false, error: 'messages must be a non-empty array' };
  }
  if (messages.length > config.maxMessages) {
    return { ok: false, error: `messages must have at most ${config.maxMessages} items` };
  }
  const parsed: ChatMessage[] = [];
  let total = 0;
  for (const item of messages) {
    if (typeof item !== 'object' || item === null) {
      return { ok: false, error: 'each message must be an object' };
    }
    const message = item as Record<string, unknown>;
    if (message.role !== 'user' && message.role !== 'assistant') {
      return { ok: false, error: 'role must be user or assistant' };
    }
    if (typeof message.content !== 'string' || message.content.length === 0) {
      return { ok: false, error: 'content must be a non-empty string' };
    }
    if (message.content.length > config.maxCharsPerMessage) {
      return {
        ok: false,
        error: `content must have at most ${config.maxCharsPerMessage} chars`,
      };
    }
    total += message.content.length;
    parsed.push({ role: message.role, content: message.content });
  }
  if (total > config.maxTotalChars) {
    return { ok: false, error: `total content must have at most ${config.maxTotalChars} chars` };
  }
  if (parsed[parsed.length - 1].role !== 'user') {
    return { ok: false, error: 'last message must be from user' };
  }
  return { ok: true, value: { messages: parsed, turnstileToken: token } };
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run (em `ai/`): `npm test -- validation`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ai/src/validation.ts ai/test/validation.test.ts
git commit -m "feat(p2-chat): validacao do payload do chat"
```

---

### Task 4: Turnstile (fail-closed)

**Files:**
- Create: `ai/src/turnstile.ts`, `ai/test/turnstile.test.ts`

**Interfaces:**
- Consumes: nada.
- Produces: `verifyTurnstile(options: { secret: string; token: string; ip: string | null; fetchImpl?: typeof fetch }): Promise<boolean>`.

- [ ] **Step 1: Escrever o teste que falha**

`ai/test/turnstile.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { verifyTurnstile } from '../src/turnstile';

const okFetch = () =>
  vi.fn(
    async (_input: string, _init?: RequestInit) =>
      new Response(JSON.stringify({ success: true }), { status: 200 }),
  );

describe('verifyTurnstile', () => {
  it('aprova quando siteverify retorna success', async () => {
    const fetchImpl = okFetch();
    const result = await verifyTurnstile({ secret: 's', token: 't', ip: '1.2.3.4', fetchImpl });
    expect(result).toBe(true);
    const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
    expect(url).toContain('/siteverify');
    expect((init.body as URLSearchParams).get('remoteip')).toBe('1.2.3.4');
  });

  it('rejeita quando success e false', async () => {
    const fetchImpl = vi.fn(async () =>
      new Response(JSON.stringify({ success: false }), { status: 200 }),
    );
    expect(await verifyTurnstile({ secret: 's', token: 't', ip: null, fetchImpl })).toBe(false);
  });

  it('rejeita sem secret', async () => {
    const fetchImpl = okFetch();
    expect(await verifyTurnstile({ secret: '  ', token: 't', ip: null, fetchImpl })).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('rejeita sem token', async () => {
    const fetchImpl = okFetch();
    expect(await verifyTurnstile({ secret: 's', token: '', ip: null, fetchImpl })).toBe(false);
  });

  it('rejeita fail-closed em erro de rede', async () => {
    const fetchImpl = vi.fn(async () => {
      throw new Error('network');
    });
    expect(await verifyTurnstile({ secret: 's', token: 't', ip: null, fetchImpl })).toBe(false);
  });

  it('rejeita fail-closed em status nao-2xx', async () => {
    const fetchImpl = vi.fn(async () => new Response('nope', { status: 500 }));
    expect(await verifyTurnstile({ secret: 's', token: 't', ip: null, fetchImpl })).toBe(false);
  });
});
```

- [ ] **Step 2: Rodar e ver que falha**

Run (em `ai/`): `npm test -- turnstile`
Expected: FAIL (modulo `../src/turnstile` nao encontrado).

- [ ] **Step 3: Implementar**

`ai/src/turnstile.ts`:

```ts
const SITEVERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';

export interface TurnstileOptions {
  secret: string;
  token: string;
  ip: string | null;
  fetchImpl?: (input: string, init?: RequestInit) => Promise<Response>;
}

export async function verifyTurnstile(options: TurnstileOptions): Promise<boolean> {
  if (options.secret.trim().length === 0 || options.token.trim().length === 0) {
    return false;
  }
  const doFetch = options.fetchImpl ?? fetch;
  const body = new URLSearchParams();
  body.set('secret', options.secret);
  body.set('response', options.token);
  if (options.ip !== null && options.ip.length > 0) {
    body.set('remoteip', options.ip);
  }
  try {
    const response = await doFetch(SITEVERIFY_URL, { method: 'POST', body });
    if (!response.ok) {
      return false;
    }
    const data = (await response.json()) as { success?: boolean };
    return data.success === true;
  } catch {
    return false;
  }
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run (em `ai/`): `npm test -- turnstile`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ai/src/turnstile.ts ai/test/turnstile.test.ts
git commit -m "feat(p2-chat): verificacao fail-closed do Turnstile"
```

---

### Task 5: Teto diario de tokens (KV)

**Files:**
- Create: `ai/src/daily-cap.ts`, `ai/test/daily-cap.test.ts`

**Interfaces:**
- Consumes: nada.
- Produces: `CapStore { get(key): Promise<string | null>; put(key, value): Promise<void> }`, `capKey(now: Date): string`, `getUsedTokens(store: CapStore, key: string): Promise<number>`, `addTokens(store: CapStore, key: string, tokens: number): Promise<void>`.

- [ ] **Step 1: Escrever o teste que falha**

`ai/test/daily-cap.test.ts`:

```ts
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
```

- [ ] **Step 2: Rodar e ver que falha**

Run (em `ai/`): `npm test -- daily-cap`
Expected: FAIL (modulo `../src/daily-cap` nao encontrado).

- [ ] **Step 3: Implementar**

`ai/src/daily-cap.ts`:

```ts
export interface CapStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string): Promise<void>;
}

export function capKey(now: Date): string {
  return `cap:${now.toISOString().slice(0, 10)}`;
}

export async function getUsedTokens(store: CapStore, key: string): Promise<number> {
  const raw = await store.get(key);
  if (raw === null) {
    return 0;
  }
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

export async function addTokens(store: CapStore, key: string, tokens: number): Promise<void> {
  const used = await getUsedTokens(store, key);
  const delta = Number.isFinite(tokens) && tokens > 0 ? Math.floor(tokens) : 0;
  await store.put(key, String(used + delta));
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run (em `ai/`): `npm test -- daily-cap`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ai/src/daily-cap.ts ai/test/daily-cap.test.ts
git commit -m "feat(p2-chat): teto diario de tokens em KV"
```

---

### Task 6: Parsing do upstream e stream SSE

**Files:**
- Create: `ai/src/chat.ts`, `ai/test/chat.test.ts`

**Interfaces:**
- Consumes: nada.
- Produces: `ModelMessage { role: 'system' | 'user' | 'assistant'; content: string }`, `Usage { prompt: number; completion: number }`, `parseUpstreamFrame(line: string): { kind: 'delta'; text: string } | { kind: 'done' } | { kind: 'ignore' }`, `estimateTokens(chars: number): number`, `toSseStream(options: { upstream: ReadableStream<Uint8Array>; promptChars: number; onUsage: (usage: Usage) => void | Promise<void>; onError?: (error: unknown) => void }): ReadableStream<Uint8Array>`.

- [ ] **Step 1: Escrever o teste que falha**

`ai/test/chat.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { estimateTokens, parseUpstreamFrame, toSseStream, type Usage } from '../src/chat';

function upstreamFrom(text: string): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode(text));
      controller.close();
    },
  });
}

async function readAll(stream: ReadableStream<Uint8Array>): Promise<string> {
  const decoder = new TextDecoder();
  const reader = stream.getReader();
  let output = '';
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    output += decoder.decode(value, { stream: true });
  }
  return output;
}

describe('parseUpstreamFrame', () => {
  it('extrai delta de um frame', () => {
    expect(parseUpstreamFrame('data: {"response":"ola"}')).toEqual({ kind: 'delta', text: 'ola' });
  });

  it('reconhece [DONE]', () => {
    expect(parseUpstreamFrame('data: [DONE]')).toEqual({ kind: 'done' });
  });

  it('ignora linhas vazias ou nao-data', () => {
    expect(parseUpstreamFrame('')).toEqual({ kind: 'ignore' });
    expect(parseUpstreamFrame(': keep-alive')).toEqual({ kind: 'ignore' });
    expect(parseUpstreamFrame('data: ')).toEqual({ kind: 'ignore' });
  });

  it('ignora JSON invalido sem lancar', () => {
    expect(parseUpstreamFrame('data: {oops')).toEqual({ kind: 'ignore' });
  });
});

describe('estimateTokens', () => {
  it('estima chars/4 arredondando para cima', () => {
    expect(estimateTokens(0)).toBe(0);
    expect(estimateTokens(1)).toBe(1);
    expect(estimateTokens(4)).toBe(1);
    expect(estimateTokens(5)).toBe(2);
  });
});

describe('toSseStream', () => {
  it('emite tokens, done com usage e chama onUsage', async () => {
    const onUsage = vi.fn<(usage: Usage) => void>();
    const stream = toSseStream({
      upstream: upstreamFrom('data: {"response":"ola"}\ndata: {"response":" mundo"}\ndata: [DONE]\n'),
      promptChars: 8,
      onUsage,
    });
    const output = await readAll(stream);
    expect(output).toContain('event: token\ndata: {"delta":"ola"}');
    expect(output).toContain('event: token\ndata: {"delta":" mundo"}');
    expect(output).toContain('event: done');
    expect(output).toContain('"prompt":2');
    expect(output).toContain('"completion":3');
    expect(onUsage).toHaveBeenCalledWith({ prompt: 2, completion: 3 });
  });

  it('emite erro quando o upstream termina sem [DONE]', async () => {
    const stream = toSseStream({
      upstream: upstreamFrom('data: {"response":"corte"}'),
      promptChars: 4,
      onUsage: () => undefined,
    });
    const output = await readAll(stream);
    expect(output).toContain('event: error');
    expect(output).not.toContain('event: done');
  });
});
```

- [ ] **Step 2: Rodar e ver que falha**

Run (em `ai/`): `npm test -- chat`
Expected: FAIL (modulo `../src/chat` nao encontrado).

- [ ] **Step 3: Implementar**

`ai/src/chat.ts`:

```ts
export interface ModelMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface Usage {
  prompt: number;
  completion: number;
}

export type UpstreamFrame =
  | { kind: 'delta'; text: string }
  | { kind: 'done' }
  | { kind: 'ignore' };

export function parseUpstreamFrame(line: string): UpstreamFrame {
  const trimmed = line.trim();
  if (!trimmed.startsWith('data:')) {
    return { kind: 'ignore' };
  }
  const payload = trimmed.slice(5).trim();
  if (payload.length === 0) {
    return { kind: 'ignore' };
  }
  if (payload === '[DONE]') {
    return { kind: 'done' };
  }
  try {
    const parsed = JSON.parse(payload) as { response?: unknown };
    if (typeof parsed.response === 'string' && parsed.response.length > 0) {
      return { kind: 'delta', text: parsed.response };
    }
    return { kind: 'ignore' };
  } catch {
    return { kind: 'ignore' };
  }
}

export function estimateTokens(chars: number): number {
  if (!Number.isFinite(chars) || chars <= 0) {
    return 0;
  }
  return Math.ceil(chars / 4);
}

export interface ChatStreamOptions {
  upstream: ReadableStream<Uint8Array>;
  promptChars: number;
  onUsage: (usage: Usage) => void | Promise<void>;
  onError?: (error: unknown) => void;
}

export function toSseStream(options: ChatStreamOptions): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const frame = (event: string, data: unknown): Uint8Array =>
    encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);

  return new ReadableStream<Uint8Array>({
    async start(controller) {
      const reader = options.upstream.getReader();
      let buffer = '';
      let completion = '';
      let sawDone = false;
      try {
        for (;;) {
          const { done, value } = await reader.read();
          if (done) {
            break;
          }
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          buffer = lines.pop() ?? '';
          for (const line of lines) {
            const parsed = parseUpstreamFrame(line);
            if (parsed.kind === 'delta') {
              completion += parsed.text;
              controller.enqueue(frame('token', { delta: parsed.text }));
            } else if (parsed.kind === 'done') {
              sawDone = true;
            }
          }
        }
        if (!sawDone) {
          controller.enqueue(frame('error', { code: 'stream_error', message: 'stream truncated' }));
          return;
        }
        const usage: Usage = {
          prompt: estimateTokens(options.promptChars),
          completion: estimateTokens(completion.length),
        };
        controller.enqueue(frame('done', { usage }));
        await options.onUsage(usage);
      } catch (error) {
        controller.enqueue(frame('error', { code: 'stream_error', message: 'stream failed' }));
        if (options.onError) {
          options.onError(error);
        }
      } finally {
        controller.close();
      }
    },
  });
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run (em `ai/`): `npm test -- chat`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ai/src/chat.ts ai/test/chat.test.ts
git commit -m "feat(p2-chat): parsing do upstream e stream SSE"
```

---

### Task 7: System prompt

**Files:**
- Create: `ai/src/system-prompt.ts`, `ai/test/system-prompt.test.ts`

**Interfaces:**
- Consumes: nada.
- Produces: `SYSTEM_PROMPT: string`.

- [ ] **Step 1: Escrever o teste que falha**

`ai/test/system-prompt.test.ts`:

```ts
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
```

- [ ] **Step 2: Rodar e ver que falha**

Run (em `ai/`): `npm test -- system-prompt`
Expected: FAIL (modulo `../src/system-prompt` nao encontrado).

- [ ] **Step 3: Implementar**

`ai/src/system-prompt.ts`:

```ts
export const SYSTEM_PROMPT = [
  'Voce e o assistente do portfolio de Paulo Vitor Souza, um Software Developer com foco em se tornar AI Engineer.',
  'Seu papel e responder perguntas sobre o Paulo: sua experiencia, projetos, stack e interesses, e conversar sobre engenharia de software e IA.',
  'Responda no mesmo idioma da mensagem do usuario.',
  'Seja conciso, direto e honesto: nunca invente fatos, datas, empresas ou projetos que voce nao conhece.',
  'Se o assunto fugir do portfolio ou de engenharia de software e IA, redirecione com educacao para esses temas.',
].join(' ');
```

- [ ] **Step 4: Rodar e ver que passa**

Run (em `ai/`): `npm test -- system-prompt`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ai/src/system-prompt.ts ai/test/system-prompt.test.ts
git commit -m "feat(p2-chat): persona do assistente do portfolio"
```

---

### Task 8: Handler com ordem de checagem e wiring real

**Files:**
- Create: `ai/src/handler.ts`, `ai/test/handler.test.ts`
- Modify: `ai/src/index.ts`

**Interfaces:**
- Consumes: `Config` (Task 1), `corsHeaders`/`isAllowedOrigin` (Task 2), `validateChatRequest`/`ChatMessage` (Task 3), `SYSTEM_PROMPT` (Task 7), `ModelMessage`/`Usage`/`toSseStream` (Task 6).
- Produces: `HandlerDeps { config; verifyTurnstile; checkRate; getUsedTokens; addTokens; runModel; log }`, `createHandler(deps: HandlerDeps): (request: Request) => Promise<Response>`.

- [ ] **Step 1: Escrever o teste que falha**

`ai/test/handler.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { createHandler, type HandlerDeps } from '../src/handler';
import { loadConfig } from '../src/config';
import type { ModelMessage, Usage } from '../src/chat';

const encoder = new TextEncoder();

function upstream(text: string): ReadableStream<Uint8Array> {
  return new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode(text));
      controller.close();
    },
  });
}

function makeDeps(overrides: Partial<HandlerDeps> = {}): HandlerDeps {
  const config = loadConfig({
    CHAT_MODEL: 'test-model',
    DAILY_TOKEN_CAP: '1000',
    ALLOWED_ORIGINS: 'https://pvsouza.com',
  });
  const deps: HandlerDeps = {
    config,
    verifyTurnstile: async () => true,
    checkRate: async () => true,
    getUsedTokens: async () => 0,
    addTokens: async () => undefined,
    runModel: async () => upstream('data: {"response":"ola"}\ndata: [DONE]\n'),
    log: () => undefined,
    ...overrides,
  };
  return deps;
}

const validBody = {
  messages: [{ role: 'user', content: 'oi' }],
  turnstileToken: 'token',
};

function chatRequest(body: unknown, origin = 'https://pvsouza.com'): Request {
  return new Request('https://ai.pvsouza.com/chat', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin },
    body: JSON.stringify(body),
  });
}

describe('createHandler', () => {
  it('responde preflight 204 com headers CORS', async () => {
    const handler = createHandler(makeDeps());
    const response = await handler(
      new Request('https://ai.pvsouza.com/chat', {
        method: 'OPTIONS',
        headers: { origin: 'https://pvsouza.com' },
      }),
    );
    expect(response.status).toBe(204);
    expect(response.headers.get('access-control-allow-origin')).toBe('https://pvsouza.com');
  });

  it('bloqueia origem fora da allowlist', async () => {
    const handler = createHandler(makeDeps());
    const response = await handler(chatRequest(validBody, 'https://evil.example'));
    expect(response.status).toBe(403);
    expect((await response.json()).code).toBe('origin_not_allowed');
  });

  it('rejeita JSON invalido com 400', async () => {
    const handler = createHandler(makeDeps());
    const response = await handler(
      new Request('https://ai.pvsouza.com/chat', {
        method: 'POST',
        headers: { 'content-type': 'application/json', origin: 'https://pvsouza.com' },
        body: '{oops',
      }),
    );
    expect(response.status).toBe(400);
    expect((await response.json()).code).toBe('invalid_request');
  });

  it('rejeita payload invalido com 400', async () => {
    const handler = createHandler(makeDeps());
    const response = await handler(chatRequest({ messages: [] }));
    expect(response.status).toBe(400);
  });

  it('bloqueia Turnstile invalido com 403 e nao chama a IA', async () => {
    const runModel = vi.fn();
    const handler = createHandler(makeDeps({ verifyTurnstile: async () => false, runModel }));
    const response = await handler(chatRequest(validBody));
    expect(response.status).toBe(403);
    expect((await response.json()).code).toBe('turnstile_failed');
    expect(runModel).not.toHaveBeenCalled();
  });

  it('responde 429 com Retry-After quando o rate limita', async () => {
    const handler = createHandler(makeDeps({ checkRate: async () => false }));
    const response = await handler(chatRequest(validBody));
    expect(response.status).toBe(429);
    expect(response.headers.get('retry-after')).toBe('60');
    expect((await response.json()).code).toBe('rate_limited');
  });

  it('responde 429 quando o teto diario foi atingido e nao chama a IA', async () => {
    const runModel = vi.fn();
    const handler = createHandler(makeDeps({ getUsedTokens: async () => 1000, runModel }));
    const response = await handler(chatRequest(validBody));
    expect(response.status).toBe(429);
    expect((await response.json()).code).toBe('daily_cap_exceeded');
    expect(runModel).not.toHaveBeenCalled();
  });

  it('responde 502 quando a IA falha antes do stream', async () => {
    const handler = createHandler(
      makeDeps({
        runModel: async () => {
          throw new Error('upstream down');
        },
      }),
    );
    const response = await handler(chatRequest(validBody));
    expect(response.status).toBe(502);
    expect((await response.json()).code).toBe('upstream_error');
  });

  it('injeta o system prompt como primeira mensagem', async () => {
    const seen: ModelMessage[][] = [];
    const handler = createHandler(
      makeDeps({
        runModel: async ({ messages }) => {
          seen.push(messages);
          return upstream('data: {"response":"ok"}\ndata: [DONE]\n');
        },
      }),
    );
    await handler(chatRequest(validBody));
    expect(seen[0][0].role).toBe('system');
    expect(seen[0][1]).toEqual({ role: 'user', content: 'oi' });
  });

  it('transmite SSE e registra o uso de tokens', async () => {
    const addTokens = vi.fn<(tokens: number) => Promise<void>>(async () => undefined);
    const handler = createHandler(makeDeps({ addTokens }));
    const response = await handler(chatRequest(validBody));
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('text/event-stream');
    const text = await response.text();
    expect(text).toContain('event: token');
    expect(text).toContain('event: done');
    expect(addTokens).toHaveBeenCalledTimes(1);
  });

  it('responde 405 para metodo diferente de POST', async () => {
    const handler = createHandler(makeDeps());
    const response = await handler(
      new Request('https://ai.pvsouza.com/chat', {
        method: 'GET',
        headers: { origin: 'https://pvsouza.com' },
      }),
    );
    expect(response.status).toBe(405);
  });

  it('responde 404 em rota desconhecida', async () => {
    const handler = createHandler(makeDeps());
    const response = await handler(
      new Request('https://ai.pvsouza.com/nope', {
        method: 'GET',
        headers: { origin: 'https://pvsouza.com' },
      }),
    );
    expect(response.status).toBe(404);
  });
});
```

- [ ] **Step 2: Rodar e ver que falha**

Run (em `ai/`): `npm test -- handler`
Expected: FAIL (modulo `../src/handler` nao encontrado).

- [ ] **Step 3: Implementar**

`ai/src/handler.ts`:

```ts
import { corsHeaders, isAllowedOrigin } from './cors';
import { validateChatRequest, type ChatMessage } from './validation';
import { SYSTEM_PROMPT } from './system-prompt';
import { toSseStream, type ModelMessage, type Usage } from './chat';
import type { Config } from './config';

export interface HandlerDeps {
  config: Config;
  verifyTurnstile: (token: string, ip: string | null) => Promise<boolean>;
  checkRate: (ip: string) => Promise<boolean>;
  getUsedTokens: () => Promise<number>;
  addTokens: (tokens: number) => Promise<void>;
  runModel: (args: {
    model: string;
    messages: ModelMessage[];
    maxTokens: number;
  }) => Promise<ReadableStream<Uint8Array>>;
  log: (message: string) => void;
}

function jsonResponse(
  status: number,
  body: unknown,
  headers: Record<string, string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}

export function createHandler(deps: HandlerDeps): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    const url = new URL(request.url);
    const origin = request.headers.get('origin');
    const cors = corsHeaders(origin, deps.config.allowedOrigins);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }

    if (url.pathname === '/health') {
      if (request.method !== 'GET') {
        return jsonResponse(405, { code: 'method_not_allowed' }, cors);
      }
      return jsonResponse(200, { status: 'ok' }, cors);
    }

    if (url.pathname !== '/chat') {
      return jsonResponse(404, { code: 'not_found' }, cors);
    }

    if (request.method !== 'POST') {
      return jsonResponse(405, { code: 'method_not_allowed' }, cors);
    }

    if (!isAllowedOrigin(origin, deps.config.allowedOrigins)) {
      return jsonResponse(403, { code: 'origin_not_allowed' }, cors);
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return jsonResponse(400, { code: 'invalid_request', message: 'invalid JSON body' }, cors);
    }

    const validation = validateChatRequest(body, deps.config);
    if (!validation.ok) {
      return jsonResponse(400, { code: 'invalid_request', message: validation.error }, cors);
    }

    const ip = request.headers.get('cf-connecting-ip');
    const turnstileOk = await deps.verifyTurnstile(validation.value.turnstileToken, ip);
    if (!turnstileOk) {
      return jsonResponse(403, { code: 'turnstile_failed' }, cors);
    }

    const withinRate = await deps.checkRate(ip ?? 'unknown');
    if (!withinRate) {
      return new Response(JSON.stringify({ code: 'rate_limited' }), {
        status: 429,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'retry-after': '60',
          ...cors,
        },
      });
    }

    const used = await deps.getUsedTokens();
    if (used >= deps.config.dailyTokenCap) {
      return jsonResponse(429, { code: 'daily_cap_exceeded' }, cors);
    }

    const messages: ModelMessage[] = [
      { role: 'system', content: SYSTEM_PROMPT },
      ...validation.value.messages.map((message: ChatMessage): ModelMessage => ({
        role: message.role,
        content: message.content,
      })),
    ];
    const promptChars = messages.reduce((total, message) => total + message.content.length, 0);

    let upstream: ReadableStream<Uint8Array>;
    try {
      upstream = await deps.runModel({
        model: deps.config.model,
        messages,
        maxTokens: deps.config.maxTokens,
      });
    } catch (error) {
      deps.log(`upstream_error: ${String(error)}`);
      return jsonResponse(502, { code: 'upstream_error' }, cors);
    }

    const stream = toSseStream({
      upstream,
      promptChars,
      onUsage: (usage: Usage) => deps.addTokens(usage.prompt + usage.completion),
    });

    return new Response(stream, {
      status: 200,
      headers: {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache',
        connection: 'keep-alive',
        ...cors,
      },
    });
  };
}
```

Modify `ai/src/index.ts` (substituir o conteudo inteiro):

```ts
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
```

- [ ] **Step 4: Rodar toda a suite do Worker**

Run (em `ai/`): `npm test`
Expected: PASS (health + cors + validation + turnstile + daily-cap + chat + system-prompt + handler).

- [ ] **Step 5: Typecheck do Worker**

Run (em `ai/`): `npm run typecheck`
Expected: sem erros.

- [ ] **Step 6: Commit**

```bash
git add ai/src/handler.ts ai/src/index.ts ai/test/handler.test.ts
git commit -m "feat(p2-chat): handler com ordem de checagem e wiring real"
```

---

### Task 9: Parser SSE do cliente (site)

**Files:**
- Create: `components/chatStream.ts`, `components/chatStream.test.ts`, `vitest.config.ts`
- Modify: `package.json` (devDependency `vitest`, script `test`)

**Interfaces:**
- Consumes: nada.
- Produces: `StreamEvent { event: string; data: string }`, `parseSseBuffer(buffer: string): { events: StreamEvent[]; rest: string }`.

- [ ] **Step 1: Adicionar vitest e o script de teste**

Modify `package.json`: adicionar `"vitest": "^4.1.0"` em `devDependencies` e `"test": "vitest run"` em `scripts`:

```json
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "format": "prettier --write .",
    "deploy": "wrangler pages deploy out --project-name pvsouza --branch main --commit-dirty=true"
  },
```

```json
  "devDependencies": {
    "@types/node": "^22.0.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@types/three": "^0.180.0",
    "prettier": "^3.0.0",
    "typescript": "^5.6.0",
    "vitest": "^4.1.0",
    "wrangler": "^4.0.0"
  }
```

`vitest.config.ts` (raiz):

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['components/**/*.test.ts'],
  },
});
```

Run (raiz): `npm install`
Expected: instala `vitest` sem erro.

- [ ] **Step 2: Escrever o teste que falha**

`components/chatStream.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { parseSseBuffer } from './chatStream';

describe('parseSseBuffer', () => {
  it('extrai eventos completos e devolve o resto', () => {
    const { events, rest } = parseSseBuffer(
      'event: token\ndata: {"delta":"ola"}\n\nevent: token\ndata: {"delta":"x"',
    );
    expect(events).toEqual([{ event: 'token', data: '{"delta":"ola"}' }]);
    expect(rest).toBe('event: token\ndata: {"delta":"x"');
  });

  it('assume evento message quando nao ha linha event', () => {
    const { events } = parseSseBuffer('data: {"a":1}\n\n');
    expect(events).toEqual([{ event: 'message', data: '{"a":1}' }]);
  });

  it('junta multiplas linhas data', () => {
    const { events } = parseSseBuffer('event: x\ndata: a\ndata: b\n\n');
    expect(events).toEqual([{ event: 'x', data: 'a\nb' }]);
  });

  it('normaliza CRLF', () => {
    const { events, rest } = parseSseBuffer('event: token\r\ndata: {"delta":"a"}\r\n\r\n');
    expect(events).toEqual([{ event: 'token', data: '{"delta":"a"}' }]);
    expect(rest).toBe('');
  });

  it('nao emite evento sem data', () => {
    const { events } = parseSseBuffer('event: token\n\n');
    expect(events).toEqual([]);
  });
});
```

- [ ] **Step 3: Rodar e ver que falha**

Run (raiz): `npm test`
Expected: FAIL (modulo `./chatStream` nao encontrado).

- [ ] **Step 4: Implementar**

`components/chatStream.ts`:

```ts
export interface StreamEvent {
  event: string;
  data: string;
}

export function parseSseBuffer(buffer: string): { events: StreamEvent[]; rest: string } {
  const normalized = buffer.replace(/\r\n/g, '\n');
  const parts = normalized.split('\n\n');
  const rest = parts.pop() ?? '';
  const events: StreamEvent[] = [];
  for (const part of parts) {
    let event = 'message';
    const dataLines: string[] = [];
    for (const line of part.split('\n')) {
      if (line.startsWith('event:')) {
        event = line.slice(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.push(line.slice(5).trim());
      }
    }
    if (dataLines.length > 0) {
      events.push({ event, data: dataLines.join('\n') });
    }
  }
  return { events, rest };
}
```

- [ ] **Step 5: Rodar e ver que passa**

Run (raiz): `npm test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json vitest.config.ts components/chatStream.ts components/chatStream.test.ts
git commit -m "feat(p2-chat): parser SSE do cliente com teste"
```

---

### Task 10: UI do chat, pagina e link na home

**Files:**
- Create: `app/chat/page.tsx`, `components/Chat.tsx`, `styles/chat.module.css`
- Modify: `app/page.tsx` (card Chat vira `Link`)

**Interfaces:**
- Consumes: `parseSseBuffer` (Task 9).
- Produces: rota estatica `/chat` com o componente de chat.

- [ ] **Step 1: Adicionar as dependencias de Markdown**

Modify `package.json` `dependencies`:

```json
  "dependencies": {
    "@react-three/drei": "^10.0.0",
    "@react-three/fiber": "^9.0.0",
    "next": "^15.5.0",
    "react": "19.2.0",
    "react-dom": "19.2.0",
    "react-icons": "^5.0.0",
    "react-markdown": "^10.1.0",
    "remark-gfm": "^4.0.1",
    "three": "^0.180.0"
  },
```

Run (raiz): `npm install`
Expected: instala `react-markdown` e `remark-gfm`.

- [ ] **Step 2: Implementar o componente**

`components/Chat.tsx`:

```tsx
'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Script from 'next/script';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { parseSseBuffer } from '@/components/chatStream';
import styles from '@/styles/chat.module.css';

interface Message {
  role: 'user' | 'assistant';
  content: string;
}

declare global {
  interface Window {
    turnstile?: {
      render: (
        container: HTMLElement,
        options: {
          sitekey: string;
          callback: (token: string) => void;
          'expired-callback'?: () => void;
        },
      ) => string;
      reset: (widgetId?: string) => void;
    };
  }
}

const API_URL = process.env.NEXT_PUBLIC_CHAT_API_URL ?? '';
const SITE_KEY = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY ?? '';
const SUGGESTIONS = [
  'Quem e o Paulo?',
  'Quais projetos ele ja fez?',
  'Qual stack ele domina?',
];

export default function Chat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState('');
  const [status, setStatus] = useState<'idle' | 'streaming' | 'error' | 'capped'>('idle');
  const [error, setError] = useState<string | null>(null);
  const tokenRef = useRef<string>('');
  const widgetRef = useRef<string | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const bottomRef = useRef<HTMLDivElement | null>(null);

  const renderWidget = useCallback(() => {
    if (!containerRef.current || !window.turnstile || SITE_KEY.length === 0) {
      return;
    }
    widgetRef.current = window.turnstile.render(containerRef.current, {
      sitekey: SITE_KEY,
      callback: (token) => {
        tokenRef.current = token;
      },
      'expired-callback': () => {
        tokenRef.current = '';
      },
    });
  }, []);

  useEffect(() => {
    if (window.turnstile) {
      renderWidget();
    }
  }, [renderWidget]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  async function send(text: string): Promise<void> {
    const trimmed = text.trim();
    if (trimmed.length === 0 || status === 'streaming') {
      return;
    }
    setError(null);
    setStatus('streaming');
    const history: Message[] = [...messages, { role: 'user', content: trimmed }];
    setMessages([...history, { role: 'assistant', content: '' }]);
    setInput('');
    try {
      const response = await fetch(`${API_URL}/chat`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ messages: history.slice(-12), turnstileToken: tokenRef.current }),
      });
      if (!response.ok) {
        const payload = (await response.json().catch(() => ({}))) as { code?: string };
        setStatus(payload.code === 'daily_cap_exceeded' ? 'capped' : 'error');
        setError(payload.code ?? `HTTP ${response.status}`);
        setMessages(history);
        return;
      }
      if (!response.body) {
        throw new Error('missing body');
      }
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let assistant = '';
      for (;;) {
        const { done, value } = await reader.read();
        if (done) {
          break;
        }
        buffer += decoder.decode(value, { stream: true });
        const parsed = parseSseBuffer(buffer);
        buffer = parsed.rest;
        for (const streamEvent of parsed.events) {
          if (streamEvent.event === 'token') {
            const data = JSON.parse(streamEvent.data) as { delta: string };
            assistant += data.delta;
            setMessages([...history, { role: 'assistant', content: assistant }]);
          } else if (streamEvent.event === 'error') {
            setStatus('error');
            setError('stream interrompido');
          }
        }
      }
      setStatus((current) => (current === 'streaming' ? 'idle' : current));
    } catch {
      setStatus('error');
      setError('falha de rede');
    } finally {
      tokenRef.current = '';
      if (widgetRef.current && window.turnstile) {
        window.turnstile.reset(widgetRef.current);
      }
    }
  }

  return (
    <div className={styles.chat}>
      <div className={styles.messages} aria-live="polite">
        {messages.length === 0 && (
          <div className={styles.suggestions}>
            {SUGGESTIONS.map((suggestion) => (
              <button
                key={suggestion}
                type="button"
                className={styles.suggestion}
                onClick={() => void send(suggestion)}
              >
                {suggestion}
              </button>
            ))}
          </div>
        )}
        {messages.map((message, index) => (
          <div
            key={index}
            className={message.role === 'user' ? styles.user : styles.assistant}
          >
            {message.role === 'assistant' ? (
              <ReactMarkdown remarkPlugins={[remarkGfm]}>
                {message.content.length > 0 ? message.content : '...'}
              </ReactMarkdown>
            ) : (
              <p>{message.content}</p>
            )}
          </div>
        ))}
        <div ref={bottomRef} />
      </div>
      {error && (
        <p className={styles.error} role="alert">
          {error}
        </p>
      )}
      <form
        className={styles.form}
        onSubmit={(event) => {
          event.preventDefault();
          void send(input);
        }}
      >
        <label className={styles.label} htmlFor="chat-input">
          Mensagem
        </label>
        <input
          id="chat-input"
          className={styles.input}
          value={input}
          onChange={(event) => setInput(event.target.value)}
          placeholder="Pergunte sobre o Paulo..."
          disabled={status === 'streaming'}
        />
        <button
          type="submit"
          className={styles.send}
          disabled={status === 'streaming' || input.trim().length === 0}
        >
          Enviar
        </button>
      </form>
      <div ref={containerRef} className={styles.turnstile} />
      <Script
        src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
        strategy="afterInteractive"
        onLoad={renderWidget}
      />
    </div>
  );
}
```

`styles/chat.module.css`:

```css
.chat {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  max-width: 720px;
  margin: 0 auto;
  padding: 1rem;
}

.messages {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  min-height: 320px;
}

.suggestions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.suggestion {
  border: 1px solid #8884;
  border-radius: 999px;
  background: transparent;
  padding: 0.5rem 0.9rem;
  cursor: pointer;
  font: inherit;
}

.user,
.assistant {
  border-radius: 12px;
  padding: 0.6rem 0.9rem;
  line-height: 1.5;
  overflow-wrap: anywhere;
}

.user {
  align-self: flex-end;
  background: #2b6cb0;
  color: #fff;
}

.assistant {
  align-self: flex-start;
  background: #8881;
}

.form {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 0.5rem;
}

.label {
  grid-column: 1 / -1;
  font-size: 0.8rem;
}

.input {
  padding: 0.6rem;
  border: 1px solid #8884;
  border-radius: 8px;
  font: inherit;
}

.send {
  padding: 0.6rem 1.1rem;
  border: 0;
  border-radius: 8px;
  background: #2b6cb0;
  color: #fff;
  font: inherit;
  cursor: pointer;
}

.send:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.error {
  color: #c53030;
}

.turnstile {
  min-height: 1px;
}
```

`app/chat/page.tsx`:

```tsx
import type { Metadata } from 'next';
import PageShell from '@/components/PageShell';
import Chat from '@/components/Chat';

export const metadata: Metadata = {
  title: 'Chat | PVS DEV',
  description: 'Converse com o assistente de IA do portfolio de Paulo Vitor Souza.',
};

export default function ChatPage() {
  return (
    <PageShell>
      <h1>Chat</h1>
      <Chat />
    </PageShell>
  );
}
```

Modify `app/page.tsx`: trocar o bloco do card "Chat" (o `<div className={styles.card}>` com `-- em breve --`) por:

```tsx
          <Link href="/chat" className={styles.card}>
            <h3>Chat &rarr;</h3>
            <p>Converse com meu assistente de IA.</p>
          </Link>
```

- [ ] **Step 3: Rodar typecheck e build**

Run (raiz): `npm run typecheck`
Expected: sem erros.

Run (raiz): `npm run build`
Expected: build estatico conclui e gera `out/chat/index.html`.

- [ ] **Step 4: Rodar os testes do site**

Run (raiz): `npm test`
Expected: PASS (parser SSE).

- [ ] **Step 5: Commit**

```bash
git add app/chat/page.tsx components/Chat.tsx styles/chat.module.css app/page.tsx package.json package-lock.json
git commit -m "feat(p2-chat): UI do chat e link na home"
```

---

### Task 11: Verificacao final

**Files:**
- Nenhum arquivo novo; apenas verificacao.

- [ ] **Step 1: Suite do Worker**

Run (em `ai/`): `npm test`
Expected: PASS, 0 falhas.

- [ ] **Step 2: Typecheck do Worker**

Run (em `ai/`): `npm run typecheck`
Expected: sem erros.

- [ ] **Step 3: Testes do site**

Run (raiz): `npm test`
Expected: PASS.

- [ ] **Step 4: Checks obrigatorios do repo**

Run (raiz): `npm run typecheck`
Expected: sem erros.

Run (raiz): `npm run build`
Expected: build estatico conclui.

- [ ] **Step 5: Confirmar que o site segue sem API routes**

Run (raiz): `git status --short`
Expected: nenhum arquivo em `app/api` ou `pages/api`; `out/` ignorado.

---

## Definicao de pronto

- `npm test` em `ai/` e na raiz com `Failed: 0`.
- `npm run typecheck` (raiz e `ai/`) e `npm run build` (raiz) passam.
- `GET /health` responde `200 {"status":"ok"}` nos testes.
- Ordem de checagem, fail-closed do Turnstile, rate limit e teto diario cobertos por teste.
- Nenhum segredo no repositorio; nenhuma API route adicionada ao site.

## Verificacao manual adiada (smoke E2E real)

Requer os passos humanos de infra abaixo. Executar antes de declarar o pacote
pronto para uso:

1. Criar o namespace KV `DAILY_CAP` e preencher o `id` no `ai/wrangler.toml`.
2. Criar o widget Turnstile (site key + secret).
3. `npx wrangler secret put TURNSTILE_SECRET` (dentro de `ai/`).
4. `npx wrangler deploy` (dentro de `ai/`) e associar o custom domain `ai.pvsouza.com`.
5. Definir `NEXT_PUBLIC_CHAT_API_URL=https://ai.pvsouza.com` e
   `NEXT_PUBLIC_TURNSTILE_SITE_KEY=<site key>` (ex.: em `.env.local`) e rodar `npm run deploy`.
6. Em `https://pvsouza.com/chat`: enviar uma mensagem, confirmar streaming e Markdown;
   confirmar `403` sem token valido e `429` ao estourar rate/cap; conferir
   `GET https://ai.pvsouza.com/health`.

## Fora do escopo deste plano

- Deploy real e criacao de infra (passos humanos).
- Multi-provider de LLM (issue #2).
- AI Gateway, persistencia de sessao e cache (v2).
- RAG (P3) e artefatos HTML/SVG (P4).
