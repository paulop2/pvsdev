# pvsouza.com — P2: Chat v1 (Worker de IA)

**Data:** 2026-09-21
**Status:** design aprovado; implementação não iniciada
**Repo:** `paulop2/pvsdev` (`C:\Users\PVS\projetos\pvsdev`)
**Spec-pai:** `docs/superpowers/specs/2026-09-17-pvsouza-p1-deploy-design.md` (roadmap P0–P5)

## Estado da execução

- **P0 — Processo:** concluído.
- **P1 — Deploy/plataforma:** concluído (`pvsouza.com` no Cloudflare Pages, Next 15 estático).
- **P2 — Chat v1:** design aprovado nesta spec; implementação pendente.

## 1. Contexto

O P1 entregou o site estático (`output: 'export'`) no Cloudflare Pages. O card
"Chat" da home existe como placeholder (`-- em breve --`). Esta spec detalha o
**P2 — Chat v1**: um chat LLM público com streaming, servido por um Worker de IA
separado, sem login e sem persistência de histórico.

A decisão de topologia do P1 permanece: o site é estático e **não** tem API
routes; todo acesso a IA vive num Worker dedicado em `ai/`.

## 2. Objetivos e não-objetivos

**Objetivos:**

1. Chat público com streaming token a token, renderizando Markdown progressivo.
2. Worker de IA em `ai/` (TypeScript), deploy independente, exposto em
   `ai.pvsouza.com`.
3. Persona de **assistente do portfólio**: responde sobre o Paulo, projetos,
   stack e experiência; conversa sobre engenharia de software/IA; redireciona o
   que foge do tema. É a base natural do RAG (P3).
4. Proteção sem login: Turnstile + rate limit por IP + teto diário de tokens.
5. Chaves apenas no servidor; nada de segredo no repositório.

**Não-objetivos (agora):**

- Persistência de histórico de chat ou sessão no servidor.
- Cache de respostas.
- Multi-provider de LLM (fica como follow-up; issue #2).
- Artefatos HTML/SVG (P4) e RAG (P3).
- AI Gateway / observabilidade avançada (v2).

## 3. Decisões aprovadas

| Tema | Decisão |
|---|---|
| Abordagem do Worker | Worker TS mínimo com handler `fetch` e primitivas nativas (sem Hono/zod). |
| Provedor de LLM | Cloudflare Workers AI (binding `AI`, sem chave externa). |
| Modelo padrão | `@cf/deepseek-ai/deepseek-v4-flash-0731` (configurável por var). |
| Endpoint | Subdomínio dedicado `ai.pvsouza.com` (Worker custom domain). |
| Proteção | Turnstile + Rate Limiting binding (por IP) + teto diário em KV. |
| Persona | Assistente do portfólio (system prompt no Worker). |
| Histórico | Só no cliente; reenviado a cada turno, limitado. |
| Render Markdown | `react-markdown` + `remark-gfm` (sem HTML cru). |
| Testes do Worker | `vitest` + `@cloudflare/vitest-pool-workers`, adapters falsos. |
| Gateway | AI Gateway fica para o v2. |

## 4. Arquitetura e topologia

Dois deploys independentes, um contrato:

```
browser (pvsouza.com/chat)
   |  POST https://ai.pvsouza.com/chat   (SSE)
   v
Worker: Turnstile -> rate limit por IP -> teto diario de tokens (KV)
   |
   v  Workers AI binding (@cf/deepseek-ai/deepseek-v4-flash-0731)
stream SSE token a token --> browser renderiza Markdown progressivo
```

- **Site:** Next 15 estático no Pages em `pvsouza.com`. Ganha a rota `/chat` e o
  card da home passa a linkar para ela. Nenhuma API route é adicionada.
- **Worker:** `ai/`, deploy próprio via Wrangler, exposto em `ai.pvsouza.com`.
- **Sem sessão no servidor:** as mensagens vivem no estado do cliente e são
  reenviadas (limitadas às N últimas) a cada turno. O Worker só mantém o
  contador diário de tokens.

**Configuração do Worker:**

- Bindings: `AI` (Workers AI), `KV` (namespace `DAILY_CAP`), Rate Limiting
  (`CHAT_RATE`).
- Vars: `CHAT_MODEL` (`@cf/deepseek-ai/deepseek-v4-flash-0731`),
  `DAILY_TOKEN_CAP` (`100000`), `ALLOWED_ORIGINS`.
- Secrets (nunca no repo): `TURNSTILE_SECRET`.
- Site: `NEXT_PUBLIC_TURNSTILE_SITE_KEY`, `NEXT_PUBLIC_CHAT_API_URL` no build.

## 5. Contrato da API

### `POST /chat`

Request (`application/json`):

```json
{
  "messages": [
    { "role": "user", "content": "..." },
    { "role": "assistant", "content": "..." }
  ],
  "turnstileToken": "..."
}
```

Validação (violação -> `400 invalid_request`):

- `messages` não-vazio; último item é `user`.
- `role` em `user|assistant`.
- No máximo **12 mensagens** (6 turnos).
- No máximo **4000 caracteres** por mensagem e **16000** no total.
- `turnstileToken` string não-vazia.

O Worker injeta o system prompt; o cliente nunca o envia.

Resposta de sucesso: `200` + `text/event-stream`:

```
event: token
data: {"delta":"Ola"}

event: token
data: {"delta":", mundo"}

event: done
data: {"model":"@cf/deepseek-ai/deepseek-v4-flash-0731","usage":{"prompt":123,"completion":45}}
```

`usage` está sempre presente no `done`; quando o upstream não devolve, o Worker
estima `~chars/4`. A resposta é limitada a `max_tokens: 1024`.

Erros **antes** do stream (JSON, com cabeçalhos CORS):

| Status | code | Quando |
|---|---|---|
| 400 | `invalid_request` | payload malformado ou fora dos limites |
| 403 | `turnstile_failed` | verificação do Turnstile falhou (fail-closed) |
| 429 | `rate_limited` | excedeu o rate limit por IP (`Retry-After`) |
| 429 | `daily_cap_exceeded` | teto diário de tokens atingido |
| 405 | `method_not_allowed` | método diferente de POST/OPTIONS |
| 502 | `upstream_error` | falha do Workers AI antes do primeiro token |

Erros **durante** o stream: `event: error` com `{code,message}` e fim do stream.
O cliente mantém o texto já recebido e mostra o aviso.

### `GET /health`

`200 {"status":"ok"}` — usado no smoke.

### CORS

`Access-Control-Allow-Origin` ecoado apenas se o `Origin` estiver em
`ALLOWED_ORIGINS` (`https://pvsouza.com`, `https://www.pvsouza.com`,
`http://localhost:3000`). `OPTIONS` responde `204` com
`Allow-Methods: POST, OPTIONS` e `Allow-Headers: content-type`.

## 6. Proteção e limites

Ordem de checagem: método -> CORS -> validação -> Turnstile -> rate limit ->
teto diário -> Workers AI.

- **Turnstile:** widget em modo **managed**; token de uso único, resetado no
  cliente após cada envio. O
  Worker chama `siteverify` com `secret` + `token` + IP. **Fail-closed**:
  qualquer falha, expiração ou erro de rede -> `403 turnstile_failed`. Sem
  `TURNSTILE_SECRET` configurado, o Worker falha no startup em produção.
- **Rate limit:** binding nativo do Cloudflare, chave = `CF-Connecting-IP`,
  **10 req/min** (config no `wrangler.toml`). Excedeu ->
  `429 rate_limited` + `Retry-After`.
- **Teto diário:** KV, chave `cap:YYYY-MM-DD` (UTC), contador de tokens somado
  ao fim de cada resposta. Ultrapassou `DAILY_TOKEN_CAP` ->
  `429 daily_cap_exceeded`. Consistência eventual do KV é aceitável no v1
  (limite documentado); v2 pode migrar para Durable Object.
- **Contagem de tokens:** usa `usage` do Workers AI quando disponível; senão
  estima `~chars/4`. Serve só para o teto, não é cobrança.
- **Privacidade:** logs só de metadados (status, tokens, latência, IP
  truncado). Nunca prompt/resposta.

## 7. Worker — estrutura e comportamento

```
ai/
  wrangler.toml
  package.json
  tsconfig.json
  src/
    index.ts          roteador (POST /chat, GET /health, OPTIONS)
    config.ts         parse de env + limites
    cors.ts
    validation.ts
    turnstile.ts
    daily-cap.ts
    system-prompt.ts  perfil do Paulo (constante no v1; vira RAG no P3)
    chat.ts           Workers AI + SSE
  test/
    *.test.ts
```

- `index.ts` monta a ordem de checagem e delega; não contém regra de negócio.
- `chat.ts` chama o binding `AI` com `stream: true` e traduz os chunks para o
  framing SSE (`token` / `done` / `error`).
- `system-prompt.ts` é a única fonte da persona no v1 e será substituída pelo
  contexto do RAG no P3.
- Sem comentários no código-fonte.

## 8. UI de chat

- `app/chat/page.tsx` (server): metadata e shell.
- `components/Chat.tsx` (client): lista de mensagens, input, envio, leitura do
  stream SSE (`fetch` + `response.body.getReader()`), render Markdown
  progressivo, estados `idle | streaming | error | capped`, botão "limpar" e
  prompts sugeridos iniciais.
- `styles/chat.module.css` para o layout.
- Turnstile carregado via `next/script`; o token é resetado após cada envio.
- Card "Chat" da home vira `<Link href="/chat">`.
- Acessibilidade: input rotulado, `aria-live` na região de resposta, foco
  preservado, contraste no tema existente.

## 9. Configuração e segredos

- **Worker:** `wrangler.toml` com `[[kv_namespaces]]`, `[[ratelimits]]` e
  `[vars]`; `TURNSTILE_SECRET` via `wrangler secret put` (nunca no repo).
- **Site:** `NEXT_PUBLIC_TURNSTILE_SITE_KEY` e `NEXT_PUBLIC_CHAT_API_URL`
  injetados no build (são públicos por natureza).
- `.dev.vars` (local) fica no `.gitignore`; nenhum segredo é commitado.

## 10. Testes e verificação

**Worker (`vitest` + `@cloudflare/vitest-pool-workers`), com AI/Turnstile/KV/rate
falsos:**

- validação de payload (limites de mensagens/chars, papel do último item);
- CORS (origem permitida, negada, preflight);
- Turnstile fail-closed e token inválido;
- rate limit e teto diário (incluindo `Retry-After` e `daily_cap_exceeded`);
- ordem de checagem (não chama a IA quando uma checagem anterior falha);
- framing SSE (`token`, `done`, `error`) e erro de upstream antes do 1º token;
- `GET /health`.

**UI/site:** `npm run typecheck` e `npm run build` (obrigatórios pelo
`AGENTS.md`) e smoke manual no `/chat`.

**Verificação E2E (manual):** após o deploy, enviar uma mensagem em
`https://pvsouza.com/chat`, confirmar streaming, Markdown, bloqueio sem
Turnstile e comportamento do cap.

## 11. Deploy e passos humanos

Passos que exigem ação humana (não delegáveis ao agente):

1. Criar o namespace KV `DAILY_CAP` (`wrangler kv namespace create`).
2. Criar o widget Turnstile no painel Cloudflare (site key + secret).
3. `wrangler secret put TURNSTILE_SECRET` no Worker.
4. Associar o custom domain `ai.pvsouza.com` ao Worker.
5. Buildar o site com as env vars e publicar (`npm run deploy`).

Deploy do Worker: `npx wrangler deploy` em `ai/`.

## 12. Riscos e limites

| Risco | Mitigação |
|---|---|
| Custo/abuso do LLM público | Turnstile + rate limit + teto diário; fail-closed. |
| KV com consistência eventual no cap | Limite documentado; migração para Durable Object no v2. |
| Worker fora do ar derruba o chat | `502 upstream_error` claro na UI; site continua estático e funcional. |
| Turnstile indisponível | Fail-closed por design; erro visível ao usuário. |
| Segredo vazado | Segredos só via `wrangler secret`; `.dev.vars` ignorado. |
| Contexto do modelo excedido | Limite de 12 mensagens / 16000 chars antes da chamada. |

## 13. Alternativas consideradas

- **Hono + zod:** melhor ergonomia de roteamento/validação, porém dependências e
  framework que o repo não usa; descartado para um único endpoint.
- **AI Gateway / AI Search no v1:** adiciona infra e antecipa o RAG (P3);
  adiado para o v2.
- **Rota no mesmo hostname (`pvsouza.com/ai/*`):** evita CORS, mas divide o
  hostname com o Pages; descartado em favor do subdomínio dedicado.
- **Só `workers.dev`:** mais simples, menos polido e com CORS entre domínios;
  descartado.
- **Durable Object para rate limit/cap:** mais preciso, mais complexo; o KV
  atende o v1.

## 14. Follow-ups

- Issue #2: multi-provider de LLM (Groq, Grok, Cerebras).
- v2: AI Gateway (cache, observabilidade).
- v2: persistência de sessão.
- v2: cache de respostas.
- P3: RAG playground (substitui o system prompt estático pelo contexto recuperado).
- P4: artefatos HTML/SVG.

## 15. Critérios de aceite

- `npm run build` e `npm run typecheck` passam.
- `npx vitest run` em `ai/` passa com todos os cenários da seção 10.
- `https://pvsouza.com/chat` renderiza o chat e faz streaming token a token com
  Markdown progressivo.
- Requisição sem Turnstile válido recebe `403 turnstile_failed`.
- Exceder o rate limit responde `429 rate_limited`; exceder o teto diário
  responde `429 daily_cap_exceeded`.
- `GET https://ai.pvsouza.com/health` responde `200 {"status":"ok"}`.
- Nenhum segredo no repositório; nenhuma API route adicionada ao site.
