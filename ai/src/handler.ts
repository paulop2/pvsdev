import { corsHeaders, isAllowedOrigin } from './cors';
import { validateChatRequest, type ChatMessage } from './validation';
import { SYSTEM_PROMPT } from './system-prompt';
import { toTextStream, type ModelMessage, type Usage } from './chat';
import type { Config } from './config';
import type { LlmProvider } from './providers';

export interface HandlerDeps {
  config: Config;
  provider: LlmProvider;
  checkRate: (ip: string) => Promise<boolean>;
  getUsedTokens: () => Promise<number>;
  addTokens: (tokens: number) => Promise<void>;
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

    if (url.pathname === '/' || url.pathname === '') {
      if (request.method !== 'GET') {
        return jsonResponse(405, { code: 'method_not_allowed' }, cors);
      }
      return jsonResponse(
        200,
        { service: 'pvsouza-ai', endpoints: ['POST /chat', 'GET /health'] },
        cors,
      );
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
      upstream = await deps.provider.run({
        model: deps.config.model,
        messages,
        maxTokens: deps.config.maxTokens,
      });
    } catch (error) {
      deps.log(`upstream_error: ${String(error)}`);
      return jsonResponse(502, { code: 'upstream_error' }, cors);
    }

    const stream = toTextStream({
      upstream,
      promptChars,
      onUsage: (usage: Usage) => deps.addTokens(usage.prompt + usage.completion),
    });

    return new Response(stream, {
      status: 200,
      headers: {
        'content-type': 'text/plain; charset=utf-8',
        'cache-control': 'no-cache',
        ...cors,
      },
    });
  };
}
