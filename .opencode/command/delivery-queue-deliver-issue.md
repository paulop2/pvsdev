---
description: Entrega uma issue da fila de delivery (uma tentativa), executada pelo worker.
agent: delivery-queue-worker
---

Entrega uma unica issue da delivery queue.

Argumentos: `$ARGUMENTS` no formato `<issue> --repo <owner/repo> --base <branch>`.

Siga o fluxo do agente worker: implementar, verificar, review adversarial,
corrigir, push, abrir a PR com `Closes #<issue>` e publicar o comentario de
tentativa `delivery-queue-attempt:v1` com `status: delivered`, `pr`, `headSha`,
`review` e `checks` locais vinculados ao head. Nao faca merge.
