# Handoff — decompor P3–P5 (e novos epics) em sub-issues

- **Data:** 2026-09-22
- **Para:** proximo agente que assume a decomposicao (item "C").
- **Regras:** siga `docs/project/WORKFLOW.md` antes de agir.

## Estado atual

- **P0–P2 concluidos** e publicados (site estatico no Cloudflare Pages + Worker `ai.pvsouza.com`).
- **Epic #5** (redesign do portfolio) com S1–S5 e #16 concluidos; resta **#17** (conteudo pendente de dados do usuario).
- **Delivery queue** operacional (PRs #18–#24 corrigiram coletor, quoting do `gh`, deps do worktree, id do comentario, modelo dos agentes, reconciliacao e verificacao pos-merge).
- **ADR 0001 aceito:** `docs/adr/0001-chat-ui-assistant-ui.md` — adotar **assistant-ui + Vercel AI SDK** como UI de chat, mantendo a topologia estatica + Worker. A `huggingface/chat-ui` **nao** tem artefatos (issue #1607 aberta).

## Decisao que afeta a decomposicao

UI de chat = **assistant-ui** client-only no site estatico, chamando o Worker no protocolo do AI SDK. Nada de SvelteKit/Mongo; gaps de plataforma ficam catalogados em #30.

## Epics a decompor

| Epic | Tema | Nota |
| --- | --- | --- |
| **#29** | Chat UI v2: assistant-ui + Vercel AI SDK | Comecar por aqui; destrava UX-alvo |
| **#25** | P3: RAG playground (pipeline visivel) | Depende do P2; retrieval no Worker |
| **#26** | P4: Artefatos v2 (HTML/SVG sandboxed) | Client-side; nao existe na chat-ui |
| **#27** | P5: Estrutura extensivel para features de IA | `/demos/*` + registry no Worker |
| **#28** | Chat v2: AI Gateway, cache e sessao | Follow-ups do spec do P2 |
| **#30** | Gaps da chat-ui nao cobertos pelo assistant-ui | Catalogo; decidir construir/adiar/descartar |

## Restricoes

- Site **estatico** (`output: 'export'`): sem API routes; toda IA no Worker `ai/`.
- Verificacoes: `npm run build`, `npm run typecheck` (raiz) e `npx vitest run` em `ai/`.
- Sem segredos no repo; sem atribuicao de IA em commits/PRs (`AGENTS.md`).
- Trabalho em sub-issues nativas da epic; PR com `Closes #<n>`.

## Proxima acao concreta

1. Decompor **#29** e **#25** em sub-issues pequenas e verificaveis (tracer bullets), linkadas como sub-issues nativas.
2. Declarar dependencias reais (blocked-by) entre sub-issues; sem dependencia, nao ordenar.
3. Rotular `delivery-queue-ready` apenas as sub-issues que o loop pode entregar de forma autonoma (sem depender de dados/decisao do usuario).
4. Depois, decompor #26, #27, #28 e #30 (o catalogo de gaps pode virar issues filhas conforme a decisao de cada linha).

## Ferramentas

- Criar issue: `gh issue create --repo paulop2/pvsdev --title <t> --label enhancement|task --body-file <arquivo>`.
- Linkar sub-issue: GraphQL `addSubIssue(input:{issueId, subIssueId})` (obter node IDs com `gh issue view <n> --json id`).
- Dependencias: se `addBlockedBy` nao estiver disponivel, declarar no corpo da sub-issue e nao rotular como `delivery-queue-ready` ate o blocker concluir.

## Evidencias / referencias

- ADR: `docs/adr/0001-chat-ui-assistant-ui.md`.
- Specs: `docs/superpowers/specs/2026-09-17-pvsouza-p1-deploy-design.md` (roadmap P0–P5), `docs/superpowers/specs/2026-09-21-pvsouza-p2-chat-v1-design.md` (follow-ups).
- PRs recentes: #18–#24 (delivery queue), #22 (#16).

## Bloqueios

- Nenhum tecnico. **#17** depende de dados do usuario (links sociais, Solufil, contato).
