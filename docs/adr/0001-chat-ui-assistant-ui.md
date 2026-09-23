# ADR 0001 — Chat UI: assistant-ui + Vercel AI SDK (em vez da chat-ui do Hugging Face)

- **Status:** Aceito
- **Data:** 2026-09-22
- **Decisores:** Paulo (dono do produto)
- **Relacionado:** epics do chat/RAG/artefatos; spec do P1 (`docs/superpowers/specs/2026-09-17-pvsouza-p1-deploy-design.md`, secoes 3 e 4); spec do P2 (`docs/superpowers/specs/2026-09-21-pvsouza-p2-chat-v1-design.md`).

## Contexto

O chat v1 e um componente client-only simples (`react-markdown` + `remark-gfm` sobre um stream SSE do Worker `ai.pvsouza.com`). O objetivo e chegar a uma UX proxima da `huggingface/chat-ui` (HuggingChat) sem mudar a topologia registrada no P1: **site estatico no Cloudflare Pages + Worker de IA separado**, sem API routes no site.

Dois fatos motivam a decisao:

1. A `huggingface/chat-ui` **nao e uma biblioteca de UI, e um app full-stack** (SvelteKit 2 + Svelte 5 + MongoDB), que fala apenas com APIs compativeis com OpenAI (`OPENAI_BASE_URL` + `/models`). Adota-la significa rodar um app separado e manter um banco — nao um componente no site.
2. A chat-ui **nao tem artefatos** (painel HTML/SVG tipo Claude/Canvas); ha apenas a issue aberta `huggingface/chat-ui#1607` pedindo isso. Logo, "artefatos" nao e algo que perderiamos ao nao usa-la.

## Decisao

Adotar **`@assistant-ui/react` + `@assistant-ui/ai-sdk`** (sobre o **Vercel AI SDK**) como a UI de chat, como **componente client-only** dentro do site estatico, mantendo a topologia atual:

- A UI roda no browser (compativel com `output: 'export'`) e chama o Worker `ai.pvsouza.com`.
- O Worker expoe o stream no **protocolo de texto do AI SDK** (`streamProtocol: 'text'`, `text/plain`); o UI message stream completo fica como evolucao possivel.
- CORS/Turnstile/rate-limit continuam no Worker (subdominio separado permanece).
- Recursos de plataforma que a chat-ui traz prontos (MCP, multimodal, router, OIDC, MongoDB, compartilhamento, web search) ficam **explicitamente fora** desta decisao e sao registrados como gaps.

## Estado da implementacao

Implementado e publicado (epic #29). O estado final esta detalhado em
`docs/superpowers/specs/2026-09-21-pvsouza-p2-chat-v1-design.md`:

- **UI:** `@assistant-ui/react` + `@assistant-ui/ai-sdk` como componente
  client-only; markdown via `@assistant-ui/react-markdown` com `remark-gfm` +
  `rehype-highlight`.
- **Protocolo:** `POST /chat` responde `200` + `text/plain` (texto concatenado),
  consumido por `TextStreamChatTransport`. Sem framing SSE e sem parser SSE no
  cliente; CORS, Turnstile, rate limit e teto diario seguem no Worker.
- **Codigo legado removido:** componente v1 e `components/chatStream.ts` (parser
  SSE) e seus testes; CSS orfao correspondente.
- **Limitacoes:** threads so na memoria do cliente; anexos apenas de texto
  (sem vision/multimodal); sem RAG/artefatos/MCP/OIDC; teto diario em KV com
  consistencia eventual.

## Alternativas consideradas

| Alternativa | Por que nao |
| --- | --- |
| `huggingface/chat-ui` (app) | SvelteKit + MongoDB + endpoint OpenAI-compativel; exige app separado, banco e camada de compatibilidade no Worker; duplica a superficie do chat |
| `vercel/ai-chatbot` (Next full-stack) | Exige runtime de servidor (nao roda no export estatico); muda a topologia |
| Lobe Chat / LibreChat / Open WebUI | Apps completos, nao componentes; stack/vendor divergentes |
| Libs simples (`@chatscope/chat-ui-kit-react`, `react-chat-elements`) | Nao entregam a UX-alvo (threads, anexos, edicao, generative UI) |
| SPA separada (ex.: Vite) | Nao muda a disponibilidade real de libs client-only; adiciona um terceiro deploy sem ganho |

## Consequencias

**Positivas**

- UX proxima da chat-ui (threads, editar/regenerar, anexos, markdown/codigo, atalhos, a11y, generative UI) sem adotar SvelteKit/Mongo.
- Mantem a topologia, o custo baixo e o isolamento de segredos no Worker.
- Compativel com o AI SDK e com as demos futuras (runtime custom, generative UI; markdown/Mermaid via Streamdown).

**Negativas / custos**

- Novas dependencias React (`@assistant-ui/react`, `@assistant-ui/ai-sdk`, `@assistant-ui/react-markdown`, `ai`, `@ai-sdk/react`).
- Trabalho no Worker para emitir o protocolo de stream do AI SDK.
- Recursos de plataforma da chat-ui nao vem de graca — ver o epic de gaps.

## Referencias

- `https://github.com/huggingface/chat-ui` (app SvelteKit + MongoDB; OpenAI-compativel).
- `huggingface/chat-ui#1607` — pedido de artefatos/Canvas (nao implementado).
- `https://github.com/assistant-ui/assistant-ui` (MIT; `useChatRuntime` sobre o AI SDK).
- `https://ai-sdk.dev` (Vercel AI SDK; `useChat` com endpoint absoluto).
