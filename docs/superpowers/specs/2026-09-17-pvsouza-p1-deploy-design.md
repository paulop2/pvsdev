# pvsouza.com — Redesign e plataforma de IA

**Data:** 2026-09-17
**Status:** P0–P2 concluídos; P3–P5 pendentes
**Repo:** `paulop2/pvsdev` (`C:\Users\PVS\projetos\pvsdev`)

## Estado da execução

- **P0 — Processo:** concluído (templates de issue, PR template, `AGENTS.md`, `WORKFLOW.md`).
- **P1 — Deploy/plataforma:** concluído. Site em Next.js 15 (App Router, `output: 'export'`)
  publicado no Cloudflare Pages (projeto `pvsouza`).
  - Evidência: `https://pvsouza.com` responde `200` em `/`, `/posts/about-me/`,
    `/posts/rants/`, `/posts/first-post/`, `/posts/art/`, `/three/boxes/`.
  - `https://www.pvsouza.com/...` responde `301` para `https://pvsouza.com/...`
    (path e query preservados).
  - Verificado com `scripts/smoke.ps1` e `curl.exe`.
  - Desvio documentado: o demo `birds` foi adiado (follow-up), conforme mitigação da §5.6.
- **P2 — Chat v1:** concluído e publicado. Spec em
  `docs/superpowers/specs/2026-09-21-pvsouza-p2-chat-v1-design.md`; Worker em
  `https://ai.pvsouza.com` e chat em `https://pvsouza.com/chat`. A UI/protocolo
  evoluíram para o **chat v2** (epic #29: `@assistant-ui/react` + AI SDK,
  protocolo de texto; ADR 0001).
- **P3–P5:** não iniciados.

## 1. Contexto

`pvsouza.com` é o domínio pessoal de Paulo Vitor Souza, hospedado no Cloudflare
(zone ativa, NS `vivienne/watson.ns.cloudflare.com`, conta
`paulo225vitor@gmail.com`). O domínio raiz está **fora do ar**: não há registro
`A`/`AAAA`/`CNAME` no apex — apenas `SOA`. O site estático que corresponde ao
domínio é o repo `pvsdev` (Next.js 10.0.5 / React 17, com demos three.js), que
não tem nenhum alvo de deploy configurado no repositório.

O autor está entre empregos e quer usar o site como portfólio ativo, com foco em
posicioná-lo como **AI engineer**. Para isso quer adicionar, de forma
incremental: um chat LLM com streaming e artefatos, uma seção didática/visual de
RAG, e outras features de IA no futuro.

Subdomínios já existentes no mesmo domínio (não fazem parte deste projeto, mas
restringem decisões de DNS):

- `maratona.pvsouza.com` — Cloudflare Pages `pj240` (repo
  `projeto-integrador-PJI240`). Hostname associado ao Pages, mas **falta o CNAME**
  no DNS.
- `nexus.pvsouza.com` — app `nexus` (deploy self-hosted, ver `nexus/deploy`).

## 2. Objetivos e não-objetivos

**Objetivos (do projeto como um todo):**

1. Colocar o site de volta no ar em `https://pvsouza.com`, com `www` redirecionando
   para a raiz e HTTPS válido.
2. Ter uma base técnica moderna e sustentável para adicionar features de IA.
3. Chat LLM público com streaming e renderização progressiva.
4. Artefatos (render de HTML/SVG/Markdown) no chat, de forma faseada.
5. Playground didático de RAG que mostre o pipeline ao vivo.
6. Facilitar adicionar novas features de IA depois, sem retrabalho estrutural.

**Não-objetivos (agora):**

- Reescrever todo o conteúdo editorial do site.
- Multiusuário, login, ou persistência de histórico de chat.
- Vector DB gerenciado / escala de produção no RAG (fica para depois).
- Migrar `maratona.pvsouza.com` e `nexus.pvsouza.com`.

## 3. Decisões aprovadas

| Tema | Decisão |
|---|---|
| Base do site | Modernizar o repo `pvsdev` (mantém histórico e conteúdo). |
| Stack de IA | APIs externas (OpenAI/Anthropic/Groq) atrás de um Worker; chaves só no servidor. |
| Topologia | Site **estático** no Cloudflare Pages + **Worker separado** para a API de IA. |
| Artefatos | Faseado: **v1 Markdown → v2 HTML/SVG → v3 completo** (React/Mermaid/charts). |
| Seção de RAG | **Playground do pipeline ao vivo** (chunk → embed → retrieve com scores → prompt → resposta). |
| Proteção | Turnstile + rate limit por IP/sessão + teto diário de tokens/custo; sem login. |
| Backend de retrieval | **Embeddings pré-computados no build + cosine em memória** no Worker (interface preparada para migrar para Vectorize). |

## 4. Roadmap (sub-projetos)

| # | Sub-projeto | Entrega | Depende de |
|---|---|---|---|
| P0 | Processo | Camada leve de rastreamento no repo (templates de epic/feature/task/bug, PR template, `AGENTS.md` + `WORKFLOW.md` curto). | — |
| P1 | Deploy/plataforma | `pvsdev` modernizado (Next 15 App Router, `output: export`) no Pages + `pvsouza.com` na raiz, www→raiz, HTTPS. | P0 |
| P2 | Chat | Worker de IA com streaming (v2: protocolo de texto do AI SDK) + render Markdown + Turnstile/rate-limit/teto + UI (v2: assistant-ui). | P1 |
| P3 | RAG playground | Playground do pipeline sobre corpus curado, com scores e citações visíveis. | P2 |
| P4 | Artefatos v2 | Painel lateral + iframe sandboxed para HTML/SVG. | P2 |
| P5+ | Mais IA | Estrutura extensível (`/demos/*` no site + rotas no Worker) para novas features. | P2 |

Cada sub-projeto terá sua própria spec + plano. Esta spec detalha o **P1**.

## 5. Design do P1 — Deploy/plataforma

### 5.1 Framework

- **Next.js 15 (App Router) + React 19 + TypeScript**, com `output: 'export'`.
- Migração de `pages/` para `app/`:
  - `app/layout.tsx` — root layout (substitui `components/layout.js`), com header/footer compartilhados.
  - `app/page.tsx` — home (conteúdo atual).
  - `app/posts/about-me/page.tsx`, `app/posts/rants/page.tsx`, `app/posts/art/page.tsx`, `app/posts/first-post/page.tsx`.
  - `app/three/birds/page.tsx`, `app/three/boxes/page.tsx` — demos three.js como **client components** (`'use client'` + `dynamic(..., { ssr: false })`).
- Upgrade de `react-three-fiber` → `@react-three/fiber`, `@react-three/drei` e `three` para versões modernas.
  - Se o upgrade se mostrar custoso, os demos three.js são isolados numa fatia de polish posterior; o P1 sobe o site sem eles.
- Sem API routes no site (é estático). Todo acesso a IA vai para o Worker.
- CSS Modules existentes migram com ajustes mínimos.

### 5.2 Estrutura de repositório

```
pvsdev/
  app/                 # rotas (App Router)
  components/          # componentes compartilhados
  styles/              # CSS Modules
  public/              # assets (imagens, glb)
  ai/                  # Worker de IA (P2+)
    wrangler.toml
  docs/superpowers/specs/
  package.json
```

### 5.3 Deploy

- Pages project: **`pvsouza`**.
- Build: `next build` → `out/`.
- Deploy: `npx wrangler pages deploy out --project-name pvsouza`.
- Custom domains no projeto Pages: `pvsouza.com` e `www.pvsouza.com`.
  - A Cloudflare cria o registro do apex por CNAME flattening apontando para
    `pvsouza.pages.dev` (é exatamente o registro ausente hoje).
  - **Fallback manual** (token de OAuth não edita DNS): criar no painel o CNAME
    `@` → `pvsouza.pages.dev` e `www` → `pvsouza.pages.dev`.
- Redirect 301 `www.pvsouza.com` → `pvsouza.com` via Cloudflare Redirect Rule.
- HTTPS: emissão automática pelo Cloudflare após o domínio ativar.

### 5.4 Conteúdo e UX no P1

- Preservar o conteúdo atual: home, Sobre mim, Rants, Art, First Post.
- Home ganha placeholders (ocultos/com "em breve") para as seções Chat e RAG,
  ativadas em P2/P3.
- Commitar a correção pendente de links em `pages/posts/about-me.js`.
- Home atual menciona "Portfolio — em breve"; mantida como está para não expandir
  escopo.

### 5.5 Verificação / critérios de aceite

- `npx next build` conclui sem erros e gera `out/`.
- `npx wrangler pages deploy out --project-name pvsouza` publica com sucesso.
- `Resolve-DnsName pvsouza.com -Type A` retorna IP(s) do Cloudflare (não só SOA).
- `curl -I https://pvsouza.com` retorna `200` e certificado válido.
- `curl -I https://www.pvsouza.com` redireciona `301` para a raiz.
- Páginas principais (home, about-me, rants) retornam 200 e renderizam.

### 5.6 Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Upgrade three.js/`react-three-fiber` quebra demos | Isolar demos em fatia posterior; P1 não depende deles. |
| Token OAuth não cria o registro DNS do apex | Criar CNAME manualmente no painel (ação de 1 min, documentada). |
| Conflito com subdomínios existentes | P1 só toca apex e `www`; não altera `maratona`/`nexus`. |
| Next 15 static export com componentes client-side | `'use client'` + dynamic import; validar no build. |

## 6. Alternativas consideradas

- **Rewrite com Astro** (ilhas + content collections): mais simples para site
  estático e MDX, porém descartado para manter o repo e o histórico do `pvsdev`
  (escolha do autor).
- **Next full SSR no Workers via `@opennextjs/cloudflare`**: um único deploy,
  mas mais setup e irrelevante já que o site é estático e a IA fica num Worker
  dedicado.
- **Vercel + DNS Cloudflare**: menor atrito para streaming, porém menos
  Cloudflare no portfólio e dois provedores.
- **Vectorize desde já no RAG**: mais escalável, mas a similaridade vira
  caixa-preta (pior didaticamente) e adiciona infra; migração fica preparada.

## 7. Processo e rastreamento (P0 — camada leve)

Adotamos uma versão enxuta do processo do repo `projeto-integrador-PJI240`,
sem Project board e sem automações.

**Artefatos:**

- `.github/ISSUE_TEMPLATE/{epic,feature,task,bug}.yml` — adaptados do pji240.
- `.github/pull_request_template.md` — evidências de verificação.
- `AGENTS.md` — regras permanentes (inclui: **nunca** atribuir ferramentas de IA
  em commits/PRs/metadados; usar a identidade Git existente).
- `docs/project/WORKFLOW.md` — versão curta: criar epic → decompor em sub-issues
  → branch `<tipo>/<numero>-<slug>` → PR com `Closes #numero` → handoff.

**Fontes de verdade:**

| Informação | Fonte |
|---|---|
| Regras permanentes | `AGENTS.md` + documentação versionada |
| Resultado e limites da feature | Epic |
| Escopo executável e critérios de aceite | Sub-issue |
| Racional de design | Spec em `docs/superpowers/specs/` |
| Mudanças e evidências | Pull request |

**Labels:** `epic`, `enhancement` (feature), `task`, `bug` (mesma taxonomia do pji240).

**Fora desta camada (por ora):** Project board (Kind/prioridade/área/esforço),
milestones, collectors PowerShell, subagents `.opencode` e o ciclo
worktree+review adversarial+handoff automatizado.

## 8. Pontos em aberto (para specs seguintes)

- Modelos/roteamento exatos por feature (P2/P3).
- Corpus exato do playground de RAG (provável conjunto curado versionado no repo).
- Persistência de histórico de chat (provável: nenhuma na v1).
- Branding/visual redesign do site (fora do P1, salvo ajustes mínimos).
