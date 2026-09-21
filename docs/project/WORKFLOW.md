# Fluxo de trabalho

Uma **epic** é uma issue-pai; features, tasks e bugs executáveis são **sub-issues nativas** dela.

## Fontes de verdade

| Informação | Fonte |
| --- | --- |
| Regras permanentes | `AGENTS.md` e documentação versionada |
| Resultado e limites do produto | Epic |
| Escopo executável e critérios de aceite | Sub-issue |
| Racional de design | `docs/superpowers/specs/` |
| Mudanças e evidências de verificação | Pull request |

Referencie a fonte em vez de copiar o conteúdo.

## Planejar uma epic

1. Crie a epic (template Epic) com problema, resultado, limites e critérios de conclusão.
2. Decomponha em sub-issues pequenas e verificáveis, vinculadas pela relação nativa de sub-issue.
3. Declare dependências e ordene somente o que tiver dependência real.

## Executar uma sub-issue

1. Leia a sub-issue e a epic-pai. Se os critérios estiverem ambíguos, ajuste a issue antes do código.
2. Trabalhe em uma issue executável por vez.
3. Branch a partir da base: `<tipo>/<numero>-<slug>` (ex.: `feat/12-chat-streaming`).
4. Implemente o menor incremento que satisfaz os critérios.
5. Rode verificações proporcionais ao risco e guarde comandos e resultados para a PR.
6. Abra uma PR com `Closes #<numero>` e referencie a epic-pai sem fechá-la.

## Handoff

Antes de interromper uma sub-issue, publique um comentário com: estado atual e branch/PR; concluído; verificações e resultados; pendências e bloqueios; próxima ação concreta.

## Concluir

- Faça merge da PR assim que as verificações obrigatórias passarem; não aguarde pedido explícito.
- Feche sub-issues de código pela PR com `Closes #<numero>`.
- Registre follow-ups como novas sub-issues.
