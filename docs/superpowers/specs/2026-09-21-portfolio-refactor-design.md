# Portfolio refactor — referência visual e buraco negro 3D

Status: spec de implementação; a interface ainda não foi implementada.
Data: 2026-09-21. Base inspecionada: `4e80e4c`.

## Objetivo e leitor

Permitir que um agente implemente o redesign do portfólio sem depender da conversa original. O usuário quer partir das cores, composição e animações de rubenmarcus.dev, depois trocar textos e acrescentar conteúdo. A primeira entrega deve ser uma base visual funcional e editável, com um buraco negro 3D como elemento próprio.

“Agent based” significa execução organizada por agentes, com escopo, contratos e evidências por etapa. Não significa acrescentar um novo produto de agentes, MCP ou backend ao site.

## Fontes e ordem de execução

1. Leia [AGENTS.md](../../../AGENTS.md) e [WORKFLOW.md](../../project/WORKFLOW.md).
2. Leia esta spec e o [inventário da referência](../../references/rubenmarcus/README.md). Compare as cinco capturas antes de desenhar.
3. Confira a epic e a sub-issue executável vigentes. Este documento registra o racional; a epic define resultado/limites, a sub-issue define escopo e aceite. Vincule esta spec às issues, sem duplicá-la integralmente.
4. Implemente uma sub-issue por vez, na sequência abaixo. Registre desvios, evidências e pendências na PR correspondente.

Esta worktree `portfolio-refactor` guarda a preparação e os materiais. A branch criada pelo Orca é `paulop2/portfolio-refactor`. Ela não substitui a branch de implementação `<tipo>/<numero>-<slug>` exigida pelo workflow. Este pacote não cria issues, inicia agentes de implementação, faz deploy ou declara o redesign concluído.

## Escopo e decisões

- Redesenhar a home e o mínimo de estilos compartilhados necessário para manter as páginas existentes coerentes e legíveis.
- Preservar Next.js, React, TypeScript, CSS Modules e a exportação estática. Consultar os manifests atuais antes de alterar dependências.
- Usar Three.js com React Three Fiber já presentes para a cena. Não migrar para Astro/Svelte nem adicionar Tailwind ou GSAP por imitação da referência.
- Preservar as rotas `/chat`, `/posts/about-me`, `/posts/rants`, `/posts/first-post`, `/posts/art` e `/three/boxes`, conferindo a lista real na implementação.
- Manter o contrato do chat e o Worker em `ai/`; o redesign não cria API routes.
- Separar conteúdo e apresentação. A redação atual é provisória, mas a UI entregue deve funcionar com dados reais e não conter números ou clientes inventados.
- A cópia HTML/CSS é material de consulta. O produto final usa componentes próprios, sem carregar scripts, analytics, formulários ou endpoints do site de referência.

Ficam fora desta entrega: newsletter, player de música, cursor customizado, novos serviços de contratação, novas páginas apenas para preencher o menu, contadores via API, tradução completa e mudanças no backend. Marquee, textura animada e efeitos de hover fazem parte da direção visual; não removê-los apenas por serem decorativos.

## Sistema visual

Valores observados no CSS público salvo em 2026-09-21:

| Papel | Valor de referência |
| --- | --- |
| Fundo | `#000000` |
| Superfície / superfície elevada | `rgba(134,239,172,.035)` / `.055` |
| Texto e botão claro | `#f5f1ea` |
| Texto secundário / discreto | `rgba(245,241,234,.82)` / `.55` |
| Verde principal / suave / escuro | `#00ff41` / `#4ade80` / `#15803d` |
| Borda / borda forte | `rgba(134,239,172,.10)` / `.18` |
| Largura máxima de conteúdo | `1200px` |
| Espaçamento vertical de seção | referência de `160px` desktop e `88px` mobile |
| Raio de cards / pills | `16px` / `9999px` |
| Hover / reveal | `220ms` / token de `640ms` |
| Curva padrão | `cubic-bezier(.22,1,.36,1)` |

Tipografia declarada: Uncut Sans para títulos, Gabarito para corpo e JetBrains Mono para labels. Os nomes e tokens foram extraídos; as fontes binárias não foram arquivadas. Obter fontes de distribuição autorizada ou escolher alternativas de métricas próximas, registrando a decisão. Os títulos têm peso moderado, tracking negativo e entrelinha próxima de 1.02; não usar uma fonte condensada por pressuposto do prompt anterior.

Centralizar tokens no tema. Usar verde como acento e branco suave para leitura. Conservar grandes áreas escuras, hierarquia de títulos, bordas sutis e ritmo entre seções. Calibrar espaçamentos em telas menores em vez de copiar valores desktop mecanicamente.

## Composição da home

### Faixa superior e navegação

Faixa monoespaçada com textos curtos de atuação, stack e localização. Loop contínuo suave, sem saltos; duplicação visual deve ficar fora da árvore acessível. Oferecer pausa para movimento contínuo e respeitar preferência de movimento reduzido.

Header com identidade do projeto, navegação curta, acesso ao chat e links sociais reais. No scroll, pode adquirir fundo escuro e borda discreta. Menu mobile acessível por teclado, com estado expandido anunciado e retorno de foco ao fechar. Âncoras devem considerar a altura do header.

### Hero

Texto à esquerda e cena à direita no desktop; empilhamento no mobile. Título forte, apresentação curta, descrição e até dois CTAs. Destinos iniciais seguros: “Ver projetos” para uma seção presente e “Conversar com meu assistente” para `/chat`.

Decisão inicial reversível: o buraco negro ocupa o lugar do grande retrato da referência. A foto pessoal existente pode aparecer na apresentação/sobre, sem competir com a cena principal. Essa posição é uma proposta desta spec; o usuário pediu a cena, mas não definiu sua posição.

Código decorativo pode aparecer em baixa opacidade, sem atravessar a leitura. Hero, texto e CTAs devem existir no HTML exportado e funcionar antes de qualquer WebGL carregar.

### Seções

1. **Atuação:** até três cards numerados, com títulos, descrições e tags editáveis. Usar informações fornecidas, sem importar serviços de AEO ou promessas do autor da referência.
2. **Projetos e evidências:** destacar projetos reais, papel exercido e links disponíveis. Solufil foi mencionado pelo usuário; resultados e responsabilidades ainda não foram fornecidos. Métricas e logos são opcionais e só aparecem com dados confirmados. Uma grade de evidências pode usar fatos descritivos, sem contadores fictícios.
3. **Stack:** pills com quebra de linha, superfícies discretas e hover verde. Distinguir experiência prática de aprendizado; não copiar a lista do autor.
4. **Textos e experimentos:** lista horizontal por item, numerada, com thumbnail opcional, título, resumo, metadados existentes e seta. No mobile, adaptar sem esconder o título. Aproveitar páginas reais; não inventar artigos, datas ou tempos de leitura.
5. **Encerramento e rodapé:** identidade, navegação e contatos confirmados. Enquanto não houver contato validado, encerrar com acesso ao chat e sobre. FAQ permanece opcional, condicionado a perguntas/respostas reais.

Os estados de ausência são explícitos: omitir links sem URL, omitir seções vazias e recolher espaços. Não entregar botões sem ação ou itens “em breve” como trabalho concluído.

## Movimento: evidência e implementação

O arquivo CSS preserva regras e keyframes públicos. Não há gravação temporal nem inspeção completa dos módulos JS transitivos; distinguir valores extraídos de propostas abaixo. Antes de reivindicar fidelidade das animações, observar o site vivo no navegador e guardar uma gravação curta, quando acessível. Se estiver indisponível, usar os arquivos salvos e registrar a limitação.

| Efeito | Evidência salva | Contrato para implementação |
| --- | --- | --- |
| Marquee | regra CSS com ciclo linear de 52s | loop sem salto, pausa acessível, sem duplicar anúncio |
| Campo de pontos | fundo com grade de 26px, ciclo de 32s | baixa opacidade; camadas decorativas sem capturar cliques |
| Hover de botões/cards | transições de 220ms | cor/borda, pequeno deslocamento; foco equivalente |
| Reflexo diagonal | transição de fundo de 720ms | efeito sutil em elementos selecionados |
| Navegação | prefixo terminal e underline animado | reforço visual, sem mudar largura do layout |
| Entrada das seções | token de reveal 640ms | proposta: opacity + translateY curto, uma vez por seção |
| Troca de palavras no hero | captura mostra texto embaralhado | opcional; texto acessível estável, sem anúncio repetido |

Preferir CSS e IntersectionObserver para efeitos simples. O conteúdo permanece visível caso observadores ou scripts falhem. Sem scroll hijacking. Um controle global de movimento pode pausar marquee, textura contínua e cena. `prefers-reduced-motion` apresenta estado estático por padrão, inclusive se mudar durante a sessão.

## Buraco negro 3D

### Resultado visual

Centro escuro claramente reconhecível, disco de acreção inclinado e luminoso, partículas/estrelas discretas e distorção aparente da luz ao redor do centro. Paleta verde com highlights claros. Movimento orbital lento e contínuo, sem flashes. Não basta uma esfera preta ou um torus girando: a cena deve comunicar profundidade pelo disco e pelo arco luminoso que parece passar atrás/acima do centro.

Uma aproximação artística por shader é suficiente; não é exigida simulação relativística física. Evitar modelo GLB como dependência desnecessária. O agente deve registrar a técnica e seus limites visuais.

### Contrato técnico

- Cena isolada em componente client, carregada dinamicamente por um wrapper compatível com a exportação estática do Next. Imports de WebGL ficam dentro desse limite.
- Wrapper reserva dimensões e mostra fallback estático desde o primeiro render. A cena só substitui o fallback após o primeiro frame bem-sucedido, sem deslocamento do layout.
- Tema, intensidade, qualidade e estado de movimento têm configuração explícita. Conteúdo editorial não entra no loop de renderização.
- No desktop com ponteiro preciso, permitir pequena resposta ao mouse com damping. Touch mantém scroll normal; sem câmera livre ou captura de gestos obrigatória.
- Canvas decorativo fora da árvore acessível e da ordem de foco. Controles acessíveis ficam no DOM.
- Instanciar renderer somente quando próximo/visível no viewport e com movimento habilitado. Pausar frames fora do viewport, em aba oculta ou por controle do usuário.
- Limitar DPR inicialmente a 1.5; reduzir qualidade quando necessário. Não usar React state a cada frame. Limpar listeners, observers e recursos GPU no unmount; testar remontagem e context loss.
- Ausência de WebGL, erro de carregamento, perda de contexto ou preferência por movimento reduzido preservam o fallback e todos os CTAs. Fallback pode ser SVG/CSS ou imagem própria; não depende do site de referência.
- O bundle da cena é exclusivo desse componente. As outras páginas não devem passar a carregar Three.js por causa de um import global do redesign.

### Verificação específica

Gravar pelo menos dez segundos da cena no desktop, incluindo interação do ponteiro. Registrar resolução, browser, hardware e perfil de qualidade. Meta de ajuste: aproximadamente 60fps no desktop de verificação e pelo menos 30fps no dispositivo mobile de verificação; emulação de viewport não comprova desempenho em hardware mobile. Se não houver dispositivo, registrar essa lacuna sem declarar o teste feito.

Comparar screenshot da cena e do fallback; ambos mantêm a composição. Confirmar que o loop pausa fora da tela e em aba oculta, e que falha de WebGL não produz tela vazia ou erro não tratado.

## Conteúdo editável

Criar um módulo tipado de conteúdo local para identidade, navegação, CTAs, atuação, projetos, tecnologias, textos e links. Cada item de lista tem ID estável. URLs e métricas opcionais são modeladas como opcionais, não strings vazias. Componentes cuidam de layout; o módulo cuida de redação e seleção de itens. Sem CMS nesta entrega.

Dados fornecidos: Paulo Vitor Souza; desenvolvimento fullstack com TypeScript; Hexeract AI LLC como consultoria de IA; Campinas/Valinhos, SP, remoto; Go, IoT e Edge como interesses em aprendizado. Stack candidata: TypeScript, Node.js, React/Next.js, Cloudflare Workers, Go, Python, Docker. Não transformar interesse em afirmação de senioridade. Links sociais, disponibilidade e métricas exigem confirmação no conteúdo existente ou pelo usuário.

## Etapas para agentes

Papéis são responsabilidades que podem ser assumidas sequencialmente pelo mesmo agente. O coordenador mantém uma sub-issue executável ativa por vez, conforme o workflow. Revisão independente pode ser delegada sem abrir outra frente de implementação. Nenhum agente deve editar arquivos compartilhados simultaneamente sem coordenação explícita.

| Etapa | Responsável | Depende de | Entrega e aceite local |
| --- | --- | --- | --- |
| S1 — Tema e estrutura | agente frontend | epic/sub-issue definidas | tokens, fontes, conteúdo tipado, header e hero com fallback; desktop/mobile utilizáveis e links reais |
| S2 — Seções | agente frontend | S1 | atuação, projetos, stack, textos e footer; layouts condizentes com capturas, vazios tratados |
| S3 — Movimento | agente frontend | S2 | marquee, textura, hovers e reveals; pausa e reduced-motion verificados |
| S4 — Cena 3D | agente gráficos | S3 | buraco negro integrado, fallback, lifecycle e qualidade verificados conforme contrato |
| S5 — Revisão e integração | agente revisor + responsável por correções | S4 | evidências visuais, regressões corrigidas, comandos obrigatórios e aceite global satisfeitos |

Ao iniciar cada etapa: ler a issue/epic, verificar o estado Git, executar apenas o escopo da etapa e conferir seus critérios. Ao concluir: registrar arquivos afetados, decisões, comandos/resultados, capturas e limitações na PR. Seguir o workflow para branch, PR, merge e handoff; não inferir encerramento da epic a partir de uma etapa.

## Aceite global

- [ ] Home reconhecivelmente inspirada na referência por paleta, tipografia, escala, ritmo, bordas, pills e movimento, com identidade própria e buraco negro integrado.
- [ ] Capturas em 1440×900, 1920×1080, 768×1024 e 390×844; revisão adicional de overflow a 320px. Comparação visual por seção com as referências salvas.
- [ ] Textos e listas editáveis sem modificar o código dos componentes visuais.
- [ ] CTAs e navegação operantes; rotas existentes preservadas, chat sem regressão de streaming, erros ou configuração.
- [ ] Conteúdo sem JavaScript continua legível e navegável. Sem layout shift decorrente da cena/fontes/imagens; dimensões reservadas e fallback visível.
- [ ] Contraste de texto normal de pelo menos 4.5:1, teclado e foco visível, estrutura de headings coerente e menu mobile operável.
- [ ] Movimento reduzido, pausa global, viewport oculto, aba oculta e falha de WebGL verificados.
- [ ] Bundle da cena carregado sob demanda e ausente das páginas que não o utilizam; sem requisições de produção para rubenmarcus.dev.
- [ ] `npm run build` e `npm run typecheck` passam. Executar testes existentes relevantes ao shell/chat e registrar resultados; não reescrever testes para espelhar CSS.
- [ ] Evidências e limitações registradas na PR; checklist de produção corresponde a comportamento observado, não apenas à existência de código.

## Prompt de início para o próximo agente

> Leia AGENTS.md, docs/project/WORKFLOW.md, esta spec e docs/references/rubenmarcus/README.md. Inspecione os materiais salvos e o código atual. Localize ou prepare a epic e as sub-issues conforme o workflow antes de alterar a interface. Execute uma etapa por vez, preservando a stack e o chat. Use a referência visual como base e os contratos desta spec para conteúdo editável, movimento e buraco negro 3D. Registre evidências verificáveis e limitações; não trate a existência desta spec como prova de implementação.
