# pvsouza — Plano de Implementação P0 + P1 (Processo + Deploy)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publicar o site pessoal em `https://pvsouza.com` (Cloudflare Pages) com a base moderna (Next 15 App Router, export estático) e a camada leve de processo (epics/features/tasks/bugs).

**Architecture:** Site 100% estático gerado por `next build` com `output: 'export'` (pasta `out/`) e publicado no Cloudflare Pages. A IA (chat/RAG) ficará separada em `ai/` (Worker) nos planos P2+. Nenhuma API route vive no site.

**Tech Stack:** Next.js 15 (App Router), React 19, TypeScript (adoção incremental; páginas de conteúdo podem continuar `.js`), `@react-three/fiber` v9 + `@react-three/drei` v10, Wrangler v4, Cloudflare Pages.

## Global Constraints

- Framework: Next.js 15 App Router + React 19; `output: 'export'`; `images.unoptimized: true`; `trailingSlash: true`.
- O site é estático: **nenhuma** API route (`pages/api` ou `app/**/route.ts`) pode existir no build final.
- Pacotes: `next@^15.5`, `react@^19`, `react-dom@^19`, `@react-three/fiber@^9`, `@react-three/drei@^10`, `three@^0.180`, `typescript@^5.6`, `wrangler@^4`. Substituir `react-three-fiber` (v6, obsoleto) por `@react-three/fiber`.
- Gerenciador: **npm** (remover `yarn.lock`). Node >= 20 (máquina tem v24).
- Projeto Pages: `pvsouza`, branch de produção `main`. Domínios: `pvsouza.com` (apex) e `www.pvsouza.com` (redirect 301 → apex).
- Conteúdo preservado; demos three.js pesados ficam para uma fatia futura — **apenas `boxes` é mantido**; `birds` é adiado (removido do P1).
- Commits usam a identidade Git existente (`paulop2`). **Nunca** adicionar atribuição de IA em commits/PRs/metadados.
- Shell: Windows PowerShell 5.1. Comandos de rede usam `Resolve-DnsName` e `curl.exe`.
- Specs de referência: `docs/superpowers/specs/2026-09-17-pvsouza-p1-deploy-design.md`.

---

## File Structure

**Criar:**
- `.github/ISSUE_TEMPLATE/{epic,feature,task,bug,config}.yml`, `.github/pull_request_template.md`
- `AGENTS.md`, `docs/project/WORKFLOW.md`
- `next.config.mjs`, `tsconfig.json`, `next-env.d.ts` (gerado)
- `app/layout.tsx`, `app/page.tsx`
- `app/posts/{about-me,rants,art,first-post}/page.{js,tsx}`
- `app/three/boxes/page.tsx`
- `components/PageShell.tsx`, `components/BoxesScene.tsx`, `components/BoxesCanvas.tsx`
- `public/*` (movido de `pages/public/*`)
- `scripts/smoke.ps1`

**Modificar:**
- `package.json`, `.gitignore`
- `pages/posts/first-post.js` (antes de migrar)

**Remover:**
- `next.config.js`, `.eslintrc.json`, `yarn.lock`
- `pages/` inteiro (após migração), incluindo `pages/_app.js`, `pages/api/hello.js`, `pages/index.js`, `pages/public/`
- `components/layout.js`, `components/layout.module.css`→mantido, `components/Bird.js`, `pages/three/birds.js`

---

## Task 1: Camada leve de processo (P0)

**Files:**
- Create: `.github/ISSUE_TEMPLATE/epic.yml`, `.github/ISSUE_TEMPLATE/feature.yml`, `.github/ISSUE_TEMPLATE/task.yml`, `.github/ISSUE_TEMPLATE/bug.yml`, `.github/ISSUE_TEMPLATE/config.yml`
- Create: `.github/pull_request_template.md`
- Create: `AGENTS.md`, `docs/project/WORKFLOW.md`

**Interfaces:**
- Consumes: nada.
- Produces: convenções que todas as tarefas seguintes usam (WORKFLOW/campos `Closes #`).

- [ ] **Step 1: Criar os templates de issue**

`.github/ISSUE_TEMPLATE/epic.yml`:
```yaml
name: Epic
description: Defina um resultado de produto e organize suas sub-issues.
title: "EPIC — "
labels:
  - epic
body:
  - type: markdown
    attributes:
      value: |
        Epics descrevem resultados e limites. Depois de criar esta issue, relacione o trabalho executável como sub-issues nativas.
  - type: textarea
    id: problem
    attributes:
      label: Problema
      description: Qual problema existe, para quem e por que importa agora?
      placeholder: Descreva a situação atual e o impacto.
    validations:
      required: true
  - type: textarea
    id: outcome
    attributes:
      label: Resultado esperado
      description: Que mudança observável esta epic deve produzir?
      placeholder: Ao concluir esta epic...
    validations:
      required: true
  - type: textarea
    id: success
    attributes:
      label: Medidas de sucesso
      placeholder: Inclua métricas ou evidências observáveis.
    validations:
      required: true
  - type: textarea
    id: in_scope
    attributes:
      label: Dentro do escopo
      placeholder: Liste os resultados e capacidades incluídos.
    validations:
      required: true
  - type: textarea
    id: out_of_scope
    attributes:
      label: Fora do escopo
      placeholder: Liste limites e adiamentos explícitos.
    validations:
      required: true
  - type: textarea
    id: done
    attributes:
      label: Critérios de conclusão
      placeholder: "- [ ] Resultado demonstrado por..."
    validations:
      required: true
  - type: textarea
    id: dependencies
    attributes:
      label: Dependências e riscos
      placeholder: Use "Nenhum conhecido" quando aplicável.
    validations:
      required: true
```

`.github/ISSUE_TEMPLATE/feature.yml`:
```yaml
name: Feature
description: Proponha uma entrega de valor vinculada a uma epic.
labels:
  - enhancement
body:
  - type: markdown
    attributes:
      value: |
        Crie esta feature como sub-issue nativa da epic correspondente. O vínculo nativo é a fonte de verdade da hierarquia.
  - type: textarea
    id: context
    attributes:
      label: Contexto e objetivo
      placeholder: Como usuário..., quero..., para...
    validations:
      required: true
  - type: textarea
    id: acceptance
    attributes:
      label: Critérios de aceite
      placeholder: "- [ ] Dado..., quando..., então..."
    validations:
      required: true
  - type: textarea
    id: out_of_scope
    attributes:
      label: Fora do escopo
      placeholder: Liste o que esta entrega não cobre.
    validations:
      required: true
  - type: textarea
    id: technical_notes
    attributes:
      label: Notas técnicas
  - type: textarea
    id: verification
    attributes:
      label: Plano de verificação
      placeholder: Testes automatizados, verificações manuais e evidências esperadas.
    validations:
      required: true
  - type: textarea
    id: dependencies
    attributes:
      label: Dependências
      placeholder: Issues bloqueadoras ou "Nenhuma".
    validations:
      required: true
```

`.github/ISSUE_TEMPLATE/task.yml`:
```yaml
name: Task
description: Registre um trabalho técnico pequeno e verificável.
labels:
  - task
body:
  - type: markdown
    attributes:
      value: |
        Crie esta task como sub-issue nativa da epic correspondente.
  - type: textarea
    id: objective
    attributes:
      label: Objetivo
      description: Qual resultado técnico concreto deve ser produzido?
    validations:
      required: true
  - type: textarea
    id: acceptance
    attributes:
      label: Critérios de aceite
      placeholder: "- [ ] Resultado verificável"
    validations:
      required: true
  - type: textarea
    id: out_of_scope
    attributes:
      label: Fora do escopo
      placeholder: Limites desta task.
    validations:
      required: true
  - type: textarea
    id: approach
    attributes:
      label: Notas de implementação
  - type: textarea
    id: verification
    attributes:
      label: Plano de verificação
      placeholder: Comandos, testes e evidências esperadas.
    validations:
      required: true
  - type: textarea
    id: dependencies
    attributes:
      label: Dependências
      placeholder: Issues bloqueadoras ou "Nenhuma".
    validations:
      required: true
```

`.github/ISSUE_TEMPLATE/bug.yml`:
```yaml
name: Bug
description: Relate um comportamento incorreto e reproduzível.
title: "BUG — "
labels:
  - bug
body:
  - type: markdown
    attributes:
      value: |
        Crie este bug como sub-issue nativa da epic correspondente.
  - type: textarea
    id: impact
    attributes:
      label: Impacto
      description: Quem é afetado, com que frequência e gravidade?
    validations:
      required: true
  - type: textarea
    id: reproduction
    attributes:
      label: Como reproduzir
      placeholder: |
        1. Dado...
        2. Quando...
        3. Então...
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: Comportamento esperado
    validations:
      required: true
  - type: textarea
    id: actual
    attributes:
      label: Comportamento atual
    validations:
      required: true
  - type: textarea
    id: environment
    attributes:
      label: Ambiente
    validations:
      required: true
  - type: textarea
    id: evidence
    attributes:
      label: Evidências
      description: Logs sem segredos, capturas, vídeos ou links relevantes.
  - type: textarea
    id: acceptance
    attributes:
      label: Critérios de aceite da correção
      placeholder: "- [ ] O cenário de reprodução deixa de falhar\n- [ ] Existe cobertura contra regressão"
    validations:
      required: true
  - type: textarea
    id: verification
    attributes:
      label: Plano de verificação
    validations:
      required: true
```

`.github/ISSUE_TEMPLATE/config.yml`:
```yaml
blank_issues_enabled: false
contact_links: []
```

- [ ] **Step 2: Criar o template de PR**

`.github/pull_request_template.md`:
```markdown
## Issues

Closes #
Epic-pai: #

## Resumo

<!-- Explique o resultado entregue e por que esta mudança é necessária. -->

## Alterações

<!-- Liste as mudanças relevantes sem repetir os critérios da issue. -->

## Verificação

<!-- Registre comandos e resultados atuais, além de verificações manuais. -->

- [ ] Critérios de aceite demonstrados
- [ ] Verificações relevantes executadas
- [ ] Fluxos afetados verificados manualmente quando necessário

## Evidências

<!-- Capturas, logs sem segredos, resultados ou links que sustentam a verificação. -->

## Riscos e limitações

<!-- Inclua impacto, rollback e lacunas de verificação. Use "Nenhum conhecido" quando aplicável. -->

## Follow-ups

<!-- Referencie novas issues. Não deixe trabalho pendente apenas como texto nesta PR. -->

## Checklist

- [ ] A PR trata uma única sub-issue executável
- [ ] A sub-issue e a epic-pai estão vinculadas
- [ ] Documentação afetada foi atualizada
- [ ] Não há segredos, dados pessoais ou artefatos temporários no diff
```

- [ ] **Step 3: Criar `AGENTS.md` e o WORKFLOW curto**

`AGENTS.md`:
```markdown
# Regras do repositório

- Para qualquer issue, epic, mudança planejada, branch, pull request, handoff ou decisão de conclusão, leia e siga `docs/project/WORKFLOW.md` antes de agir.
- Este é um site estático publicado no Cloudflare Pages. Não adicione API routes ao site; a API de IA vive em `ai/` (Worker) a partir do P2.
- Ao criar commits, use apenas a identidade Git existente do repositório.
- Nunca adicione ferramentas de IA, assistentes, modelos ou automação como autor, coautor, contribuidor ou atribuição em commits, trailers, PRs ou metadados gerados.
- Nunca grave segredos no repositório.
- Verificações obrigatórias antes de concluir: `npm run build` e `npm run typecheck`.
```

`docs/project/WORKFLOW.md`:
```markdown
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

- A decisão de merge é do mantenedor; faça merge somente sob pedido explícito.
- Feche sub-issues de código pela PR com `Closes #<numero>`.
- Registre follow-ups como novas sub-issues.
```

- [ ] **Step 4: Validar o YAML e commitar**

Run:
```powershell
node -e "const fs=require('fs');for(const f of fs.readdirSync('.github/ISSUE_TEMPLATE')){const t=fs.readFileSync('.github/ISSUE_TEMPLATE/'+f,'utf8');if(!/^(name|blank_issues_enabled)/m.test(t))throw new Error('bad '+f)}console.log('templates ok')"
```
Expected: `templates ok`

Run:
```powershell
git add .github AGENTS.md docs/project/WORKFLOW.md
git commit -m "docs: camada leve de processo (epics, features, tasks, bugs)"
```
Expected: commit criado.

---

## Task 2: Toolchain, shell do App Router e home

**Files:**
- Modify: `package.json`
- Create: `next.config.mjs`, `tsconfig.json`, `app/layout.tsx`, `app/page.tsx`
- Move: `pages/public/*` → `public/*`
- Delete: `next.config.js`, `.eslintrc.json`, `yarn.lock`, `pages/index.js`, `pages/three/birds.js`, `components/Bird.js`
- Modify: `pages/three/boxes.js` (imports R3F), `pages/posts/first-post.js` (remover link de Birds), `.gitignore`

**Interfaces:**
- Consumes: nada.
- Produces: `PageShell` (default export, `{ children }`), pacote `@react-three/fiber` disponível, `public/` correto na raiz.

- [ ] **Step 1: Reescrever `package.json`**

```json
{
  "name": "pvsdev",
  "version": "0.2.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "typecheck": "tsc --noEmit",
    "format": "prettier --write .",
    "deploy": "wrangler pages deploy out --project-name pvsouza --branch main --commit-dirty=true"
  },
  "dependencies": {
    "@react-three/drei": "^10.0.0",
    "@react-three/fiber": "^9.0.0",
    "next": "^15.5.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "react-icons": "^5.0.0",
    "three": "^0.180.0"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@types/three": "^0.180.0",
    "prettier": "^3.0.0",
    "typescript": "^5.6.0",
    "wrangler": "^4.0.0"
  }
}
```

- [ ] **Step 2: Instalar dependências**

Run:
```powershell
Remove-Item -LiteralPath yarn.lock -ErrorAction SilentlyContinue
npm install
```
Expected: instala sem erro; `package-lock.json` criado.

- [ ] **Step 3: Criar `next.config.mjs`, `tsconfig.json` e remover configs antigas**

`next.config.mjs`:
```js
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
};

export default nextConfig;
```

`tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules", "out", ".next", "ai"]
}
```

Run:
```powershell
Remove-Item -LiteralPath next.config.js, .eslintrc.json -ErrorAction SilentlyContinue
```
Expected: arquivos removidos.

- [ ] **Step 4: Mover os assets de `pages/public` para `public`**

Run:
```powershell
git mv pages/public public
```
Expected: `public/glb/*.glb`, `public/images/profile.jpg`, `public/favicon.ico`, `public/vercel.svg`.

- [ ] **Step 5: Criar `app/layout.tsx` e `components/PageShell.tsx`**

`app/layout.tsx`:
```tsx
import type { Metadata } from 'next';
import '@/styles/globals.css';

export const metadata: Metadata = {
  title: 'PVS DEV',
  description: 'Paulo Vitor Souza — Software Developer',
  icons: { icon: '/favicon.ico' },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
```

`components/PageShell.tsx`:
```tsx
import styles from '@/components/layout.module.css';

export default function PageShell({
  children,
}: {
  children: React.ReactNode;
}) {
  return <div className={styles.container}>{children}</div>;
}
```

- [ ] **Step 6: Criar `app/page.tsx` (home)**

```tsx
import Link from 'next/link';
import styles from '@/styles/Home.module.css';

export default function Home() {
  return (
    <div className={styles.container}>
      <main className={styles.main}>
        <h1 className={styles.title}>Paulo Vitor Souza</h1>

        <p className={styles.description}>Software Developer</p>

        <div className={styles.grid}>
          <a href="" className={styles.card}>
            <h3>Portfolio &rarr;</h3>
            <p>Veja os projetos que participei</p>
            <p>-- em breve --</p>
          </a>

          <Link href="/posts/rants" className={styles.card}>
            <h3>Rants &rarr;</h3>
            <p>Discutindo sobre tudo e todos.</p>
          </Link>

          <Link href="/posts/about-me" className={styles.card}>
            <h3>Sobre mim &rarr;</h3>
            <p>Descubra mais sobre mim.</p>
          </Link>

          <Link href="/posts/first-post" className={styles.card}>
            <h3>Testes &rarr;</h3>
            <p>Testes realizados com three.js e outras tecnologias</p>
          </Link>
        </div>
      </main>

      <footer className={styles.footer}>
        <a
          href="https://www.youtube.com/watch?v=pVpMWi-x1GY"
          target="_blank"
          rel="noopener noreferrer"
        >
          Quero me tornar uma pessoa gentil
        </a>
      </footer>
    </div>
  );
}
```

- [ ] **Step 7: Remover a rota antiga da home e ajustar o three.js remanescente**

Run:
```powershell
git rm pages/index.js pages/three/birds.js components/Bird.js
```
Expected: arquivos removidos. (`pages/_app.js` permanece até a Task 3.)

Substituir todo o conteúdo de `pages/three/boxes.js` por (migração de imports + keys):
```jsx
import { useRef, useState } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls, Box } from '@react-three/drei';

const MyBox = (props) => {
  const mesh = useRef();

  const [hovered, setHover] = useState(false);
  const [active, setActive] = useState(false);

  useFrame(() => {
    if (mesh.current) mesh.current.rotation.x = mesh.current.rotation.y += 0.01;
  });

  return (
    <Box
      args={[1, 1, 1]}
      {...props}
      ref={mesh}
      scale={active ? [6, 6, 6] : [5, 5, 5]}
      onClick={() => setActive(!active)}
      onPointerOver={() => setHover(true)}
      onPointerOut={() => setHover(false)}
    >
      <meshStandardMaterial color={hovered ? '#2b6c76' : '#720b23'} />
    </Box>
  );
};

const BoxesPage = () => {
  return (
    <>
      <h1>Click on me - Hover me :)</h1>
      <Canvas camera={{ position: [0, 0, 35] }}>
        <ambientLight intensity={2} />
        <pointLight position={[40, 40, 40]} />
        <MyBox position={[10, 0, 0]} />
        <MyBox position={[-10, 0, 0]} />
        <MyBox position={[0, 10, 0]} />
        <MyBox position={[0, -10, 0]} />
        <OrbitControls />
      </Canvas>
    </>
  );
};

export default BoxesPage;
```

Editar `pages/posts/first-post.js`: remover o bloco do card de Birds:
```jsx
        <a className={styles.card}>
          <Link href="/three/birds" >
            <h3> Birds </h3>
          </Link>
        </a>
```

- [ ] **Step 8: Atualizar `.gitignore`**

Adicionar ao final de `.gitignore`:
```
# cloudflare
/.wrangler/
```

- [ ] **Step 9: Buildar e verificar**

Run:
```powershell
npm run build
```
Expected: `Compiled successfully`; rotas `/`, `/posts/*`, `/three/*` listadas; sem erro de módulo.

Run:
```powershell
npm run typecheck
```
Expected: sem erros.

- [ ] **Step 10: Commit**

Run:
```powershell
git add -A
git commit -m "chore: migra para Next 15 + App Router (home), R3F v9 e assets na raiz public"
```
Expected: commit criado.

---

## Task 3: Migrar páginas de conteúdo para o App Router

**Files:**
- Create: `app/posts/about-me/page.tsx`, `app/posts/rants/page.tsx`, `app/posts/art/page.js`, `app/posts/first-post/page.tsx`
- Delete: `pages/posts/`, `pages/_app.js`

**Interfaces:**
- Consumes: `PageShell` de `@/components/PageShell` (Task 2).
- Produces: rotas `/posts/about-me`, `/posts/rants`, `/posts/art`, `/posts/first-post`.

- [ ] **Step 1: Criar `app/posts/about-me/page.tsx`**

```tsx
import Link from 'next/link';
import PageShell from '@/components/PageShell';
import styles from '@/styles/Home.module.css';

const manhwas = [
  { name: 'Undefeatable Swordsman', href: 'https://undefeatableswordsman.com/' },
  { name: 'Arcane Sniper', href: 'https://arcanesniper.com/' },
  {
    name: 'Mookhyang Dark lady',
    href: 'https://luminousscans.com/series/1653732347-mookhyang-dark-lady-isekai/',
  },
  {
    name: 'A returners magic should be special',
    href: 'https://flamescans.org/series/1654747321-a-returners-magic-should-be-special/',
  },
  {
    name: 'Max level hero returner',
    href: 'https://flamescans.org/series/1654747321-max-level-returner/',
  },
  { name: 'Dungeon reset', href: 'https://flamescans.org/series/1654747321-dungeon-reset/' },
  { name: 'Kenja no mago', href: 'https://read.kenjanomago.com/' },
  { name: 'legend of northern blade', href: 'https://legendofnorthernblade.com/' },
  { name: 'Volcanic age', href: 'https://luminousscans.com/series/1653732347-volcanic-age/' },
];

export const metadata = { title: 'Sobre mim' };

export default function AboutMe() {
  return (
    <PageShell>
      <div className={styles.grid}>
        <div className={styles.card}>
          <h2>Hobbies</h2>
          <div>
            Desce criança sempre gostei muito de ler, especialmente mangas (Japão).
            Ultimamente, venho lendo muitos Manhuas (China) e Manhwas (Coréia).
          </div>
        </div>

        {manhwas.map((item) => (
          <a key={item.href} href={item.href} className={styles.card}>
            <h2>{item.name}</h2>
            <div>{item.href}</div>
          </a>
        ))}
      </div>

      <h2>
        <Link href="/">&larr; Back to home</Link>
      </h2>
    </PageShell>
  );
}
```

- [ ] **Step 2: Criar `app/posts/rants/page.tsx`**

```tsx
import Link from 'next/link';
import PageShell from '@/components/PageShell';
import styles from '@/styles/Home.module.css';

export const metadata = { title: 'Rant' };

export default function Rant() {
  return (
    <PageShell>
      <div className={styles.grid}>
        <div className={styles.card}>
          <h2>Inoue</h2>
          <div>
            Seguir em frente é como tatear no escuro. <br />
            A luz que brilha ao longe é frágil e incerta. <br />
            Mas a luz interna, essa sim, se agita loucamente. <br />
            Quero sempre me sentir desse jeito. <br />
          </div>
        </div>
      </div>

      <h2>
        <Link href="/">&larr; Back to home</Link>
      </h2>
    </PageShell>
  );
}
```

- [ ] **Step 3: Criar `app/posts/first-post/page.tsx`**

```tsx
import Link from 'next/link';
import PageShell from '@/components/PageShell';
import styles from '@/styles/Home.module.css';

export const metadata = { title: 'First Post' };

export default function FirstPost() {
  return (
    <PageShell>
      <div className={styles.grid}>
        <Link href="/" className={styles.card}>
          <h2>Back to home</h2>
        </Link>

        <Link href="/three/boxes" className={styles.card}>
          <h3>Boxes</h3>
        </Link>

        <Link href="/posts/art" className={styles.card}>
          <h3>Clique aqui</h3>
        </Link>
      </div>
    </PageShell>
  );
}
```

- [ ] **Step 4: Mover a página `art` sem alterar o conteúdo**

Run:
```powershell
New-Item -ItemType Directory -Force -Path app/posts/art | Out-Null
git mv pages/posts/art.js app/posts/art/page.js
```
Expected: `app/posts/art/page.js` contém o `<pre><code>` original, inalterado.

- [ ] **Step 5: Remover as páginas antigas e o `_app`**

Run:
```powershell
git rm pages/posts/about-me.js pages/posts/rants.js pages/posts/first-post.js pages/_app.js
```
Expected: removidos. A pasta `pages/` agora contém apenas `api/` e `three/`.

- [ ] **Step 6: Buildar e verificar**

Run:
```powershell
npm run build
```
Expected: rotas `/posts/about-me`, `/posts/rants`, `/posts/art`, `/posts/first-post` geradas; nenhum conflito de rota.

- [ ] **Step 7: Commit**

Run:
```powershell
git add -A
git commit -m "feat: migra paginas de conteudo para o App Router"
```
Expected: commit criado.

---

## Task 4: Migrar o demo `boxes` para o App Router

**Files:**
- Create: `app/three/boxes/page.tsx`, `components/BoxesScene.tsx`, `components/BoxesCanvas.tsx`
- Delete: `pages/three/`, `components/layout.js`

**Interfaces:**
- Consumes: `@react-three/fiber` v9, `@react-three/drei` v10 (Task 2).
- Produces: rota `/three/boxes`.

- [ ] **Step 1: Criar `components/BoxesCanvas.tsx`**

```tsx
'use client';

import { useRef, useState } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls, Box } from '@react-three/drei';

function MyBox(props: Record<string, unknown>) {
  const mesh = useRef<any>(null);
  const [hovered, setHover] = useState(false);
  const [active, setActive] = useState(false);

  useFrame(() => {
    if (mesh.current) mesh.current.rotation.x = mesh.current.rotation.y += 0.01;
  });

  return (
    <Box
      args={[1, 1, 1]}
      {...(props as any)}
      ref={mesh}
      scale={active ? [6, 6, 6] : [5, 5, 5]}
      onClick={() => setActive(!active)}
      onPointerOver={() => setHover(true)}
      onPointerOut={() => setHover(false)}
    >
      <meshStandardMaterial color={hovered ? '#2b6c76' : '#720b23'} />
    </Box>
  );
}

export default function BoxesCanvas() {
  return (
    <Canvas camera={{ position: [0, 0, 35] }}>
      <ambientLight intensity={2} />
      <pointLight position={[40, 40, 40]} />
      <MyBox position={[10, 0, 0]} />
      <MyBox position={[-10, 0, 0]} />
      <MyBox position={[0, 10, 0]} />
      <MyBox position={[0, -10, 0]} />
      <OrbitControls />
    </Canvas>
  );
}
```

- [ ] **Step 2: Criar `components/BoxesScene.tsx`**

```tsx
'use client';

import dynamic from 'next/dynamic';

const BoxesCanvas = dynamic(() => import('@/components/BoxesCanvas'), {
  ssr: false,
  loading: () => <p>Carregando…</p>,
});

export default function BoxesScene() {
  return <BoxesCanvas />;
}
```

- [ ] **Step 3: Criar `app/three/boxes/page.tsx`**

```tsx
import BoxesScene from '@/components/BoxesScene';

export const metadata = { title: 'Boxes' };

export default function BoxesPage() {
  return (
    <div>
      <h1>Click on me - Hover me :)</h1>
      <BoxesScene />
    </div>
  );
}
```

- [ ] **Step 4: Remover a rota antiga e o layout obsoleto**

Run:
```powershell
git rm pages/three/boxes.js components/layout.js
```
Expected: `pages/three` vazio/removido; `components/layout.module.css` permanece (usado por `PageShell`).

- [ ] **Step 5: Buildar e verificar**

Run:
```powershell
npm run build
```
Expected: rota `/three/boxes` gerada; sem erro de `ssr: false`.

- [ ] **Step 6: Commit**

Run:
```powershell
git add -A
git commit -m "feat: migra demo boxes para o App Router com React 19"
```
Expected: commit criado.

---

## Task 5: Finalizar o export estático

**Files:**
- Modify: `next.config.mjs`, `.gitignore`
- Delete: `pages/api/`, `pages/` (remanescente)

**Interfaces:**
- Consumes: todas as rotas migradas (Tasks 2–4).
- Produces: pasta `out/` pronta para o Pages.

- [ ] **Step 1: Remover a API route e a pasta `pages`**

Run:
```powershell
git rm pages/api/hello.js
Remove-Item -LiteralPath pages -Recurse -Force -ErrorAction SilentlyContinue
```
Expected: `pages/` não existe mais; `Test-Path pages` retorna `False`.

- [ ] **Step 2: Ativar o export estático**

`next.config.mjs`:
```js
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  trailingSlash: true,
  images: { unoptimized: true },
  reactStrictMode: true,
};

export default nextConfig;
```

- [ ] **Step 3: Buildar o export**

Run:
```powershell
npm run build
```
Expected: mensagem de export estático; pasta `out/` criada com `out/index.html`, `out/posts/about-me/index.html`, `out/three/boxes/index.html`.

Run:
```powershell
Test-Path out/index.html, out/posts/about-me/index.html, out/three/boxes/index.html, out/404.html
```
Expected: quatro vezes `True`.

- [ ] **Step 4: Confirmar que não há API routes nem `pages/` no build**

Run:
```powershell
Test-Path pages; Test-Path out/api
```
Expected: `False` e `False`.

- [ ] **Step 5: Commit**

Run:
```powershell
git add -A
git commit -m "build: ativa export estatico e remove o Pages Router"
```
Expected: commit criado.

---

## Task 6: Criar o projeto Pages e publicar

**Files:**
- Create: `scripts/smoke.ps1`
- Modify: `.gitignore` (garantir `out/` ignorado)

**Interfaces:**
- Consumes: `out/` (Task 5), Wrangler autenticado.
- Produces: URL `https://pvsouza.pages.dev`; projeto `pvsouza`.

- [ ] **Step 1: Criar o script de smoke**

`scripts/smoke.ps1`:
```powershell
param(
  [Parameter(Mandatory = $true)][string]$BaseUrl
)
$ErrorActionPreference = 'Stop'
$urls = @('/', '/posts/about-me/', '/posts/rants/', '/posts/first-post/', '/three/boxes/')
foreach ($path in $urls) {
  $url = "$BaseUrl$path"
  $status = (curl.exe -s -o NUL -w "%{http_code}" $url)
  Write-Output "$status  $url"
  if ($status -ne '200') { throw "Falha em $url ($status)" }
}
Write-Output 'smoke ok'
```

- [ ] **Step 2: Confirmar a conta e publicar**

Run:
```powershell
npx wrangler whoami
```
Expected: conta `Paulo225vitor@gmail.com's Account` listada.

Run:
```powershell
npm run build
npx wrangler pages deploy out --project-name pvsouza --branch main --commit-dirty=true
```
Expected: primeira execução cria o projeto `pvsouza` e imprime a URL de deployment; resultado com `Deployment complete` e host `pvsouza.pages.dev`.

- [ ] **Step 3: Rodar o smoke no domínio Pages**

Run:
```powershell
powershell -NoProfile -File scripts/smoke.ps1 -BaseUrl https://pvsouza.pages.dev
```
Expected: cinco linhas `200` e `smoke ok`.

- [ ] **Step 4: Commit**

Run:
```powershell
git add scripts/smoke.ps1 .gitignore
git commit -m "chore: adiciona smoke test e ignora artefatos do wrangler"
```
Expected: commit criado.

---

## Task 7: Domínio `pvsouza.com`, `www` e verificação final

**Files:** nenhum (configuração no Cloudflare).

**Interfaces:**
- Consumes: projeto `pvsouza` publicado (Task 6).
- Produces: `https://pvsouza.com` servindo o site; `www` redirecionando para o apex.

- [ ] **Step 1 (humano): Associar os domínios no Pages**

No dashboard Cloudflare → **Workers & Pages** → `pvsouza` → **Custom domains**:
1. **Set up a domain** → `pvsouza.com` → confirmar. (Cloudflare cria o registro do apex automaticamente por estar na mesma conta.)
2. **Set up a domain** → `www.pvsouza.com` → confirmar.

Expected: ambos aparecem como `Active`/`Initializing`.

- [ ] **Step 2 (humano): Redirecionar `www` para o apex**

No dashboard → `pvsouza.com` → **Rules** → **Redirect Rules** → criar:
- Nome: `www → apex`
- When incoming requests match: `Hostname equals www.pvsouza.com`
- Then: **Dynamic redirect**, Expression `concat("https://pvsouza.com", http.request.uri.path)`, Status `301`.

Expected: regra salva e ativa.

- [ ] **Step 3: Verificar o DNS**

Run:
```powershell
Resolve-DnsName pvsouza.com -Type A
Resolve-DnsName www.pvsouza.com
```
Expected: `pvsouza.com` retorna `A`/`AAAA` (não apenas `SOA`); `www` resolve.

- [ ] **Step 4: Verificar HTTP/HTTPS e redirect**

Run:
```powershell
curl.exe -sI https://pvsouza.com | Select-String -Pattern "HTTP/|location:"
curl.exe -sI https://www.pvsouza.com | Select-String -Pattern "HTTP/|location:"
```
Expected: apex `HTTP/2 200` (ou `307`→`200` com Always Use HTTPS); `www` `HTTP/2 301` com `location: https://pvsouza.com/...`.

- [ ] **Step 5: Smoke final no domínio canônico**

Run:
```powershell
powershell -NoProfile -File scripts/smoke.ps1 -BaseUrl https://pvsouza.com
```
Expected: cinco linhas `200` e `smoke ok`.

- [ ] **Step 6 (humano): Registrar o resultado na spec**

Atualizar `docs/superpowers/specs/2026-09-17-pvsouza-p1-deploy-design.md` marcando P1 como concluído e anexar a saída do smoke. Commit:
```powershell
git add docs/superpowers/specs/2026-09-17-pvsouza-p1-deploy-design.md
git commit -m "docs: registra conclusao do P1 (deploy em pvsouza.com)"
```
Expected: commit criado.

---

## Follow-ups (criar como sub-issues, não implementar aqui)

1. **Demo `birds` (three.js)** — reintroduzir com `@react-three/fiber` v9 + `GLTFLoader`, animação via `AnimationMixer`. Foi adiado por risco de upgrade.
2. **ESLint + Prettier no CI** — config flat do Next e checagem em PR.
3. **Deploy automatizado** — GitHub Action publicando `out/` no Pages a cada push em `main`.
4. **P2 — Chat v1** — Worker de IA com streaming.
5. **P3 — RAG playground**.
6. **P4 — Artefatos v2**.

## Self-Review

- **Cobertura da spec:** §5.1 framework→Tasks 2–5; §5.2 estrutura→Files; §5.3 deploy→Tasks 6–7; §5.4 conteúdo→Tasks 2–4 (com adiamento do `birds`, previsto na mitigação §5.6); §5.5 verificação→smoke/DNS/curl; §7 processo→Task 1.
- **Placeholders:** nenhum "TBD"; todo passo traz comando/código e saída esperada.
- **Consistência de tipos:** `PageShell` e `BoxesScene`/`BoxesCanvas` com nomes únicos; alias `@/*` definido no `tsconfig` e usado consistentemente.
