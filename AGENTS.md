# Regras do repositório

- Para qualquer issue, epic, mudança planejada, branch, pull request, handoff ou decisão de conclusão, leia e siga `docs/project/WORKFLOW.md` antes de agir.
- Este é um site estático publicado no Cloudflare Pages. Não adicione API routes ao site; a API de IA vive em `ai/` (Worker) a partir do P2.
- Ao criar commits, use apenas a identidade Git existente do repositório.
- Nunca adicione ferramentas de IA, assistentes, modelos ou automação como autor, coautor, contribuidor ou atribuição em commits, trailers, PRs ou metadados gerados.
- Nunca grave segredos no repositório.
- Verificações obrigatórias antes de concluir: `npm run build` e `npm run typecheck`.
- Delivery queue: o driver e os agentes vivem em `C:\Users\PVS\projetos\harness` (`bin/dq.ps1`, `bin/goal.ps1`); a política local fica em `.delivery-queue/policy.json`.
