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
