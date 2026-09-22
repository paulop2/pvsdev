# Verificação de desempenho da cena 3D e pausa — issue #16

- Issue: [#16](https://github.com/paulop2/pvsdev/issues/16) — Verificar desempenho da cena 3D e pausa em aba oculta em hardware real
- Epic: [#5](https://github.com/paulop2/pvsdev/issues/5) — Redesign do portfólio com buraco negro 3D
- Data da coleta: 2026-09-22
- Escopo: verificação em hardware real (desktop). Sem alteração de código de produto.

Esta verificação fecha, para o desktop, o item de aceite global “Movimento reduzido, pausa global,
viewport oculto, aba oculta e falha de WebGL verificados”. O desempenho mobile permanece como lacuna
declarada (sem dispositivo real).

## Ambiente de verificação (desktop)

| Item | Valor |
| --- | --- |
| GPU | NVIDIA GeForce RTX 5060 Ti (driver 32.0.16.1088) |
| Renderer WebGL | `ANGLE (NVIDIA, NVIDIA GeForce RTX 5060 Ti (0x00002D04) Direct3D11 vs_5_0 ps_5_0, D3D11)` |
| CPU | AMD Ryzen 5 5600G |
| RAM | 31,4 GB |
| Sistema | Windows 10 Pro 10.0.19045 |
| Monitor | 1920×1080 @ 180 Hz |
| Navegador | Google Chrome 153.0.8010.53 (headed, GPU real, sem `--disable-gpu`) |
| Viewport medido | 1904×929 CSS px, `devicePixelRatio = 1` |
| Canvas da cena | buffer 486×486, CSS 486×486 |

A verificação anterior da cena era headless (SwiftShader), sem GPU nem vsync. Aqui a página foi
servida localmente a partir do export estático (`out/`) e aberta no Chrome com aceleração por GPU.

## Método

1. `npm ci` e `npm run build` no worktree; o export estático fica em `out/`.
2. Servidor HTTP local (Node) serve `out/`; Chrome headed é iniciado com `--remote-debugging-port`
   em um perfil limpo, sem flags que desabilitem GPU.
3. Instrumentação injetada antes do carregamento da página (via CDP
   `Page.addScriptToEvaluateOnNewDocument`) conta chamadas de desenho (`drawArrays`/`drawElements`
   e variantes instanciadas em `WebGLRenderingContext`/`WebGL2RenderingContext`) e ticks de
   `requestAnimationFrame`. Cada frame da cena faz uma chamada de desenho, então
   `drawCalls/s` mede o frame rate efetivo da cena.
4. Interação de ponteiro: `Input.dispatchMouseEvent` (CDP) com `pointerType: mouse` sobre o canvas,
   com contagem de eventos `pointermove` recebidos.
5. Aba oculta: abertura de uma segunda aba real e `Target.activateTarget`, lendo `document.hidden`
   e o delta de chamadas de desenho na aba da cena.
6. Gravação: `canvas.captureStream(60)` + `MediaRecorder` (VP9) na própria página, com movimento de
   ponteiro durante ~12 s; o blob foi enviado por `fetch` ao servidor local e transcodificado com
   ffmpeg (VP9, CRF 36) para reduzir tamanho.
7. Movimento reduzido: `Emulation.setEmulatedMedia` com `prefers-reduced-motion: reduce`.
8. Falha de WebGL: `HTMLCanvasElement.prototype.getContext` interceptado para devolver `null` em
   `webgl`/`webgl2` antes do carregamento da página.

Dados brutos em [`data/`](./data). Gravação e capturas em [`assets/`](./assets).

## Resultados

### 1. FPS no desktop (meta ~60 fps)

| Cenário | Duração | Chamadas de desenho | FPS de desenho | Ticks de rAF | FPS de rAF |
| --- | --- | --- | --- | --- | --- |
| Ocioso (sem ponteiro) | 4,01 s | 722 | **179,9** | 722 | 179,9 |
| Ativo (interação de ponteiro) | 3,02 s | 543 | **180,1** | 543 | 180,1 |

O frame rate acompanha exatamente o refresh do monitor (180 Hz), ou seja, a cena está limitada ao
vsync e não à GPU. A meta de ~60 fps no desktop é atingida com folga. Não houve necessidade de
ajustar qualidade ou DPR.

Fonte: [`data/desktop-measurements.json`](./data/desktop-measurements.json).

### 2. Interação do ponteiro

40 eventos `pointermove` disparados sobre o canvas; 40 recebidos com `pointerType: "mouse"`. A cena
responde ao ponteiro (paralaxe com damping em `uMouse`) e mantém ~180 fps durante a interação.

### 3. Gravação (≥10 s, com ponteiro)

- Arquivo: [`assets/scene-desktop-issue16.webm`](./assets/scene-desktop-issue16.webm)
- Duração: **12,04 s**; 486×486; VP9; 701 frames capturados (~58 fps); 306.676 bytes.
- Movimento de ponteiro: 208 amostras ao longo de 12 s (trajetória circular sobre o canvas).
- Original do `MediaRecorder`: 4.796.313 bytes; transcodificado para 306.676 bytes sem corte de
  duração.

Fonte: [`data/recording-meta.json`](./data/recording-meta.json).

### 4. Aba oculta (`visibilitychange`)

Troca real de aba no navegador (segunda aba ativada), sem emulação de visibilidade.

| Observação | Valor |
| --- | --- |
| `document.hidden` com a outra aba ativa | `true` (`visibilityState: "hidden"`) |
| Chamadas de desenho na aba oculta (2,5 s) | **0** |
| `document.hidden` ao voltar | `false` (`visibilityState: "visible"`) |
| Chamadas de desenho após voltar (2,0 s) | 361 (~180 fps) |

A cena para de renderizar quando a aba fica oculta e retoma ao voltar.

### 5. Viewport oculto

Com a página rolada para longe da cena (`scrollY = 3637`), o canvas é desmontado
(`canvasCount = 0`) e o fallback permanece. Ao voltar ao topo, o canvas é remontado e volta a
renderizar.

### 6. Pausa global (controle “Movimento” no header)

O botão `Movimento` do header alterna o estado global de movimento.

| Estado | `data-motion` | Canvas | Marquee | DotField | `aria-pressed` |
| --- | --- | --- | --- | --- | --- |
| Ligado | `on` | 1 | `running` | `running` | `false` |
| Desligado | `off` | 0 | `paused` | `paused` | `true` |
| Relidado | `on` | 1 | `running` | — | `false` |

### 7. Movimento reduzido (`prefers-reduced-motion: reduce`)

| Verificação | Valor |
| --- | --- |
| `data-motion` | `off` |
| Canvas da cena | ausente (`canvasCount = 0`) |
| Fallback | presente e visível |
| Marquee / DotField | `animation-play-state: paused` |
| Links/CTAs no DOM | 25 |

Captura: [`assets/fallback-reduced-motion.png`](./assets/fallback-reduced-motion.png).

### 8. Falha de WebGL

Com `getContext('webgl'|'webgl2')` devolvendo `null`, a página não instancia canvas
(`canvasCount = 0`), mantém o fallback visível (`opacity: 1`) e preserva os 25 links/CTAs. Nenhuma
exceção ou `console.error` foi registrada.

Captura: [`assets/fallback-webgl-failure.png`](./assets/fallback-webgl-failure.png).
Fonte: [`data/webgl-failure.json`](./data/webgl-failure.json).

### 9. Perfil de qualidade final

Nenhum ajuste foi necessário; o perfil observado permanece o do código atual:

- `quality = 1` em desktop com ponteiro preciso; `quality = 0.45` em `pointer: coarse` ou
  viewport < 720 px.
- `dpr` limitado a `[1, 1.5]`; nesta medição o `devicePixelRatio` do ambiente era 1.
- `frameloop` alterna entre `always` e `never` conforme visibilidade/aba/controle.

## Lacuna: mobile

**Não testado em dispositivo mobile real.** Não há aparelho disponível neste ambiente e a emulação
de viewport não comprova desempenho em hardware mobile (conforme a própria spec). Portanto:

- Nenhuma meta de ≥30 fps é declarada para mobile.
- O comportamento mobile (perfil `quality = 0.45`, ponteiro coarse) permanece não verificado em
  hardware real e precisa de follow-up com um dispositivo físico.

## Limitações

- O FPS de desenho é limitado ao vsync (180 Hz neste monitor); em um monitor de 60 Hz a cena deve
  ficar em ~60 fps. O número medido reflete este hardware.
- A gravação cobre apenas o canvas da cena (486×486), não a página inteira.
- Verificação feita apenas no Chrome 153; não foram testados Firefox/Safari nem outras GPUs.
- A falha de WebGL foi induzida por interceptação de `getContext`, não por perda de contexto real de
  GPU.
- A pausa em aba oculta foi observada no nível de renderização (0 chamadas de desenho). Em abas
  ocultas o Chrome não dispara `requestAnimationFrame`; a medição, portanto, não isola se a parada
  vem do `frameloop='never'` do app ou do throttling do navegador. O resultado observável (cena
  congelada e retomada ao voltar) é o mesmo e atende ao critério.
- Em aba oculta o React adia a atualização de estado do handler `visibilitychange`; a leitura das
  props no momento em que a aba está oculta ainda mostra `paused: false`. Isso não altera o
  comportamento observado (sem frames renderizados), mas é registrado para transparência.

## Comandos executados

```powershell
npm ci
npm run build
npm run typecheck
```

As medições foram feitas por scripts Node locais (CDP sobre o Chrome com GPU real) executados fora
do repositório; a metodologia está descrita acima e os dados brutos estão em `data/`.
