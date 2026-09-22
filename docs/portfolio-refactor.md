# Portfolio refactor

Ponto de entrada para planejar e implementar o redesign do portfólio.

- [Spec de implementação por agentes](superpowers/specs/2026-09-21-portfolio-refactor-design.md)
- [Referência visual, HTML/CSS e capturas](references/rubenmarcus/README.md)
- [Workflow do projeto](project/WORKFLOW.md)

Estado: implementação da interface concluída (etapas S1–S4) e revisada (S5). A home usa tokens próprios, conteúdo tipado em `content/site.ts`, seções inspiradas na referência, movimento com controle global e um buraco negro 3D com fallback. Verificações e limitações ficam registradas nas PRs da epic #5.

## Decisões registradas

- Fontes: alternativas de métricas próximas às declaradas na referência — Space Grotesk (títulos), Inter (corpo) e JetBrains Mono (labels) — via `next/font`, self-hosted na exportação.
- Conteúdo não confirmado é omitido em vez de inventado: links sociais ausentes, Solufil apenas com o nome e nota explícita, sem métricas fictícias.
- O buraco negro ocupa o lugar do retrato da referência; a cena é uma aproximação artística por shader (sem simulação relativística nem GLB).

## Limitações conhecidas

- Desempenho da cena 3D não medido em hardware real (apenas headless/SwiftShader); sem dispositivo mobile de verificação.
- Pausa por aba oculta implementada, mas não exercitada em navegador real.
- Conteúdo de projetos e links sociais pendente de confirmação do usuário.
