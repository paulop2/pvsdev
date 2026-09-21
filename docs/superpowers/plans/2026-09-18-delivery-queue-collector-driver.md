# Delivery Queue — Collector & Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar o coletor `Get-QueueSnapshot.ps1` que produz o snapshot consumido pelo resolver, e o driver `Deliver-Queue.ps1` (lock, recuperação, despacho, gate, merge e resumo) com os agentes e o comando `delivery-queue-deliver-issue`, conforme a spec v2.1 seções 7-9.

**Architecture:** O coletor separa orquestração pura de I/O: `New-QueueSnapshot` recebe um adapter (`$Gh`) injetável e devolve um snapshot no formato exato que `Resolve-QueuePlan` consome; o CLI monta o adapter real sobre `gh`/`git`. O driver separa decisão pura (preflight, seleção de ação, contrato de evidências, gate, código de saída) da orquestração com efeitos, que recebe um adapter (`$Io`) injetável; o CLI monta o adapter real sobre `gh`/`git`/`opencode`. Toda a lógica de decisão é coberta por Pester com adapters falsos; o smoke E2E real fica como checklist manual.

**Tech Stack:** Windows PowerShell 5.1 (não há `pwsh`), Pester 6.2.0 (escopo CurrentUser), `ConvertFrom-Json`/`ConvertTo-Json`, `gh`, `git`, `opencode`.

**Spec:** `docs/superpowers/specs/2026-09-17-fila-de-issues-autonoma-design.md` (v2.1), seções 5-9 e 11.

## Global Constraints

- Runtime: **Windows PowerShell 5.1**. Nenhum código pode depender do PowerShell 7.
- Testes: **Pester 6.2.0**, `Invoke-Pester -Path "delivery-queue/tests"`.
- `Set-StrictMode -Version Latest` em todo arquivo de `src/`.
- `Get-Prop` é obrigatório para leitura de propriedade opcional sob StrictMode. `Get-Array` normaliza ausente/nulo para array real; **nunca** envolver o resultado em `@(...)` (o `,@()` de `Get-Array` aninharia). Em PS 5.1 `return @()` vira `$null`; devolver array vazio como `,@()`.
- `Write-Error` sob `$ErrorActionPreference='Stop'` lança e impede `exit`; usar `[Console]::Error.WriteLine(...)` seguido de `exit`.
- Fixtures e strings de teste em **ASCII puro** (sem acento). Arquivos JSON de fixture lidos com `-Encoding UTF8`.
- **Sem comentários no código-fonte.**
- Puro = sem rede, sem shell, sem disco, sem ambiente. `DeliveryQueue.Resolver.ps1` permanece puro e não é modificado por este plano.
- Adapters são `[pscustomobject]` com propriedades `ScriptBlock`; chamadas usam `& $Adapter.Method -Arg valor`.
- Identidade de issue: `"<owner>/<repo>#<number>"`.
- Códigos de saída do driver (spec seção 8): `4` infraestrutura, `130` cancelado, `3` falhou, `2` bloqueado/aguardando, `1` limite, `0` tudo pronto/sem trabalho.
- `mergeMode: auto` sem `merge.authorizedByLocalRules: true` bloqueia antes do despacho.
- Dado necessário desconhecido é gate; nunca tratar ausência como lista vazia.
- `Get-QueueSnapshot.ps1` e `Deliver-Queue.ps1` não são adicionados a API routes do site Next; o pacote é autocontido em `delivery-queue/`.

## File Structure

```text
delivery-queue/
├── src/
│   ├── DeliveryQueue.Resolver.ps1       (existente, puro, NAO modificar)
│   ├── Resolve-Queue.ps1                (existente)
│   ├── DeliveryQueue.Pages.ps1          (novo, puro: Get-PagedItems)
│   ├── DeliveryQueue.Attempt.ps1        (novo, puro: render/parse/selecao do comentario de tentativa)
│   ├── DeliveryQueue.Common.ps1         (novo, puro: carregar policy, checagens de forma)
│   ├── DeliveryQueue.Lock.ps1           (novo, efeito: lock de SO por repositorio)
│   ├── DeliveryQueue.Collector.ps1      (novo: New-QueueSnapshot e helpers com adapter $Gh)
│   ├── Get-QueueSnapshot.ps1            (novo CLI: monta adapter real, escreve snapshot)
│   ├── DeliveryQueue.DriverCore.ps1     (novo, puro: preflight, acao, gate, resumo, exit code)
│   ├── DeliveryQueue.Driver.ps1         (novo: Invoke-DeliveryLoop com adapter $Io)
│   ├── Deliver-Queue.ps1                (novo CLI: adapter real, lock, exit codes)
│   ├── DeliveryQueue.Gh.ps1             (novo: adapter real gh/git)
│   └── DeliveryQueue.Io.ps1             (novo: adapter real de efeitos do driver)
├── agents/
│   ├── delivery-queue-worker.md
│   ├── delivery-queue-reviewer.md
│   └── delivery-queue-fixer.md
├── commands/
│   └── delivery-queue-deliver-issue.md
├── schema/
│   └── policy-v1.json
└── tests/
    ├── TestHelpers.ps1                  (fakes compartilhados; NAO e *.Tests.ps1)
    ├── DeliveryQueue.Pages.Tests.ps1
    ├── DeliveryQueue.Attempt.Tests.ps1
    ├── DeliveryQueue.Lock.Tests.ps1
    ├── DeliveryQueue.Collector.Tests.ps1
    ├── DeliveryQueue.CollectorCli.Tests.ps1
    ├── DeliveryQueue.DriverCore.Tests.ps1
    ├── DeliveryQueue.Gate.Tests.ps1
    ├── DeliveryQueue.DriverLoop.Tests.ps1
    └── DeliveryQueue.DriverCli.Tests.ps1
```

### Contrato do adapter `$Gh` (coletor)

| Metodo | Entrada | Saida |
| --- | --- | --- |
| `GetDefaultBranch` | `-Repository` | `{ name; headSha }` |
| `GetSubIssues` | `-Repository -Epic` | `[ { number; nodeId; title; state; stateReason; labels; blockedBy } ]` (so sub-issues diretas) |
| `GetProjectState` | `-Owner -Number -NodeId` | `{ found; state }` |
| `GetIssueComments` | `-Repository -Issue` | `[string]` corpos |
| `GetIssuePrs` | `-Repository -Issue` | `[ { number; state; isDraft; baseRefName; headRefName; headSha; url; hasConflict; checks; checksKnown } ]` |
| `GetBlockerIssues` | `-Repository -Ids` | hashtable `id -> { state; stateReason }` |
| `GetRefSha` | `-Ref` | string ou `$null` |

`GetSubIssues`, `GetIssueComments` e `GetIssuePrs` retornam a lista **completa** (o adapter real pagina internamente com `Get-PagedItems`); qualquer falha de coleta lança. `checks` e `[ { context; conclusion } ]`; `checksKnown=$false` significa que os checks remotos nao puderam ser lidos.

### Contrato do adapter `$Io` (driver)

| Metodo | Entrada | Saida |
| --- | --- | --- |
| `GetNow` | — | ISO-8601 string |
| `Log` | `-Message` | — |
| `Collect` | `-Repository -Epic -Only` | snapshot do coletor |
| `GetDefaultHead` | `-Repository -Branch` | sha |
| `FetchDefault` | `-Repository -Branch` | sha |
| `AcquireLock` | `-Repository` | handle de lock |
| `ReleaseLock` | `-Lock` | — |
| `EnsureWorktree` | `-Repository -Branch -Base -Root` | `{ path; branch }` |
| `FindAttemptComment` | `-Repository -Issue -AttemptId` | commentId ou `$null` |
| `UpsertComment` | `-Repository -Issue -Body -CommentId` | commentId |
| `DispatchWorker` | `-Issue -Repository -Base -Worktree -TimeoutMinutes` | `{ exitCode; timedOut; output }` |
| `GetPr` | `-Repository -Number` | pr (mesma forma de `GetIssuePrs`) |
| `GetRemoteChecks` | `-Repository -HeadSha` | `[ { context; conclusion } ]` |
| `RunLocalChecks` | `-Worktree -Commands` | `[ { command; result; headSha; at } ]` |
| `MergePr` | `-Repository -Number -Method -HeadSha -AllowAdmin` | `{ state; mergeCommit; mergedAt }` |
| `VerifyPostMerge` | `-Repository -Branch -Commands` | `{ baseSha; result; at }` |
| `WriteSummary` | `-Text` | — |

`acceptedChecks` (spec secao 7): conclusoes nao bloqueantes sao `SUCCESS`, `NEUTRAL`, `SKIPPED`; pendente/ausente/falhando bloqueiam.

---

### Task 1: Paginacao generica

**Files:**
- Create: `delivery-queue/src/DeliveryQueue.Pages.ps1`
- Test: `delivery-queue/tests/DeliveryQueue.Pages.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Prop`, `Get-Array` de `DeliveryQueue.Resolver.ps1` (dot-source na frente).
- Produces: `Get-PagedItems -FetchPage <scriptblock> [-MaxPages <int>] -> object[]`. `FetchPage` recebe o cursor (`$null` na primeira pagina) e devolve `{ items; hasNextPage; endCursor }`. Falha de pagina lanca; nao devolve lista parcial.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.Pages.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Pages.ps1"
}

Describe 'Get-PagedItems' {
    It 'junta multiplas paginas' {
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue([pscustomobject]@{ items = @(1, 2); hasNextPage = $true; endCursor = 'c1' })
        $queue.Enqueue([pscustomobject]@{ items = @(3); hasNextPage = $false; endCursor = $null })
        $fetch = { param($cursor) return $queue.Dequeue() }

        $items = Get-PagedItems -FetchPage $fetch
        $items.Count | Should -Be 3
        $items | Should -Be @(1, 2, 3)
    }

    It 'devolve lista vazia quando a unica pagina e vazia' {
        $fetch = { param($cursor) return [pscustomobject]@{ items = @(); hasNextPage = $false; endCursor = $null } }
        (Get-PagedItems -FetchPage $fetch).Count | Should -Be 0
    }

    It 'lanca quando uma pagina falha, sem devolver parcial' {
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue([pscustomobject]@{ items = @(1); hasNextPage = $true; endCursor = 'c1' })
        $fetch = {
            param($cursor)
            if ($queue.Count -gt 0) { return $queue.Dequeue() }
            throw 'falha de rede'
        }
        { Get-PagedItems -FetchPage $fetch } | Should -Throw
    }

    It 'lanca quando hasNextPage e verdadeiro sem cursor' {
        $fetch = { param($cursor) return [pscustomobject]@{ items = @(1); hasNextPage = $true; endCursor = $null } }
        { Get-PagedItems -FetchPage $fetch } | Should -Throw
    }

    It 'lanca ao exceder o teto de paginas' {
        $fetch = { param($cursor) return [pscustomobject]@{ items = @(1); hasNextPage = $true; endCursor = 'x' } }
        { Get-PagedItems -FetchPage $fetch -MaxPages 3 } | Should -Throw
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Pages.Tests.ps1" -Output Detailed`
Expected: FAIL (`DeliveryQueue.Pages.ps1` nao existe).

- [ ] **Step 3: Implementar**

Crie `delivery-queue/src/DeliveryQueue.Pages.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')

function Get-PagedItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock]$FetchPage,
        [int]$MaxPages = 100
    )

    $items = @()
    $cursor = $null
    $page = 0

    while ($true) {
        $page++
        if ($page -gt $MaxPages) {
            throw "paginacao excedeu $MaxPages paginas"
        }

        $result = & $FetchPage $cursor
        if ($null -eq $result) {
            throw 'pagina de coleta ausente'
        }

        $pageItems = Get-Array -Value (Get-Prop -Object $result -Name 'items')
        foreach ($item in $pageItems) { $items += $item }

        $hasNext = [bool](Get-Prop -Object $result -Name 'hasNextPage' -Default $false)
        if (-not $hasNext) { break }

        $cursor = Get-Prop -Object $result -Name 'endCursor'
        if ([string]::IsNullOrWhiteSpace([string]$cursor)) {
            throw 'paginacao com hasNextPage=true e sem endCursor'
        }
    }

    return ,$items
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Pages.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 5, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Pages.ps1 delivery-queue/tests/DeliveryQueue.Pages.Tests.ps1
git commit -m "feat(delivery-queue): generic pagination helper"
```

---

### Task 2: Contrato do comentario de tentativa

**Files:**
- Create: `delivery-queue/src/DeliveryQueue.Attempt.ps1`
- Test: `delivery-queue/tests/DeliveryQueue.Attempt.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Prop` de `DeliveryQueue.Resolver.ps1`.
- Produces:
  - `ConvertTo-AttemptComment -Record <object> -> string` — envelope `<!-- delivery-queue-attempt:v1 ... -->` com o JSON do registro.
  - `ConvertFrom-AttemptComment -Body <string|null> -> object|null` — extrai o registro; `$null` se nao houver marcador.
  - `Select-LatestAttempt -Comments <string[]> -> object|null` — registro com maior `updatedAt`; empate ou ausencia de `updatedAt` fica com o ultimo lido.
  - `New-AttemptRecord -AttemptId <string> -Repository <string> -Epic <int> -Issue <int> -Branch <string> -Base <string> -BaseSha <string> -Now <string> -> object` com `status='started'` e os campos de spec secao 8 nulos.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.Attempt.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Attempt.ps1"
}

Describe 'ConvertTo-AttemptComment' {
    It 'envolve o registro no marcador v1' {
        $record = [pscustomobject]@{ attemptId = 'a1'; issue = 42; status = 'started' }
        $body = ConvertTo-AttemptComment -Record $record
        $body | Should -Match 'delivery-queue-attempt:v1'
        $body | Should -Match 'a1'
    }
}

Describe 'ConvertFrom-AttemptComment' {
    It 'faz roundtrip do registro' {
        $record = [pscustomobject]@{ attemptId = 'a1'; issue = 42; status = 'delivered'; updatedAt = '2026-09-18T10:00:00Z' }
        $parsed = ConvertFrom-AttemptComment -Body (ConvertTo-AttemptComment -Record $record)
        $parsed.attemptId | Should -Be 'a1'
        $parsed.issue | Should -Be 42
        $parsed.status | Should -Be 'delivered'
    }

    It 'ignora texto humano ao redor' {
        $record = [pscustomobject]@{ attemptId = 'a2'; updatedAt = '2026-09-18T10:00:00Z' }
        $body = "comentario humano`n$(ConvertTo-AttemptComment -Record $record)`nfim"
        (ConvertFrom-AttemptComment -Body $body).attemptId | Should -Be 'a2'
    }

    It 'devolve nulo sem marcador' {
        ConvertFrom-AttemptComment -Body 'apenas texto' | Should -BeNullOrEmpty
    }

    It 'devolve nulo para corpo nulo' {
        ConvertFrom-AttemptComment -Body $null | Should -BeNullOrEmpty
    }
}

Describe 'Select-LatestAttempt' {
    It 'escolhe o registro com updatedAt maior' {
        $old = ConvertTo-AttemptComment -Record ([pscustomobject]@{ attemptId = 'old'; updatedAt = '2026-09-18T09:00:00Z' })
        $new = ConvertTo-AttemptComment -Record ([pscustomobject]@{ attemptId = 'new'; updatedAt = '2026-09-18T11:00:00Z' })
        (Select-LatestAttempt -Comments @($old, $new)).attemptId | Should -Be 'new'
    }

    It 'devolve nulo sem comentario de tentativa' {
        Select-LatestAttempt -Comments @('humano') | Should -BeNullOrEmpty
    }
}

Describe 'New-AttemptRecord' {
    It 'monta o registro inicial started' {
        $r = New-AttemptRecord -AttemptId '20260918T1000Z-a1b2' -Repository 'o/r' -Epic 9 -Issue 42 `
            -Branch 'feat/42-x' -Base 'master' -BaseSha 'abc' -Now '2026-09-18T10:00:00Z'
        $r.attemptId | Should -Be '20260918T1000Z-a1b2'
        $r.status | Should -Be 'started'
        $r.reason | Should -BeNullOrEmpty
        $r.pr | Should -BeNullOrEmpty
        $r.review | Should -BeNullOrEmpty
        $r.merge | Should -BeNullOrEmpty
        $r.postMerge | Should -BeNullOrEmpty
        $r.checks.Count | Should -Be 0
        $r.updatedAt | Should -Be '2026-09-18T10:00:00Z'
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Attempt.Tests.ps1" -Output Detailed`
Expected: FAIL (`DeliveryQueue.Attempt.ps1` nao existe).

- [ ] **Step 3: Implementar**

Crie `delivery-queue/src/DeliveryQueue.Attempt.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')

function ConvertTo-AttemptComment {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Record)

    $json = $Record | ConvertTo-Json -Depth 20
    return "<!-- delivery-queue-attempt:v1`n$json`n-->"
}

function ConvertFrom-AttemptComment {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowNull()] [string]$Body)

    if ([string]::IsNullOrWhiteSpace($Body)) { return $null }

    $pattern = '(?s)<!--\s*delivery-queue-attempt:v1\s*(\{.*?\})\s*-->'
    $match = [regex]::Match($Body, $pattern)
    if (-not $match.Success) { return $null }

    try {
        return ($match.Groups[1].Value | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Select-LatestAttempt {
    [CmdletBinding()]
    param([AllowEmptyCollection()] [string[]]$Comments = @())

    $latest = $null
    $latestStamp = $null

    foreach ($body in @($Comments)) {
        $record = ConvertFrom-AttemptComment -Body $body
        if ($null -eq $record) { continue }

        $stamp = [string](Get-Prop -Object $record -Name 'updatedAt')
        if ($null -eq $latest) {
            $latest = $record
            $latestStamp = $stamp
            continue
        }
        if ($stamp -gt $latestStamp) {
            $latest = $record
            $latestStamp = $stamp
        }
    }

    return $latest
}

function New-AttemptRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$AttemptId,
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [int]$Epic,
        [Parameter(Mandatory)] [int]$Issue,
        [AllowNull()] [string]$Branch,
        [AllowNull()] [string]$Base,
        [AllowNull()] [string]$BaseSha,
        [Parameter(Mandatory)] [string]$Now
    )

    return [pscustomobject]@{
        attemptId = $AttemptId
        repository = $Repository
        epic = $Epic
        issue = $Issue
        branch = $Branch
        pr = $null
        base = $Base
        baseSha = $BaseSha
        headSha = $null
        status = 'started'
        reason = $null
        checks = @()
        review = $null
        merge = $null
        postMerge = $null
        nextAction = $null
        updatedAt = $Now
    }
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Attempt.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 8, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Attempt.ps1 delivery-queue/tests/DeliveryQueue.Attempt.Tests.ps1
git commit -m "feat(delivery-queue): attempt record comment contract"
```

---

### Task 3: Lock por repositorio

**Files:**
- Create: `delivery-queue/src/DeliveryQueue.Lock.ps1`
- Test: `delivery-queue/tests/DeliveryQueue.Lock.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Prop` de `DeliveryQueue.Resolver.ps1`.
- Produces:
  - `Get-QueueLockPath -Repository <string> [-Root <string>] -> string`.
  - `Enter-QueueLock -Repository <string> [-Root <string>] -> [pscustomobject]@{ Acquired; Path; Stream; Repository }` — `Acquired=$false` quando outra instancia detem o lock; usa exclusao do SO (`FileShare.None`), nao a existencia do arquivo.
  - `Exit-QueueLock -Lock <object> -> void`.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.Lock.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Lock.ps1"
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dq-lock-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
}
AfterAll {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Enter-QueueLock' {
    It 'adquire o lock livre' {
        $lock = Enter-QueueLock -Repository 'o/r' -Root $root
        try {
            $lock.Acquired | Should -BeTrue
            (Test-Path -LiteralPath $lock.Path) | Should -BeTrue
        }
        finally { Exit-QueueLock -Lock $lock }
    }

    It 'recusa a segunda instancia enquanto o lock esta retido' {
        $first = Enter-QueueLock -Repository 'o/r' -Root $root
        try {
            $second = Enter-QueueLock -Repository 'o/r' -Root $root
            $second.Acquired | Should -BeFalse
            $second.Stream | Should -BeNullOrEmpty
        }
        finally { Exit-QueueLock -Lock $first }
    }

    It 'libera e permite readquirir' {
        $first = Enter-QueueLock -Repository 'o/r' -Root $root
        Exit-QueueLock -Lock $first
        $second = Enter-QueueLock -Repository 'o/r' -Root $root
        try { $second.Acquired | Should -BeTrue }
        finally { Exit-QueueLock -Lock $second }
    }

    It 'isola repositorios diferentes' {
        $a = Enter-QueueLock -Repository 'o/a' -Root $root
        $b = Enter-QueueLock -Repository 'o/b' -Root $root
        try {
            $a.Acquired | Should -BeTrue
            $b.Acquired | Should -BeTrue
            $a.Path | Should -Not -Be $b.Path
        }
        finally { Exit-QueueLock -Lock $a; Exit-QueueLock -Lock $b }
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Lock.Tests.ps1" -Output Detailed`
Expected: FAIL (`DeliveryQueue.Lock.ps1` nao existe).

- [ ] **Step 3: Implementar**

Crie `delivery-queue/src/DeliveryQueue.Lock.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')

function Get-QueueLockPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [string]$Root = $env:TEMP
    )

    $slug = ($Repository -replace '[^A-Za-z0-9._-]', '_')
    return (Join-Path $Root "delivery-queue-$slug.lock")
}

function Enter-QueueLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [string]$Root = $env:TEMP
    )

    $path = Get-QueueLockPath -Repository $Repository -Root $Root
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $path,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
    }
    catch [System.IO.IOException] {
        return [pscustomobject]@{ Acquired = $false; Path = $path; Stream = $null; Repository = $Repository }
    }

    return [pscustomobject]@{ Acquired = $true; Path = $path; Stream = $stream; Repository = $Repository }
}

function Exit-QueueLock {
    [CmdletBinding()]
    param([AllowNull()] [object]$Lock)

    if ($null -eq $Lock) { return }

    $stream = Get-Prop -Object $Lock -Name 'Stream'
    if ($null -ne $stream) { $stream.Dispose() }

    $path = [string](Get-Prop -Object $Lock -Name 'Path')
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Lock.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 4, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Lock.ps1 delivery-queue/tests/DeliveryQueue.Lock.Tests.ps1
git commit -m "feat(delivery-queue): per-repository OS lock"
```

---

### Task 4: Coletor — elegibilidade, PR candidata e checks remotos

**Files:**
- Create: `delivery-queue/src/DeliveryQueue.Collector.ps1`
- Create: `delivery-queue/tests/TestHelpers.ps1`
- Test: `delivery-queue/tests/DeliveryQueue.Collector.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Prop`, `Get-Array`, `New-IssueId` de `DeliveryQueue.Resolver.ps1`.
- Produces:
  - `Get-CollectorLabels -Issue <object> -> string[]`.
  - `Get-IssueEligibility -Issue <object> -Policy <object> -ProjectState <object|null> -> [pscustomobject]@{ Eligible; Unknown }`. Com Project, o estado elegivel e a uniao de `eligibleStates` e `resumableStates`; sem item no Project, `Unknown=$true`. Com `fallbackEligibility` no formato `label:<nome>`, usa os labels.
  - `Test-RemoteChecksComplete -Checks <object[]> -ChecksKnown <bool> -Policy <object> -> bool`. Nao bloqueantes: `SUCCESS`, `NEUTRAL`, `SKIPPED`. `ChecksKnown=$false` e `requireChecksOnPr=$false` retorna `$false`/`$true` respectivamente.
  - `Select-IssuePr -Prs <object[]> -Repository <string> -Issue <int> -DefaultBranch <object> -Policy <object> -> [pscustomobject]@{ Pr; Ambiguous }`. Filtra PRs cuja base e `defaultBranch.name`; zero => `Pr=$null`; uma => `Pr` com `checksComplete`; mais de uma => `Ambiguous=$true`, `Pr=$null`.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/TestHelpers.ps1`:

```powershell
Set-StrictMode -Version Latest

function New-TestPolicy {
    [CmdletBinding()]
    param(
        [string]$MergeMode = 'human',
        [bool]$Verify = $false,
        [AllowEmptyCollection()] [string[]]$RequiredRemoteChecks = @(),
        [bool]$RequireChecksOnPr = $true,
        [AllowNull()] [object]$Project = $null,
        [AllowNull()] [string]$Fallback = $null
    )

    if ($null -eq $Project -and [string]::IsNullOrWhiteSpace($Fallback)) {
        $Project = [pscustomobject]@{
            owner = 'o'; number = 5
            eligibleStates = @('Ready'); resumableStates = @('In Progress')
        }
    }

    return [pscustomobject]@{
        version = 1
        defaultBranch = 'master'
        mergeMode = $MergeMode
        project = $Project
        fallbackEligibility = $Fallback
        requiredChecks = @('npm run build')
        requiredRemoteChecks = $RequiredRemoteChecks
        merge = [pscustomobject]@{
            method = 'merge'; requireChecksOnPr = $RequireChecksOnPr
            verifyDefaultBranchAfterMerge = $Verify
            authorizedByLocalRules = ($MergeMode -eq 'auto'); allowAdminBypass = $false
        }
        completionWithoutCode = 'allow-closed'
        workerTimeoutMinutes = 60
        worktreeRoot = '..'
    }
}

function New-GhFake {
    [CmdletBinding()]
    param(
        [scriptblock]$GetDefaultBranch,
        [scriptblock]$GetSubIssues,
        [scriptblock]$GetProjectState,
        [scriptblock]$GetIssueComments,
        [scriptblock]$GetIssuePrs,
        [scriptblock]$GetBlockerIssues,
        [scriptblock]$GetRefSha
    )

    if (-not $GetDefaultBranch) { $GetDefaultBranch = { param($Repository) [pscustomobject]@{ name = 'master'; headSha = 'base-sha' } } }
    if (-not $GetSubIssues) { $GetSubIssues = { param($Repository, $Epic) @() } }
    if (-not $GetProjectState) { $GetProjectState = { param($Owner, $Number, $NodeId) [pscustomobject]@{ found = $true; state = 'Ready' } } }
    if (-not $GetIssueComments) { $GetIssueComments = { param($Repository, $Issue) @() } }
    if (-not $GetIssuePrs) { $GetIssuePrs = { param($Repository, $Issue) @() } }
    if (-not $GetBlockerIssues) { $GetBlockerIssues = { param($Repository, $Ids) @{} } }
    if (-not $GetRefSha) { $GetRefSha = { param($Ref) $null } }

    return [pscustomobject]@{
        GetDefaultBranch = $GetDefaultBranch
        GetSubIssues     = $GetSubIssues
        GetProjectState  = $GetProjectState
        GetIssueComments = $GetIssueComments
        GetIssuePrs      = $GetIssuePrs
        GetBlockerIssues = $GetBlockerIssues
        GetRefSha        = $GetRefSha
    }
}
```

Crie `delivery-queue/tests/DeliveryQueue.Collector.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Collector.ps1"
    . "$PSScriptRoot/TestHelpers.ps1"
}

Describe 'Get-IssueEligibility' {
    It 'elegivel quando o estado do Project esta em eligibleStates' {
        $r = Get-IssueEligibility -Issue ([pscustomobject]@{ labels = @() }) -Policy (New-TestPolicy) -ProjectState ([pscustomobject]@{ found = $true; state = 'Ready' })
        $r.Eligible | Should -BeTrue
        $r.Unknown | Should -BeFalse
    }

    It 'elegivel quando o estado esta em resumableStates' {
        $r = Get-IssueEligibility -Issue ([pscustomobject]@{ labels = @() }) -Policy (New-TestPolicy) -ProjectState ([pscustomobject]@{ found = $true; state = 'In Progress' })
        $r.Eligible | Should -BeTrue
    }

    It 'nao elegivel para estado fora das listas' {
        $r = Get-IssueEligibility -Issue ([pscustomobject]@{ labels = @() }) -Policy (New-TestPolicy) -ProjectState ([pscustomobject]@{ found = $true; state = 'Backlog' })
        $r.Eligible | Should -BeFalse
        $r.Unknown | Should -BeFalse
    }

    It 'desconhecido quando o Project nao tem o item' {
        $r = Get-IssueEligibility -Issue ([pscustomobject]@{ labels = @() }) -Policy (New-TestPolicy) -ProjectState ([pscustomobject]@{ found = $false; state = $null })
        $r.Eligible | Should -BeFalse
        $r.Unknown | Should -BeTrue
    }

    It 'elegivel por label no fallback' {
        $r = Get-IssueEligibility -Issue ([pscustomobject]@{ labels = @('agent-ready', 'bug') }) -Policy (New-TestPolicy -Fallback 'label:agent-ready') -ProjectState $null
        $r.Eligible | Should -BeTrue
    }

    It 'nao elegivel quando o label do fallback falta' {
        $r = Get-IssueEligibility -Issue ([pscustomobject]@{ labels = @('bug') }) -Policy (New-TestPolicy -Fallback 'label:agent-ready') -ProjectState $null
        $r.Eligible | Should -BeFalse
    }

    It 'aceita labels como objetos com name' {
        $r = Get-IssueEligibility -Issue ([pscustomobject]@{ labels = @([pscustomobject]@{ name = 'agent-ready' }) }) -Policy (New-TestPolicy -Fallback 'label:agent-ready') -ProjectState $null
        $r.Eligible | Should -BeTrue
    }
}

Describe 'Test-RemoteChecksComplete' {
    It 'reconhece checks desconhecidos como incompletos' {
        (Test-RemoteChecksComplete -Checks @() -ChecksKnown $false -Policy (New-TestPolicy)) | Should -BeFalse
    }

    It 'nao exige checks quando requireChecksOnPr e falso' {
        (Test-RemoteChecksComplete -Checks @() -ChecksKnown $true -Policy (New-TestPolicy -RequireChecksOnPr $false)) | Should -BeTrue
    }

    It 'aceita todos os checks presentes quando nao ha lista exigida' {
        $checks = @([pscustomobject]@{ context = 'ci'; conclusion = 'SUCCESS' }, [pscustomobject]@{ context = 'lint'; conclusion = 'SKIPPED' })
        (Test-RemoteChecksComplete -Checks $checks -ChecksKnown $true -Policy (New-TestPolicy)) | Should -BeTrue
    }

    It 'rejeita check presente falhando' {
        $checks = @([pscustomobject]@{ context = 'ci'; conclusion = 'FAILURE' })
        (Test-RemoteChecksComplete -Checks $checks -ChecksKnown $true -Policy (New-TestPolicy)) | Should -BeFalse
    }

    It 'rejeita check presente pendente' {
        $checks = @([pscustomobject]@{ context = 'ci'; conclusion = 'PENDING' })
        (Test-RemoteChecksComplete -Checks $checks -ChecksKnown $true -Policy (New-TestPolicy)) | Should -BeFalse
    }

    It 'exige os contextos da lista requiredRemoteChecks' {
        $policy = New-TestPolicy -RequiredRemoteChecks @('ci/build', 'ci/test')
        $checks = @([pscustomobject]@{ context = 'ci/build'; conclusion = 'SUCCESS' })
        (Test-RemoteChecksComplete -Checks $checks -ChecksKnown $true -Policy $policy) | Should -BeFalse
    }

    It 'aceita quando todos os contextos exigidos passaram' {
        $policy = New-TestPolicy -RequiredRemoteChecks @('ci/build', 'ci/test')
        $checks = @([pscustomobject]@{ context = 'ci/build'; conclusion = 'SUCCESS' }, [pscustomobject]@{ context = 'ci/test'; conclusion = 'NEUTRAL' })
        (Test-RemoteChecksComplete -Checks $checks -ChecksKnown $true -Policy $policy) | Should -BeTrue
    }
}

Describe 'Select-IssuePr' {
    It 'devolve nulo sem candidata' {
        $r = Select-IssuePr -Prs @() -Repository 'o/r' -Issue 1 -DefaultBranch ([pscustomobject]@{ name = 'master' }) -Policy (New-TestPolicy)
        $r.Pr | Should -BeNullOrEmpty
        $r.Ambiguous | Should -BeFalse
    }

    It 'seleciona a unica PR na branch padrao' {
        $prs = @([pscustomobject]@{ number = 7; url = 'u'; state = 'OPEN'; isDraft = $false; baseRefName = 'master'; headRefName = 'feat/1'; headSha = 'h'; hasConflict = $false; checks = @([pscustomobject]@{ context = 'ci'; conclusion = 'SUCCESS' }); checksKnown = $true })
        $r = Select-IssuePr -Prs $prs -Repository 'o/r' -Issue 1 -DefaultBranch ([pscustomobject]@{ name = 'master' }) -Policy (New-TestPolicy)
        $r.Pr.number | Should -Be 7
        $r.Pr.checksComplete | Should -BeTrue
        $r.Ambiguous | Should -BeFalse
    }

    It 'ignora PR cuja base nao e a padrao' {
        $prs = @([pscustomobject]@{ number = 8; state = 'OPEN'; baseRefName = 'release'; headSha = 'h'; checks = @(); checksKnown = $true })
        $r = Select-IssuePr -Prs $prs -Repository 'o/r' -Issue 1 -DefaultBranch ([pscustomobject]@{ name = 'master' }) -Policy (New-TestPolicy)
        $r.Pr | Should -BeNullOrEmpty
    }

    It 'marca ambiguidade com mais de uma candidata' {
        $prs = @(
            [pscustomobject]@{ number = 7; baseRefName = 'master'; state = 'OPEN'; headSha = 'h'; checks = @(); checksKnown = $true },
            [pscustomobject]@{ number = 8; baseRefName = 'master'; state = 'OPEN'; headSha = 'h2'; checks = @(); checksKnown = $true }
        )
        $r = Select-IssuePr -Prs $prs -Repository 'o/r' -Issue 1 -DefaultBranch ([pscustomobject]@{ name = 'master' }) -Policy (New-TestPolicy)
        $r.Ambiguous | Should -BeTrue
        $r.Pr | Should -BeNullOrEmpty
    }

    It 'propaga checks incompletos para a PR selecionada' {
        $prs = @([pscustomobject]@{ number = 7; baseRefName = 'master'; state = 'OPEN'; headSha = 'h'; hasConflict = $false; checks = @([pscustomobject]@{ context = 'ci'; conclusion = 'PENDING' }); checksKnown = $true })
        $r = Select-IssuePr -Prs $prs -Repository 'o/r' -Issue 1 -DefaultBranch ([pscustomobject]@{ name = 'master' }) -Policy (New-TestPolicy)
        $r.Pr.checksComplete | Should -BeFalse
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Collector.Tests.ps1" -Output Detailed`
Expected: FAIL (`DeliveryQueue.Collector.ps1` nao existe).

- [ ] **Step 3: Implementar**

Crie `delivery-queue/src/DeliveryQueue.Collector.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Pages.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Attempt.ps1')

function Get-CollectorLabels {
    [CmdletBinding()]
    param([AllowNull()] [object]$Issue)

    $names = @()
    foreach ($label in (Get-Array -Value (Get-Prop -Object $Issue -Name 'labels'))) {
        if ($label -is [string]) { $names += $label; continue }
        $name = [string](Get-Prop -Object $label -Name 'name')
        if (-not [string]::IsNullOrWhiteSpace($name)) { $names += $name }
    }
    return ,$names
}

function Get-IssueEligibility {
    [CmdletBinding()]
    param(
        [AllowNull()] [object]$Issue,
        [Parameter(Mandatory)] [object]$Policy,
        [AllowNull()] [object]$ProjectState
    )

    $project = Get-Prop -Object $Policy -Name 'project'
    if ($null -ne $project) {
        $found = [bool](Get-Prop -Object $ProjectState -Name 'found' -Default $false)
        $state = [string](Get-Prop -Object $ProjectState -Name 'state')
        $states = Get-Array -Value (Get-Prop -Object $project -Name 'eligibleStates')
        $states += Get-Array -Value (Get-Prop -Object $project -Name 'resumableStates')
        return [pscustomobject]@{ Eligible = ($found -and ($states -contains $state)); Unknown = (-not $found) }
    }

    $fallback = [string](Get-Prop -Object $Policy -Name 'fallbackEligibility')
    if ($fallback -match '^label:(?<name>.+)$') {
        $label = $Matches['name']
        $labels = Get-CollectorLabels -Issue $Issue
        return [pscustomobject]@{ Eligible = ($labels -contains $label); Unknown = $false }
    }

    return [pscustomobject]@{ Eligible = $false; Unknown = $true }
}

function Test-RemoteChecksComplete {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [object[]]$Checks = @(),
        [bool]$ChecksKnown = $false,
        [Parameter(Mandatory)] [object]$Policy
    )

    if (-not $ChecksKnown) { return $false }

    $merge = Get-Prop -Object $Policy -Name 'merge'
    $requireChecks = [bool](Get-Prop -Object $merge -Name 'requireChecksOnPr' -Default $false)
    if (-not $requireChecks) { return $true }

    $accepted = @('SUCCESS', 'NEUTRAL', 'SKIPPED')
    $byContext = @{}
    foreach ($check in @($Checks)) {
        $context = [string](Get-Prop -Object $check -Name 'context')
        $conclusion = [string](Get-Prop -Object $check -Name 'conclusion')
        $byContext[$context] = $conclusion
    }

    $required = Get-Array -Value (Get-Prop -Object $Policy -Name 'requiredRemoteChecks')
    if ($required.Count -gt 0) {
        foreach ($context in $required) {
            if (-not $byContext.ContainsKey($context)) { return $false }
            if ($byContext[$context] -notin $accepted) { return $false }
        }
        return $true
    }

    foreach ($context in $byContext.Keys) {
        if ($byContext[$context] -notin $accepted) { return $false }
    }
    return $true
}

function Select-IssuePr {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [object[]]$Prs = @(),
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [int]$Issue,
        [Parameter(Mandatory)] [object]$DefaultBranch,
        [Parameter(Mandatory)] [object]$Policy
    )

    $defaultName = [string](Get-Prop -Object $DefaultBranch -Name 'name')
    $candidates = @()
    foreach ($pr in @($Prs)) {
        if ([string](Get-Prop -Object $pr -Name 'baseRefName') -eq $defaultName) {
            $candidates += $pr
        }
    }

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{ Pr = $null; Ambiguous = $false }
    }
    if ($candidates.Count -gt 1) {
        return [pscustomobject]@{ Pr = $null; Ambiguous = $true }
    }

    $pr = $candidates[0]
    $checks = Get-Array -Value (Get-Prop -Object $pr -Name 'checks')
    $checksKnown = [bool](Get-Prop -Object $pr -Name 'checksKnown' -Default $false)
    $complete = Test-RemoteChecksComplete -Checks $checks -ChecksKnown $checksKnown -Policy $Policy

    return [pscustomobject]@{
        Pr = [pscustomobject]@{
            number         = [int](Get-Prop -Object $pr -Name 'number')
            url            = [string](Get-Prop -Object $pr -Name 'url')
            state          = [string](Get-Prop -Object $pr -Name 'state')
            isDraft        = [bool](Get-Prop -Object $pr -Name 'isDraft' -Default $false)
            hasConflict    = [bool](Get-Prop -Object $pr -Name 'hasConflict' -Default $false)
            checksComplete = $complete
            headSha        = [string](Get-Prop -Object $pr -Name 'headSha')
            baseRefName    = $defaultName
            headRefName    = [string](Get-Prop -Object $pr -Name 'headRefName')
        }
        Ambiguous = $false
    }
}
```

Nunca envolva a saida de `Get-Array` em `@(...)`: `@(Get-Array -Value @(1,2))` produz um array de um elemento cujo [0] e o array interno (verificado em PS 5.1). Atribuicao direta (`$x = Get-Array ...`) e concatenacao (`$x += Get-Array ...`) sao as formas corretas.

- [ ] **Step 4: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Collector.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 18, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Collector.ps1 delivery-queue/tests/TestHelpers.ps1 delivery-queue/tests/DeliveryQueue.Collector.Tests.ps1
git commit -m "feat(delivery-queue): collector eligibility, PR selection and remote checks"
```

---

### Task 5: Coletor — montagem do snapshot

**Files:**
- Modify: `delivery-queue/src/DeliveryQueue.Collector.ps1` (append)
- Modify: `delivery-queue/tests/DeliveryQueue.Collector.Tests.ps1` (append)

**Interfaces:**
- Consumes: tudo da Task 4, mais `Get-PagedItems` (`DeliveryQueue.Pages.ps1`), `Select-LatestAttempt` (`DeliveryQueue.Attempt.ps1`) e `New-IssueId`.
- Produces:
  - `New-CollectorIssueNode -Raw <object> -Repository <string> -DefaultBranch <object> -Policy <object> -Gh <object> [-InScope <bool>] -> object` — no no formato do resolver.
  - `New-CollectorError -Code <string> -Message <string> -> [pscustomobject]@{ Ok=$false; Error; Snapshot=$null }`.
  - `New-QueueSnapshot -Repository <string> -Epic <int> -Policy <object> -Gh <object> [-Filter <object>] -> [pscustomobject]@{ Ok; Error; Snapshot }`. Falha global de coleta devolve `Ok=$false`, `Code='infra'` e **nunca** snapshot parcial.

- [ ] **Step 1: Escrever os testes que falham**

Acrescente ao final de `delivery-queue/tests/DeliveryQueue.Collector.Tests.ps1`:

```powershell
Describe 'New-QueueSnapshot' {
    It 'monta a cadeia linear e o resolver libera so a primeira' {
        $gh = New-GhFake -GetSubIssues {
            param($Repository, $Epic)
            @(
                [pscustomobject]@{ number = 3; nodeId = 'n3'; title = 'C'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @('o/r#2') },
                [pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() },
                [pscustomobject]@{ number = 2; nodeId = 'n2'; title = 'B'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @('o/r#1') }
            )
        }
        $result = New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy (New-TestPolicy) -Gh $gh

        $result.Ok | Should -BeTrue
        $plan = Resolve-QueuePlan -Snapshot $result.Snapshot
        $plan.Order | Should -Be @('o/r#1', 'o/r#2', 'o/r#3')
        $plan.Runnable | Should -Be @('o/r#1')
    }

    It 'inclui blocker externo fora do escopo como bloqueio' {
        $gh = New-GhFake `
            -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 2; nodeId = 'n2'; title = 'B'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @('o/r#99') }) } `
            -GetBlockerIssues { param($Repository, $Ids) @{ 'o/r#99' = [pscustomobject]@{ state = 'OPEN'; stateReason = $null } } }
        $result = New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy (New-TestPolicy) -Gh $gh

        $plan = Resolve-QueuePlan -Snapshot $result.Snapshot
        ($plan.Issues | Where-Object Number -eq 2).Reason | Should -Be 'blocked_by_issue'
    }

    It 'marca no externo desconhecido quando o blocker nao vem dos dados' {
        $gh = New-GhFake `
            -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 2; nodeId = 'n2'; title = 'B'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @('o/r#99') }) } `
            -GetBlockerIssues { param($Repository, $Ids) @{} }
        $result = New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy (New-TestPolicy) -Gh $gh

        $external = $result.Snapshot.issues | Where-Object { $_.id -eq 'o/r#99' }
        $external.unknown | Should -BeTrue
    }

    It 'falha de coleta nao produz snapshot parcial' {
        $gh = New-GhFake -GetSubIssues { param($Repository, $Epic) throw 'falha na pagina 2' }
        $result = New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy (New-TestPolicy) -Gh $gh

        $result.Ok | Should -BeFalse
        $result.Error.Code | Should -Be 'infra'
        $result.Snapshot | Should -BeNullOrEmpty
    }

    It 'falha ao ler a branch padrao encerra como infra' {
        $gh = New-GhFake -GetDefaultBranch { param($Repository) throw 'sem auth' }
        $result = New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy (New-TestPolicy) -Gh $gh
        $result.Ok | Should -BeFalse
        $result.Error.Code | Should -Be 'infra'
    }

    It 'le o registro de tentativa do comentario' {
        $gh = New-GhFake `
            -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() }) } `
            -GetIssueComments { param($Repository, $Issue) @((ConvertTo-AttemptComment -Record ([pscustomobject]@{ attemptId = 'att1'; status = 'failed'; updatedAt = '2026-09-18T10:00:00Z' }))) }
        $result = New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy (New-TestPolicy) -Gh $gh

        $result.Snapshot.issues[0].attempt.attemptId | Should -Be 'att1'
        $plan = Resolve-QueuePlan -Snapshot $result.Snapshot
        ($plan.Issues | Where-Object Number -eq 1).Status | Should -Be 'failed'
    }

    It 'marca unknown quando a leitura do Project falha' {
        $gh = New-GhFake `
            -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() }) } `
            -GetProjectState { param($Owner, $Number, $NodeId) throw 'project indisponivel' }
        $result = New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy (New-TestPolicy) -Gh $gh

        $result.Ok | Should -BeTrue
        $result.Snapshot.issues[0].unknown | Should -BeTrue
        $plan = Resolve-QueuePlan -Snapshot $result.Snapshot
        ($plan.Issues | Where-Object Number -eq 1).Reason | Should -Be 'infra'
    }

    It 'usa fallback de label quando nao ha Project' {
        $policy = New-TestPolicy -Project $null -Fallback 'label:agent-ready'
        $gh = New-GhFake -GetSubIssues {
            param($Repository, $Epic)
            @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @('agent-ready'); blockedBy = @() })
        }
        $result = New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $policy -Gh $gh

        $result.Snapshot.issues[0].eligible | Should -BeTrue
        $plan = Resolve-QueuePlan -Snapshot $result.Snapshot
        ($plan.Issues | Where-Object Number -eq 1).Status | Should -Be 'runnable'
    }

    It 'preserva o filtro -Only no snapshot' {
        $gh = New-GhFake -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() }) }
        $result = New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy (New-TestPolicy) -Gh $gh -Filter ([pscustomobject]@{ only = @(7) })

        $result.Snapshot.filter.only | Should -Be @(7)
        $plan = Resolve-QueuePlan -Snapshot $result.Snapshot
        ($plan.Issues | Where-Object Number -eq 1).Reason | Should -Be 'filtered'
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Collector.Tests.ps1" -Output Detailed`
Expected: FAIL em `New-QueueSnapshot: CommandNotFoundException`.

- [ ] **Step 3: Implementar**

Acrescente ao final de `delivery-queue/src/DeliveryQueue.Collector.ps1`:

```powershell
function New-CollectorError {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Code, [Parameter(Mandatory)] [string]$Message)
    return [pscustomobject]@{
        Ok = $false
        Error = [pscustomobject]@{ Code = $Code; Messages = @($Message) }
        Snapshot = $null
    }
}

function New-CollectorIssueNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Raw,
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [object]$DefaultBranch,
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Gh,
        [bool]$InScope = $true
    )

    $number = [int](Get-Prop -Object $Raw -Name 'number')
    $id = [string](Get-Prop -Object $Raw -Name 'id')
    if ([string]::IsNullOrWhiteSpace($id)) {
        $id = New-IssueId -Repository $Repository -Number $number
    }

    $unknown = $false

    $project = Get-Prop -Object $Policy -Name 'project'
    $projectState = $null
    if ($null -ne $project) {
        try {
            $projectState = & $Gh.GetProjectState `
                -Owner ([string](Get-Prop -Object $project -Name 'owner')) `
                -Number ([int](Get-Prop -Object $project -Name 'number')) `
                -NodeId ([string](Get-Prop -Object $Raw -Name 'nodeId'))
        }
        catch {
            $projectState = [pscustomobject]@{ found = $false; state = $null }
        }
    }
    $eligibility = Get-IssueEligibility -Issue $Raw -Policy $Policy -ProjectState $projectState
    if ([bool]$eligibility.Unknown) { $unknown = $true }

    $attempt = $null
    try {
        $comments = @(& $Gh.GetIssueComments -Repository $Repository -Issue $number)
        $attempt = Select-LatestAttempt -Comments $comments
    }
    catch { $unknown = $true }

    $pr = $null
    $ambiguous = $false
    try {
        $prs = @(& $Gh.GetIssuePrs -Repository $Repository -Issue $number)
        $selected = Select-IssuePr -Prs $prs -Repository $Repository -Issue $number -DefaultBranch $DefaultBranch -Policy $Policy
        $pr = $selected.Pr
        $ambiguous = [bool]$selected.Ambiguous
    }
    catch { $unknown = $true }

    $blockedBy = @()
    foreach ($blocker in (Get-Array -Value (Get-Prop -Object $Raw -Name 'blockedBy'))) {
        $blockedBy += [string]$blocker
    }

    return [pscustomobject]@{
        id          = $id
        number      = $number
        title       = [string](Get-Prop -Object $Raw -Name 'title')
        state       = [string](Get-Prop -Object $Raw -Name 'state')
        stateReason = Get-Prop -Object $Raw -Name 'stateReason'
        hasCode     = [bool](Get-Prop -Object $Raw -Name 'hasCode' -Default $true)
        inScope     = $InScope
        eligible    = [bool]$eligibility.Eligible
        unknown     = $unknown
        ambiguousPr = $ambiguous
        blockedBy   = $blockedBy
        pr          = $pr
        attempt     = $attempt
    }
}

function New-QueueSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [int]$Epic,
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Gh,
        [AllowNull()] [object]$Filter = $null
    )

    if ($null -eq $Filter) { $Filter = [pscustomobject]@{ only = @() } }

    try {
        $defaultBranch = & $Gh.GetDefaultBranch -Repository $Repository
    }
    catch {
        return New-CollectorError -Code 'infra' -Message "falha ao ler a branch padrao: $($_.Exception.Message)"
    }
    if ($null -eq $defaultBranch) {
        return New-CollectorError -Code 'infra' -Message 'branch padrao indisponivel'
    }

    try {
        $subIssues = @(& $Gh.GetSubIssues -Repository $Repository -Epic $Epic)
    }
    catch {
        return New-CollectorError -Code 'infra' -Message "falha ao coletar sub-issues: $($_.Exception.Message)"
    }

    $rawByNumber = @{}
    foreach ($raw in $subIssues) {
        $rawByNumber[[int](Get-Prop -Object $raw -Name 'number')] = $raw
    }

    $externalIds = @()
    foreach ($raw in $subIssues) {
        foreach ($blocker in (Get-Array -Value (Get-Prop -Object $raw -Name 'blockedBy'))) {
            $blockerId = [string]$blocker
            if ($blockerId -match '#(?<n>\d+)$') {
                $blockerNumber = [int]$Matches['n']
                if (-not $rawByNumber.ContainsKey($blockerNumber) -and ($externalIds -notcontains $blockerId)) {
                    $externalIds += $blockerId
                }
            }
        }
    }

    $externalStates = @{}
    if ($externalIds.Count -gt 0) {
        try {
            $externalStates = & $Gh.GetBlockerIssues -Repository $Repository -Ids $externalIds
            if ($null -eq $externalStates) { throw 'blockers externos indisponiveis' }
        }
        catch {
            return New-CollectorError -Code 'infra' -Message "falha ao coletar blockers externos: $($_.Exception.Message)"
        }
    }

    $issues = @()
    foreach ($raw in $subIssues) {
        $issues += New-CollectorIssueNode -Raw $raw -Repository $Repository -DefaultBranch $defaultBranch -Policy $Policy -Gh $Gh -InScope $true
    }

    foreach ($externalId in $externalIds) {
        $state = $null
        if ($externalStates.ContainsKey($externalId)) { $state = $externalStates[$externalId] }
        $number = 0
        if ($externalId -match '#(?<n>\d+)$') { $number = [int]$Matches['n'] }
        $issues += [pscustomobject]@{
            id          = $externalId
            number      = $number
            title       = ''
            state       = [string](Get-Prop -Object $state -Name 'state')
            stateReason = Get-Prop -Object $state -Name 'stateReason'
            hasCode     = $true
            inScope     = $false
            eligible    = $true
            unknown     = ($null -eq $state)
            ambiguousPr = $false
            blockedBy   = @()
            pr          = $null
            attempt     = $null
        }
    }

    $snapshot = [pscustomobject]@{
        schemaVersion = 1
        repository    = $Repository
        epic          = [pscustomobject]@{ number = $Epic }
        defaultBranch = [pscustomobject]@{
            name    = [string](Get-Prop -Object $defaultBranch -Name 'name')
            headSha = [string](Get-Prop -Object $defaultBranch -Name 'headSha')
        }
        policy        = $Policy
        filter        = [pscustomobject]@{ only = (Get-Array -Value (Get-Prop -Object $Filter -Name 'only')) }
        attempted     = @()
        issues        = $issues
    }

    return [pscustomobject]@{ Ok = $true; Error = $null; Snapshot = $snapshot }
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Collector.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 27, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Collector.ps1 delivery-queue/tests/DeliveryQueue.Collector.Tests.ps1
git commit -m "feat(delivery-queue): snapshot assembly from collector adapter"
```

---

### Task 6: Carregador de politica, adapter `gh` real e CLI do coletor

**Files:**
- Create: `delivery-queue/src/DeliveryQueue.Common.ps1`
- Create: `delivery-queue/src/DeliveryQueue.Gh.ps1`
- Create: `delivery-queue/src/Get-QueueSnapshot.ps1`
- Test: `delivery-queue/tests/DeliveryQueue.CollectorCli.Tests.ps1`

**Interfaces:**
- Consumes: `Test-DeliveryQueuePolicy` (resolver), `New-QueueSnapshot`, `New-GhFake` (testes).
- Produces:
  - `Read-DeliveryQueuePolicy -Path <string> -> [pscustomobject]@{ Ok; Code; Messages; Policy }`. `Code` assume `policy_missing`, `policy_invalid` ou `policy_conflict`.
  - `Invoke-GhJson -Arguments <string[]> -> object|null` — wrapper de `gh` que lanca em exit code != 0.
  - `New-DeliveryQueueGhAdapter [-InvokeGh <scriptblock>] -> object` — adapter do contrato `$Gh`; `-InvokeGh` recebe `-Arguments <string[]>` e devolve JSON ja parseado (seam de teste).
  - CLI `Get-QueueSnapshot.ps1 -Epic <int> -Repository <string> [-PolicyPath <path>] [-Only <int[]>] [-OutputPath <path>] [-GhAdapter <object>]` — saida `0` snapshot gravado, `4` politica/coleta/infra.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.CollectorCli.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Pages.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Attempt.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Common.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Collector.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Gh.ps1"
    . "$PSScriptRoot/TestHelpers.ps1"

    function Write-PolicyFile {
        param([object]$Policy, [string]$Name = 'policy.json')
        $path = Join-Path $TestDrive $Name
        ($Policy | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $path -Encoding UTF8
        return $path
    }
}

Describe 'Read-DeliveryQueuePolicy' {
    It 'falha quando o arquivo nao existe' {
        $r = Read-DeliveryQueuePolicy -Path (Join-Path $TestDrive 'inexistente.json')
        $r.Ok | Should -BeFalse
        $r.Code | Should -Be 'policy_missing'
    }

    It 'le politica valida' {
        $path = Write-PolicyFile -Policy (New-TestPolicy)
        $r = Read-DeliveryQueuePolicy -Path $path
        $r.Ok | Should -BeTrue
        $r.Policy.mergeMode | Should -Be 'human'
    }

    It 'rejeita JSON malformado' {
        $path = Join-Path $TestDrive 'malformado.json'
        Set-Content -LiteralPath $path -Value '{ nao json' -Encoding UTF8
        $r = Read-DeliveryQueuePolicy -Path $path
        $r.Ok | Should -BeFalse
        $r.Code | Should -Be 'policy_invalid'
    }

    It 'rejeita policy conflitante com regra local' {
        $policy = New-TestPolicy -MergeMode 'auto'
        $policy.merge.authorizedByLocalRules = $false
        $path = Write-PolicyFile -Policy $policy
        $r = Read-DeliveryQueuePolicy -Path $path
        $r.Ok | Should -BeFalse
        $r.Code | Should -Be 'policy_conflict'
    }
}

Describe 'New-DeliveryQueueGhAdapter' {
    It 'monta a branch padrao e o head' {
        $adapter = New-DeliveryQueueGhAdapter -InvokeGh {
            param($Arguments)
            if ($Arguments -contains 'view') { return [pscustomobject]@{ defaultBranchRef = [pscustomobject]@{ name = 'master' } } }
            return [pscustomobject]@{ sha = 'abc123' }
        }
        $r = & $adapter.GetDefaultBranch -Repository 'o/r'
        $r.name | Should -Be 'master'
        $r.headSha | Should -Be 'abc123'
    }

    It 'filtra PRs pelo corpo com keyword de fechamento e pela base' {
        $adapter = New-DeliveryQueueGhAdapter -InvokeGh {
            param($Arguments)
            return @(
                [pscustomobject]@{ number = 7; state = 'OPEN'; isDraft = $false; baseRefName = 'master'; headRefName = 'feat/1'; headRefOid = 'h'; url = 'u'; mergeable = 'MERGEABLE'; body = 'Closes #1'; statusCheckRollup = @([pscustomobject]@{ name = 'ci'; conclusion = 'SUCCESS' }) },
                [pscustomobject]@{ number = 8; state = 'OPEN'; isDraft = $false; baseRefName = 'master'; headRefName = 'feat/9'; headRefOid = 'h2'; url = 'u2'; mergeable = 'MERGEABLE'; body = 'sem keyword'; statusCheckRollup = @() },
                [pscustomobject]@{ number = 9; state = 'OPEN'; isDraft = $false; baseRefName = 'outra'; headRefName = 'feat/1'; headRefOid = 'h3'; url = 'u3'; mergeable = 'MERGEABLE'; body = 'Closes #1'; statusCheckRollup = @() }
            )
        }
        $prs = @(& $adapter.GetIssuePrs -Repository 'o/r' -Issue 1)
        $prs.Count | Should -Be 2
        $prs[0].number | Should -Be 7
        $prs[0].checks[0].context | Should -Be 'ci'
    }

    It 'le o estado do Project do item da issue' {
        $adapter = New-DeliveryQueueGhAdapter -InvokeGh {
            param($Arguments)
            return [pscustomobject]@{ items = @([pscustomobject]@{ content = [pscustomobject]@{ number = 42 }; status = 'Ready' }) }
        }
        $r = & $adapter.GetProjectState -Owner 'o' -Number 5 -NodeId 'n1'
        $r.found | Should -BeTrue
        $r.state | Should -Be 'Ready'
    }
}

Describe 'Get-QueueSnapshot.ps1 (CLI)' {
    It 'retorna 4 quando a politica esta ausente' {
        & "$PSScriptRoot/../src/Get-QueueSnapshot.ps1" -Epic 9 -Repository 'o/r' -PolicyPath (Join-Path $TestDrive 'nao-existe.json') | Out-Null
        $LASTEXITCODE | Should -Be 4
    }

    It 'grava o snapshot equivalente ao coletor com adapter injetado' {
        $path = Write-PolicyFile -Policy (New-TestPolicy)
        $out = Join-Path $TestDrive 'snapshot.json'
        $gh = New-GhFake -GetSubIssues {
            param($Repository, $Epic)
            @(
                [pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() },
                [pscustomobject]@{ number = 2; nodeId = 'n2'; title = 'B'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @('o/r#1') }
            )
        }
        & "$PSScriptRoot/../src/Get-QueueSnapshot.ps1" -Epic 9 -Repository 'o/r' -PolicyPath $path -OutputPath $out -GhAdapter $gh | Out-Null
        $LASTEXITCODE | Should -Be 0

        $snapshot = Get-Content -LiteralPath $out -Raw -Encoding UTF8 | ConvertFrom-Json
        $plan = Resolve-QueuePlan -Snapshot $snapshot
        $plan.Order | Should -Be @('o/r#1', 'o/r#2')
        $plan.Runnable | Should -Be @('o/r#1')
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.CollectorCli.Tests.ps1" -Output Detailed`
Expected: FAIL (`DeliveryQueue.Common.ps1` nao existe).

- [ ] **Step 3: Implementar o carregador de politica**

Crie `delivery-queue/src/DeliveryQueue.Common.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')

function Read-DeliveryQueuePolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            Ok = $false; Code = 'policy_missing'
            Messages = @("policy ausente: $Path"); Policy = $null
        }
    }

    try {
        $policy = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            Ok = $false; Code = 'policy_invalid'
            Messages = @("policy invalida: $($_.Exception.Message)"); Policy = $null
        }
    }

    $problems = Test-DeliveryQueuePolicy -Policy $policy
    if ($problems.Count -gt 0) {
        $code = 'policy_invalid'
        foreach ($problem in $problems) {
            if ($problem -match '^policy_conflict:') { $code = 'policy_conflict' }
        }
        return [pscustomobject]@{ Ok = $false; Code = $code; Messages = $problems; Policy = $policy }
    }

    return [pscustomobject]@{ Ok = $true; Code = $null; Messages = @(); Policy = $policy }
}
```

- [ ] **Step 4: Implementar o adapter `gh` real**

Crie `delivery-queue/src/DeliveryQueue.Gh.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Pages.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')

function Invoke-GhJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]]$Arguments)

    $output = & gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh falhou ($LASTEXITCODE): $($output -join ' ')"
    }
    $text = (($output | ForEach-Object { [string]$_ }) -join "`n")
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json)
}

function New-DeliveryQueueGhAdapter {
    [CmdletBinding()]
    param([scriptblock]$InvokeGh)

    if (-not $InvokeGh) {
        $InvokeGh = { param([string[]]$Arguments) Invoke-GhJson -Arguments $Arguments }
    }

    $getDefaultBranch = {
        param($Repository)
        $meta = & $InvokeGh -Arguments @('repo', 'view', $Repository, '--json', 'defaultBranchRef')
        $branch = [string]$meta.defaultBranchRef.name
        $head = & $InvokeGh -Arguments @('api', "repos/$Repository/commits/$branch")
        return [pscustomobject]@{ name = $branch; headSha = [string]$head.sha }
    }.GetNewClosure()

    $getSubIssues = {
        param($Repository, $Epic)
        $split = $Repository -split '/'
        $repoOwner = $split[0]
        $repoName = $split[1]
        $query = 'query($owner:String!,$name:String!,$number:Int!,$after:String){repository(owner:$owner,name:$name){issue(number:$number){subIssues(first:100,after:$after){pageInfo{hasNextPage endCursor}nodes{number id title state stateReason labels(first:100){nodes{name}} blockedBy(first:100){nodes{number}}}}}}}'
        $fetch = {
            param($cursor)
            $arguments = @('api', 'graphql', '-f', "query=$query", '-f', "owner=$repoOwner", '-f', "name=$repoName", '-F', "number=$Epic")
            if (-not [string]::IsNullOrWhiteSpace([string]$cursor)) {
                $arguments += @('-f', "after=$cursor")
            }
            $data = & $InvokeGh -Arguments $arguments
            $connection = $data.data.repository.issue.subIssues
            $items = @()
            foreach ($node in @($connection.nodes)) {
                $labels = @()
                foreach ($label in @($node.labels.nodes)) { $labels += [string]$label.name }
                $blocked = @()
                foreach ($blocker in @($node.blockedBy.nodes)) { $blocked += "$Repository#$([int]$blocker.number)" }
                $items += [pscustomobject]@{
                    number = [int]$node.number; nodeId = [string]$node.id
                    title = [string]$node.title; state = [string]$node.state
                    stateReason = [string]$node.stateReason; labels = $labels; blockedBy = $blocked
                }
            }
            return [pscustomobject]@{ items = $items; hasNextPage = [bool]$connection.pageInfo.hasNextPage; endCursor = $connection.pageInfo.endCursor }
        }.GetNewClosure()
        return ,(Get-PagedItems -FetchPage $fetch)
    }.GetNewClosure()

    $getProjectState = {
        param($Owner, $Number, $NodeId)
        $result = & $InvokeGh -Arguments @('project', 'item-list', [string]$Number, '--owner', $Owner, '--format', 'json', '--limit', '2000')
        foreach ($item in @($result.items)) {
            $content = Get-Prop -Object $item -Name 'content'
            if ([string](Get-Prop -Object $content -Name 'id') -eq [string]$NodeId) {
                $state = [string](Get-Prop -Object $item -Name 'status')
                if ([string]::IsNullOrWhiteSpace($state)) { $state = [string](Get-Prop -Object $item -Name 'Status') }
                return [pscustomobject]@{ found = $true; state = $state }
            }
        }
        return [pscustomobject]@{ found = $false; state = $null }
    }.GetNewClosure()

    $getIssueComments = {
        param($Repository, $Issue)
        $data = & $InvokeGh -Arguments @('issue', 'view', [string]$Issue, '--repo', $Repository, '--json', 'comments')
        $bodies = @()
        foreach ($comment in @($data.comments)) { $bodies += [string]$comment.body }
        return ,$bodies
    }.GetNewClosure()

    $getIssuePrs = {
        param($Repository, $Issue)
        $json = 'number,state,isDraft,baseRefName,headRefName,headRefOid,url,mergeable,body,statusCheckRollup'
        $prs = & $InvokeGh -Arguments @('pr', 'list', '--repo', $Repository, '--state', 'all', '--search', "$Issue in:body", '--json', $json, '--limit', '500')
        $pattern = "(?im)\b(?:close[sd]?|fixe[sd]?|resolve[sd]?)\s+#$Issue\b"
        $result = @()
        foreach ($pr in @($prs)) {
            if ([string](Get-Prop -Object $pr -Name 'body') -notmatch $pattern) { continue }
            $rollup = Get-Prop -Object $pr -Name 'statusCheckRollup'
            $checks = @()
            $known = $null -ne $rollup
            foreach ($entry in @($rollup)) {
                $context = [string](Get-Prop -Object $entry -Name 'name')
                if ([string]::IsNullOrWhiteSpace($context)) { $context = [string](Get-Prop -Object $entry -Name 'context') }
                $conclusion = [string](Get-Prop -Object $entry -Name 'conclusion')
                if ([string]::IsNullOrWhiteSpace($conclusion)) { $conclusion = [string](Get-Prop -Object $entry -Name 'state') }
                $checks += [pscustomobject]@{ context = $context; conclusion = $conclusion}
            }
            $mergeable = [string](Get-Prop -Object $pr -Name 'mergeable')
            $result += [pscustomobject]@{
                number = [int](Get-Prop -Object $pr -Name 'number')
                state = [string](Get-Prop -Object $pr -Name 'state')
                isDraft = [bool](Get-Prop -Object $pr -Name 'isDraft' -Default $false)
                baseRefName = [string](Get-Prop -Object $pr -Name 'baseRefName')
                headRefName = [string](Get-Prop -Object $pr -Name 'headRefName')
                headSha = [string](Get-Prop -Object $pr -Name 'headRefOid')
                url = [string](Get-Prop -Object $pr -Name 'url')
                hasConflict = ($mergeable -eq 'CONFLICTING')
                checks = $checks
                checksKnown = $known
            }
        }
        return ,$result
    }.GetNewClosure()

    $getBlockerIssues = {
        param($Repository, $Ids)
        $map = @{}
        foreach ($id in @($Ids)) {
            if ($id -notmatch '#(?<n>\d+)$') { continue }
            $number = [int]$Matches['n']
            $data = & $InvokeGh -Arguments @('issue', 'view', [string]$number, '--repo', $Repository, '--json', 'state,stateReason')
            $map[[string]$id] = [pscustomobject]@{ state = [string](Get-Prop -Object $data -Name 'state'); stateReason = [string](Get-Prop -Object $data -Name 'stateReason') }
        }
        return $map
    }.GetNewClosure()

    $getRefSha = {
        param($Ref)
        $output = & git rev-parse --verify --quiet $Ref 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ([string]$output).Trim()
    }.GetNewClosure()

    return [pscustomobject]@{
        GetDefaultBranch = $getDefaultBranch
        GetSubIssues     = $getSubIssues
        GetProjectState  = $getProjectState
        GetIssueComments = $getIssueComments
        GetIssuePrs      = $getIssuePrs
        GetBlockerIssues = $getBlockerIssues
        GetRefSha        = $getRefSha
    }
}
```

- [ ] **Step 5: Implementar o CLI do coletor**

Crie `delivery-queue/src/Get-QueueSnapshot.ps1`:

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [int]$Epic,
    [Parameter(Mandatory)] [string]$Repository,
    [string]$PolicyPath = '.delivery-queue/policy.json',
    [AllowEmptyCollection()] [int[]]$Only = @(),
    [string]$OutputPath,
    [AllowNull()] [object]$GhAdapter = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Pages.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Attempt.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Common.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Gh.ps1')

$loaded = Read-DeliveryQueuePolicy -Path $PolicyPath
if (-not $loaded.Ok) {
    [Console]::Error.WriteLine(($loaded.Messages -join '; '))
    exit 4
}

if ($Repository -notmatch '^[^/]+/[^/]+$') {
    [Console]::Error.WriteLine("repository invalido: $Repository")
    exit 4
}

$gh = $GhAdapter
if ($null -eq $gh) { $gh = New-DeliveryQueueGhAdapter }

$filter = [pscustomobject]@{ only = $Only }
$result = New-QueueSnapshot -Repository $Repository -Epic $Epic -Policy $loaded.Policy -Gh $gh -Filter $filter

if (-not $result.Ok) {
    [Console]::Error.WriteLine(($result.Error.Messages -join '; '))
    exit 4
}

$json = $result.Snapshot | ConvertTo-Json -Depth 30
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $json
}
else {
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
}

exit 0
```

- [ ] **Step 6: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.CollectorCli.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 12, Failed: 0`.

- [ ] **Step 7: Rodar a suite inteira**

Run: `Invoke-Pester -Path "delivery-queue/tests" -Output Detailed`
Expected: `Failed: 0`.

- [ ] **Step 8: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Common.ps1 delivery-queue/src/DeliveryQueue.Gh.ps1 delivery-queue/src/Get-QueueSnapshot.ps1 delivery-queue/tests/DeliveryQueue.CollectorCli.Tests.ps1
git commit -m "feat(delivery-queue): gh adapter, policy loader and snapshot CLI"
```

---

### Task 7: Driver puro — preflight, selecao de acao, resumo e codigos de saida

**Files:**
- Create: `delivery-queue/src/DeliveryQueue.DriverCore.ps1`
- Test: `delivery-queue/tests/DeliveryQueue.DriverCore.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Prop`, `Get-Array`, `Test-DeliveryQueuePolicy`.
- Produces:
  - `Test-DeliveryQueuePreflight -Policy <object> -Options <object> -DefaultBranchName <string|null> -> string[]`.
  - `Select-DeliveryAction -Plan <object> [-Attempted <int[]>] [-MaxIssues <int>] [-HasLimit <bool>] -> [pscustomobject]@{ Kind; Issue }`, `Kind` em `recover|update_branch|merge|dispatch|limit|none`.
  - `New-DeliverySummary -Plan <object> [-Attempted <int[]>] [-Infra <bool>] [-Cancelled <bool>] [-LimitReached <bool>] [-Messages <string[]>] -> [pscustomobject]`.
  - `Get-DeliveryExitCode -Summary <object> -> int`.
  - `New-AttemptId -Now <string> -Suffix <int> -> string`.
  - `Get-BranchSlug -Title <string> -> string`.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.DriverCore.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.DriverCore.ps1"
    . "$PSScriptRoot/TestHelpers.ps1"

    function New-PlanIssue {
        param($IssueId, $Number, $Status, $Reason = $null, $NextAction = 'none')
        [pscustomobject]@{ IssueId = $IssueId; Number = $Number; Status = $Status; Reason = $Reason; NextAction = $NextAction; Blockers = @(); PrNumber = $null; PrUrl = $null; Branch = ''; AttemptId = '' }
    }
    function New-Plan {
        param($Issues)
        [pscustomobject]@{ Repository = 'o/r'; Epic = 9; Error = $null; Order = @(); Runnable = @(); Issues = $Issues; Diagnostics = @() }
    }
}

Describe 'Test-DeliveryQueuePreflight' {
    It 'aprova politica e opcoes validas' {
        $options = [pscustomobject]@{ Repository = 'o/r'; MaxIssues = $null; WorkerTimeoutMinutes = 60 }
        (Test-DeliveryQueuePreflight -Policy (New-TestPolicy) -Options $options -DefaultBranchName 'master').Count | Should -Be 0
    }
    It 'reprova repository sem owner/repo' {
        $options = [pscustomobject]@{ Repository = 'sem-barra'; MaxIssues = $null; WorkerTimeoutMinutes = 60 }
        (Test-DeliveryQueuePreflight -Policy (New-TestPolicy) -Options $options -DefaultBranchName 'master') | Should -Match 'repository invalido'
    }
    It 'reprova MaxIssues nao positivo' {
        $options = [pscustomobject]@{ Repository = 'o/r'; MaxIssues = 0; WorkerTimeoutMinutes = 60 }
        (Test-DeliveryQueuePreflight -Policy (New-TestPolicy) -Options $options -DefaultBranchName 'master') | Should -Match 'MaxIssues'
    }
    It 'reprova divergencia de defaultBranch' {
        $options = [pscustomobject]@{ Repository = 'o/r'; MaxIssues = $null; WorkerTimeoutMinutes = 60 }
        (Test-DeliveryQueuePreflight -Policy (New-TestPolicy) -Options $options -DefaultBranchName 'main') | Should -Match 'policy_conflict'
    }
}

Describe 'Select-DeliveryAction' {
    It 'prioriza recuperacao antes de merge e dispatch' {
        $plan = New-Plan @(
            (New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'in_progress' -Reason 'merge_pending' -NextAction 'reconcile'),
            (New-PlanIssue -IssueId 'o/r#2' -Number 2 -Status 'runnable' -NextAction 'implement')
        )
        $a = Select-DeliveryAction -Plan $plan
        $a.Kind | Should -Be 'recover'
        $a.Issue.Number | Should -Be 1
    }
    It 'seleciona update_branch' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'in_progress' -NextAction 'update_branch'))
        (Select-DeliveryAction -Plan $plan).Kind | Should -Be 'update_branch'
    }
    It 'seleciona merge' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'in_progress' -NextAction 'merge'))
        (Select-DeliveryAction -Plan $plan).Kind | Should -Be 'merge'
    }
    It 'despacha runnable' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'runnable' -NextAction 'implement'))
        (Select-DeliveryAction -Plan $plan).Kind | Should -Be 'dispatch'
    }
    It 'respeita o teto quando so ha dispatch' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'runnable' -NextAction 'implement'))
        $a = Select-DeliveryAction -Plan $plan -Attempted @(1) -HasLimit $true -MaxIssues 1
        $a.Kind | Should -Be 'limit'
    }
    It 'merge nao consome o teto' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'in_progress' -NextAction 'merge'))
        (Select-DeliveryAction -Plan $plan -Attempted @(2) -HasLimit $true -MaxIssues 1).Kind | Should -Be 'merge'
    }
    It 'retorna none sem acao elegivel' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'blocked' -Reason 'blocked_by_issue'))
        (Select-DeliveryAction -Plan $plan).Kind | Should -Be 'none'
    }
}

Describe 'New-DeliverySummary e Get-DeliveryExitCode' {
    It 'aguardando merge conta como bloqueado e sai com 2' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'blocked' -Reason 'awaiting_merge' -NextAction 'wait_merge'))
        $s = New-DeliverySummary -Plan $plan
        $s.Blocked | Should -Be 1
        (Get-DeliveryExitCode -Summary $s) | Should -Be 2
    }
    It 'checks pendentes sao bloqueio e saem com 2' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'in_progress' -Reason 'checks_pending' -NextAction 'wait_checks'))
        (Get-DeliveryExitCode -Summary (New-DeliverySummary -Plan $plan)) | Should -Be 2
    }
    It 'tudo done sai com 0' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'done' -NextAction 'reconcile'))
        (Get-DeliveryExitCode -Summary (New-DeliverySummary -Plan $plan)) | Should -Be 0
    }
    It 'failed tem precedencia sobre blocked' {
        $plan = New-Plan @(
            (New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'failed' -Reason 'needs_manual'),
            (New-PlanIssue -IssueId 'o/r#2' -Number 2 -Status 'blocked' -Reason 'awaiting_merge')
        )
        (Get-DeliveryExitCode -Summary (New-DeliverySummary -Plan $plan)) | Should -Be 3
    }
    It 'infra tem precedencia sobre tudo' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'failed'))
        (Get-DeliveryExitCode -Summary (New-DeliverySummary -Plan $plan -Infra $true)) | Should -Be 4
    }
    It 'cancelado sai 130' {
        (Get-DeliveryExitCode -Summary (New-DeliverySummary -Plan (New-Plan @()) -Cancelled $true)) | Should -Be 130
    }
    It 'limite sai 1' {
        (Get-DeliveryExitCode -Summary (New-DeliverySummary -Plan (New-Plan @()) -LimitReached $true)) | Should -Be 1
    }
}

Describe 'New-AttemptId e Get-BranchSlug' {
    It 'monta o attemptId a partir do instante UTC' {
        New-AttemptId -Now '2026-09-18T14:22:00Z' -Suffix 1 | Should -Be '20260918T1422Z-0001'
    }
    It 'gera slug ascii a partir do titulo' {
        Get-BranchSlug -Title 'Seletor de Regiao (v2)!' | Should -Be 'seletor-de-regiao-v2'
    }
    It 'usa fallback quando o titulo nao gera slug' {
        Get-BranchSlug -Title '###' | Should -Be 'issue'
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.DriverCore.Tests.ps1" -Output Detailed`
Expected: FAIL (`DeliveryQueue.DriverCore.ps1` nao existe).

- [ ] **Step 3: Implementar**

Crie `delivery-queue/src/DeliveryQueue.DriverCore.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')

function Test-DeliveryQueuePreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Options,
        [AllowNull()] [string]$DefaultBranchName
    )

    $problems = @()
    $problems += Test-DeliveryQueuePolicy -Policy $Policy

    $repository = [string](Get-Prop -Object $Options -Name 'Repository')
    if ($repository -notmatch '^[^/]+/[^/]+$') {
        $problems += "repository invalido: '$repository'"
    }

    $max = Get-Prop -Object $Options -Name 'MaxIssues'
    if ($null -ne $max -and [int]$max -lt 1) {
        $problems += 'MaxIssues deve ser um inteiro positivo'
    }

    $timeout = Get-Prop -Object $Options -Name 'WorkerTimeoutMinutes'
    if ($null -ne $timeout -and [int]$timeout -lt 1) {
        $problems += 'WorkerTimeoutMinutes deve ser um inteiro positivo'
    }

    $policyBranch = [string](Get-Prop -Object $Policy -Name 'defaultBranch')
    if (-not [string]::IsNullOrWhiteSpace($DefaultBranchName) -and $policyBranch -ne $DefaultBranchName) {
        $problems += "policy_conflict: defaultBranch da policy '$policyBranch' difere de '$DefaultBranchName'"
    }

    return ,$problems
}

function Select-DeliveryAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Plan,
        [AllowEmptyCollection()] [int[]]$Attempted = @(),
        [int]$MaxIssues = 0,
        [bool]$HasLimit = $false
    )

    $issues = Get-Array -Value (Get-Prop -Object $Plan -Name 'Issues')

    foreach ($issue in $issues) {
        $action = [string](Get-Prop -Object $issue -Name 'NextAction')
        if ($action -eq 'reconcile') { return [pscustomobject]@{ Kind = 'recover'; Issue = $issue } }
    }
    foreach ($issue in $issues) {
        if ([string](Get-Prop -Object $issue -Name 'NextAction') -eq 'update_branch') {
            return [pscustomobject]@{ Kind = 'update_branch'; Issue = $issue }
        }
    }
    foreach ($issue in $issues) {
        if ([string](Get-Prop -Object $issue -Name 'NextAction') -eq 'merge') {
            return [pscustomobject]@{ Kind = 'merge'; Issue = $issue }
        }
    }
    foreach ($issue in $issues) {
        if ([string](Get-Prop -Object $issue -Name 'Status') -eq 'runnable') {
            if ($HasLimit -and $Attempted.Count -ge $MaxIssues) {
                return [pscustomobject]@{ Kind = 'limit'; Issue = $null }
            }
            return [pscustomobject]@{ Kind = 'dispatch'; Issue = $issue }
        }
    }

    return [pscustomobject]@{ Kind = 'none'; Issue = $null }
}

function New-DeliverySummary {
    [CmdletBinding()]
    param(
        [AllowNull()] [object]$Plan,
        [AllowEmptyCollection()] [int[]]$Attempted = @(),
        [bool]$Infra = $false,
        [bool]$Cancelled = $false,
        [bool]$LimitReached = $false,
        [AllowEmptyCollection()] [string[]]$Messages = @()
    )

    $lines = @()
    $failed = 0
    $blocked = 0
    $done = 0
    $excluded = 0
    $runnable = 0
    $allDelivered = $true

    $issues = @()
    if ($null -ne $Plan) { $issues = Get-Array -Value (Get-Prop -Object $Plan -Name 'Issues') }

    foreach ($issue in $issues) {
        $id = [string](Get-Prop -Object $issue -Name 'IssueId')
        $status = [string](Get-Prop -Object $issue -Name 'Status')
        $reason = [string](Get-Prop -Object $issue -Name 'Reason')
        $action = [string](Get-Prop -Object $issue -Name 'NextAction')

        switch ($status) {
            'failed' { $failed++ }
            'blocked' { $blocked++ }
            'done' { $done++ }
            'excluded' { $excluded++ }
            'runnable' { $runnable++ }
            'in_progress' {
                if ($reason -in @('checks_pending', 'merge_pending')) { $blocked++ }
            }
        }

        if ($status -notin @('done', 'excluded')) { $allDelivered = $false }

        $pr = [string](Get-Prop -Object $issue -Name 'PrNumber')
        $lines += ('{0}: status={1} reason={2} action={3} pr={4}' -f $id, $status, $reason, $action, $pr)
    }

    foreach ($message in @($Messages)) { $lines += "nota: $message" }

    return [pscustomobject]@{
        Infra = $Infra
        Cancelled = $Cancelled
        LimitReached = $LimitReached
        Failed = $failed
        Blocked = $blocked
        Done = $done
        Excluded = $excluded
        Runnable = $runnable
        AllDelivered = $allDelivered
        Text = ($lines -join "`n")
    }
}

function Get-DeliveryExitCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Summary)

    if ([bool](Get-Prop -Object $Summary -Name 'Infra' -Default $false)) { return 4 }
    if ([bool](Get-Prop -Object $Summary -Name 'Cancelled' -Default $false)) { return 130 }
    if ([int](Get-Prop -Object $Summary -Name 'Failed' -Default 0) -gt 0) { return 3 }
    if ([int](Get-Prop -Object $Summary -Name 'Blocked' -Default 0) -gt 0) { return 2 }
    if ([bool](Get-Prop -Object $Summary -Name 'LimitReached' -Default $false)) { return 1 }
    return 0
}

function New-AttemptId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Now,
        [Parameter(Mandatory)] [int]$Suffix
    )

    $stamp = $null
    try {
        $stamp = ([datetimeoffset]::Parse($Now)).UtcDateTime.ToString('yyyyMMddTHHmmZ')
    }
    catch {
        $stamp = ($Now -replace '[^0-9TZ]', '')
    }
    if ([string]::IsNullOrWhiteSpace($stamp)) { $stamp = '00000000T0000Z' }
    return ('{0}-{1:x4}' -f $stamp, $Suffix)
}

function Get-BranchSlug {
    [CmdletBinding()]
    param([AllowNull()] [string]$Title)

    $slug = ([string]$Title).ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'issue' }
    if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).Trim('-') }
    return $slug
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.DriverCore.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 19, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.DriverCore.ps1 delivery-queue/tests/DeliveryQueue.DriverCore.Tests.ps1
git commit -m "feat(delivery-queue): driver preflight, action selection, summary and exit codes"
```

---

### Task 8: Gate puro — evidencia, review, handoff e prontidao

**Files:**
- Modify: `delivery-queue/src/DeliveryQueue.DriverCore.ps1` (append)
- Test: `delivery-queue/tests/DeliveryQueue.Gate.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Prop`, `Get-Array`, `Test-RemoteChecksComplete`.
- Produces:
  - `Test-LocalEvidenceContract -Evidence <object[]> -Policy <object> -HeadSha <string|null> -> bool` — exige, para cada comando de `requiredChecks`, um item `{ command; result='pass'; headSha=<atual>; at }`.
  - `Test-ReviewContract -Attempt <object|null> -HeadSha <string|null> -> bool` — `iterations` entre 1 e 3, `blocking=0`, `headSha` atual.
  - `Test-HandoffContract -Attempt <object|null> -> bool` — `status` em `delivered|merged` e campos obrigatorios nao vazios.
  - `Test-MergeReadiness -Pr <object|null> -Attempt <object|null> -Policy <object> -HeadSha <string|null> -> [pscustomobject]@{ Ready; Reasons }`.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.Gate.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.DriverCore.ps1"
    . "$PSScriptRoot/TestHelpers.ps1"

    function New-Evidence {
        param($Command, $Result = 'pass', $HeadSha = 'h1', $At = '2026-09-18T10:00:00Z')
        [pscustomobject]@{ command = $Command; result = $Result; headSha = $HeadSha; at = $At }
    }
    function New-Review {
        param($Iterations = 1, $Blocking = 0, $HeadSha = 'h1')
        [pscustomobject]@{ iterations = $Iterations; blocking = $Blocking; headSha = $HeadSha }
    }
    function New-Attempt {
        param($Status = 'delivered', $Review = $null, $Checks = @(), $HeadSha = 'h1')
        [pscustomobject]@{ attemptId = 'a1'; repository = 'o/r'; epic = 9; issue = 1; branch = 'feat/1-x'; status = $Status; review = $Review; checks = $Checks; headSha = $HeadSha; pr = 7; nextAction = 'merge' }
    }
}

Describe 'Test-LocalEvidenceContract' {
    It 'aceita evidencia completa no head atual' {
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'npm run build')) -Policy (New-TestPolicy) -HeadSha 'h1') | Should -BeTrue
    }
    It 'rejeita evidencia de head antigo' {
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'npm run build' -HeadSha 'velho')) -Policy (New-TestPolicy) -HeadSha 'h1') | Should -BeFalse
    }
    It 'rejeita evidencia sem at' {
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'npm run build' -At '')) -Policy (New-TestPolicy) -HeadSha 'h1') | Should -BeFalse
    }
    It 'rejeita comando fora de requiredChecks' {
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'echo oi')) -Policy (New-TestPolicy) -HeadSha 'h1') | Should -BeFalse
    }
    It 'rejeita resultado nao pass' {
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'npm run build' -Result 'fail')) -Policy (New-TestPolicy) -HeadSha 'h1') | Should -BeFalse
    }
    It 'exige todos os requiredChecks' {
        $policy = New-TestPolicy
        $policy.requiredChecks = @('npm run build', 'npm run typecheck')
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'npm run build')) -Policy $policy -HeadSha 'h1') | Should -BeFalse
    }
}

Describe 'Test-ReviewContract' {
    It 'aceita review valido' { (Test-ReviewContract -Attempt (New-Attempt -Review (New-Review)) -HeadSha 'h1') | Should -BeTrue }
    It 'rejeita zero iteracoes' { (Test-ReviewContract -Attempt (New-Attempt -Review (New-Review -Iterations 0)) -HeadSha 'h1') | Should -BeFalse }
    It 'rejeita mais de tres iteracoes' { (Test-ReviewContract -Attempt (New-Attempt -Review (New-Review -Iterations 4)) -HeadSha 'h1') | Should -BeFalse }
    It 'rejeita achado bloqueante' { (Test-ReviewContract -Attempt (New-Attempt -Review (New-Review -Blocking 1)) -HeadSha 'h1') | Should -BeFalse }
    It 'rejeita review de head antigo' { (Test-ReviewContract -Attempt (New-Attempt -Review (New-Review -HeadSha 'velho')) -HeadSha 'h1') | Should -BeFalse }
    It 'rejeita sem review' { (Test-ReviewContract -Attempt (New-Attempt) -HeadSha 'h1') | Should -BeFalse }
}

Describe 'Test-HandoffContract' {
    It 'aceita handoff delivered com campos' { (Test-HandoffContract -Attempt (New-Attempt)) | Should -BeTrue }
    It 'aceita handoff merged' { (Test-HandoffContract -Attempt (New-Attempt -Status 'merged')) | Should -BeTrue }
    It 'rejeita status started' { (Test-HandoffContract -Attempt (New-Attempt -Status 'started')) | Should -BeFalse }
    It 'rejeita sem tentativa' { (Test-HandoffContract -Attempt $null) | Should -BeFalse }
}

Describe 'Test-MergeReadiness' {
    function New-Pr {
        param($State = 'OPEN', $IsDraft = $false, $HasConflict = $false, $ChecksComplete = $true, $HeadSha = 'h1')
        [pscustomobject]@{ number = 7; state = $State; isDraft = $IsDraft; hasConflict = $HasConflict; checksComplete = $ChecksComplete; headSha = $HeadSha; url = 'u'; baseRefName = 'master'; headRefName = 'feat/1-x' }
    }
    It 'pronta quando PR, review, handoff e evidencias conferem' {
        $attempt = New-Attempt -Review (New-Review) -Checks @((New-Evidence -Command 'npm run build'))
        $r = Test-MergeReadiness -Pr (New-Pr) -Attempt $attempt -Policy (New-TestPolicy) -HeadSha 'h1'
        $r.Ready | Should -BeTrue
        $r.Reasons.Count | Should -Be 0
    }
    It 'nao pronta com draft' {
        $attempt = New-Attempt -Review (New-Review) -Checks @((New-Evidence -Command 'npm run build'))
        $r = Test-MergeReadiness -Pr (New-Pr -IsDraft $true) -Attempt $attempt -Policy (New-TestPolicy) -HeadSha 'h1'
        $r.Ready | Should -BeFalse
        $r.Reasons | Should -Contain 'draft'
    }
    It 'nao pronta com conflito' {
        $attempt = New-Attempt -Review (New-Review) -Checks @((New-Evidence -Command 'npm run build'))
        (Test-MergeReadiness -Pr (New-Pr -HasConflict $true) -Attempt $attempt -Policy (New-TestPolicy) -HeadSha 'h1').Reasons | Should -Contain 'conflito'
    }
    It 'nao pronta com checks remotos incompletos' {
        $attempt = New-Attempt -Review (New-Review) -Checks @((New-Evidence -Command 'npm run build'))
        (Test-MergeReadiness -Pr (New-Pr -ChecksComplete $false) -Attempt $attempt -Policy (New-TestPolicy) -HeadSha 'h1').Reasons | Should -Contain 'checks_remotos'
    }
    It 'nao pronta com head divergente' {
        $attempt = New-Attempt -Review (New-Review) -Checks @((New-Evidence -Command 'npm run build'))
        (Test-MergeReadiness -Pr (New-Pr -HeadSha 'velho') -Attempt $attempt -Policy (New-TestPolicy) -HeadSha 'h1').Reasons | Should -Contain 'head_divergente'
    }
    It 'nao pronta sem PR' {
        (Test-MergeReadiness -Pr $null -Attempt (New-Attempt) -Policy (New-TestPolicy) -HeadSha 'h1').Reasons | Should -Contain 'sem_pr'
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Gate.Tests.ps1" -Output Detailed`
Expected: FAIL em `Test-LocalEvidenceContract: CommandNotFoundException`.

- [ ] **Step 3: Implementar**

Acrescente ao final de `delivery-queue/src/DeliveryQueue.DriverCore.ps1`:

```powershell
function Test-LocalEvidenceContract {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [object[]]$Evidence = @(),
        [Parameter(Mandatory)] [object]$Policy,
        [AllowNull()] [string]$HeadSha
    )

    $current = [string]$HeadSha
    if ([string]::IsNullOrWhiteSpace($current)) { return $false }

    $required = Get-Array -Value (Get-Prop -Object $Policy -Name 'requiredChecks')

    foreach ($command in $required) {
        $found = $false
        foreach ($item in @($Evidence)) {
            if ([string](Get-Prop -Object $item -Name 'command') -ne [string]$command) { continue }
            if ([string](Get-Prop -Object $item -Name 'result') -ne 'pass') { continue }
            if ([string](Get-Prop -Object $item -Name 'headSha') -ne $current) { continue }
            if ([string]::IsNullOrWhiteSpace([string](Get-Prop -Object $item -Name 'at'))) { continue }
            $found = $true
            break
        }
        if (-not $found) { return $false }
    }

    return $true
}

function Test-ReviewContract {
    [CmdletBinding()]
    param(
        [AllowNull()] [object]$Attempt,
        [AllowNull()] [string]$HeadSha
    )

    $review = Get-Prop -Object $Attempt -Name 'review'
    if ($null -eq $review) { return $false }

    $iterations = [int](Get-Prop -Object $review -Name 'iterations' -Default 0)
    if ($iterations -lt 1 -or $iterations -gt 3) { return $false }

    if ([int](Get-Prop -Object $review -Name 'blocking' -Default 1) -ne 0) { return $false }

    $reviewSha = [string](Get-Prop -Object $review -Name 'headSha')
    if ([string]::IsNullOrWhiteSpace($reviewSha)) { return $false }
    if ($reviewSha -ne [string]$HeadSha) { return $false }

    return $true
}

function Test-HandoffContract {
    [CmdletBinding()]
    param([AllowNull()] [object]$Attempt)

    if ($null -eq $Attempt) { return $false }

    if ([string](Get-Prop -Object $Attempt -Name 'status') -notin @('delivered', 'merged')) { return $false }

    foreach ($field in @('attemptId', 'repository', 'issue', 'branch')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-Prop -Object $Attempt -Name $field))) { return $false }
    }

    return $true
}

function Test-MergeReadiness {
    [CmdletBinding()]
    param(
        [AllowNull()] [object]$Pr,
        [AllowNull()] [object]$Attempt,
        [Parameter(Mandatory)] [object]$Policy,
        [AllowNull()] [string]$HeadSha
    )

    $reasons = @()

    if ($null -eq $Pr) {
        $reasons += 'sem_pr'
    }
    else {
        if ([string](Get-Prop -Object $Pr -Name 'state') -ne 'OPEN') { $reasons += 'pr_nao_aberta' }
        if ([bool](Get-Prop -Object $Pr -Name 'isDraft' -Default $false)) { $reasons += 'draft' }
        if ([bool](Get-Prop -Object $Pr -Name 'hasConflict' -Default $false)) { $reasons += 'conflito' }
        if ([bool](Get-Prop -Object $Pr -Name 'checksComplete' -Default $false) -ne $true) { $reasons += 'checks_remotos' }
        if ([string](Get-Prop -Object $Pr -Name 'headSha') -ne [string]$HeadSha) { $reasons += 'head_divergente' }
    }

    $evidence = Get-Array -Value (Get-Prop -Object $Attempt -Name 'checks')
    if (-not (Test-LocalEvidenceContract -Evidence $evidence -Policy $Policy -HeadSha $HeadSha)) {
        $reasons += 'evidencia_local'
    }
    if (-not (Test-ReviewContract -Attempt $Attempt -HeadSha $HeadSha)) { $reasons += 'review' }
    if (-not (Test-HandoffContract -Attempt $Attempt)) { $reasons += 'handoff' }

    return [pscustomobject]@{ Ready = ($reasons.Count -eq 0); Reasons = $reasons }
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Gate.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 22, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.DriverCore.ps1 delivery-queue/tests/DeliveryQueue.Gate.Tests.ps1
git commit -m "feat(delivery-queue): merge gate contracts"
```

---

### Task 9: Loop do driver com efeitos injetados

**Files:**
- Create: `delivery-queue/src/DeliveryQueue.Driver.ps1`
- Modify: `delivery-queue/tests/TestHelpers.ps1` (append `New-IoFake`)
- Test: `delivery-queue/tests/DeliveryQueue.DriverLoop.Tests.ps1`

**Interfaces:**
- Consumes: `Resolve-QueuePlan`, `Select-DeliveryAction`, `Test-MergeReadiness`, `New-DeliverySummary`, `New-AttemptRecord`, `ConvertTo-AttemptComment`, `Get-BranchSlug`, `New-AttemptId`.
- Produces:
  - `Invoke-DeliveryLoop -Policy <object> -Options <object> -Io <object> -> [pscustomobject]` (o resumo). `Options` tem `Repository`, `Epic`, `MaxIssues`, `HasLimit`, `Only`, `Retry`, `WorkerTimeoutMinutes`, `WhatIf`.
  - Helpers de acao: `Invoke-RecoverAction`, `Invoke-UpdateBranchAction`, `Invoke-MergeAction`, `Invoke-DispatchAction`, todos `-Io -Policy -Options -Issue [-Repository] [-Suffix]` e retornam `string[]` de mensagens.

**Contrato `$Io` deste task:** `GetNow`, `Log`, `Sleep -Seconds`, `IsCancelled`, `Collect -Repository -Epic -Only`, `AcquireLock -Repository`, `ReleaseLock -Lock`, `FetchDefault -Repository -Branch`, `EnsureWorktree -Repository -Branch -Base -Root`, `ReadAttempt -Repository -Issue`, `UpsertAttempt -Repository -Issue -Record`, `DispatchWorker -Issue -Repository -Base -Worktree -TimeoutMinutes`, `GetPr -Repository -Number`, `RunLocalChecks -Worktree -Commands`, `UpdateBranch -Repository -Number -Base`, `MergePr -Repository -Number -Method -HeadSha -AllowAdmin`, `VerifyPostMerge -Repository -Branch -Commands`, `WriteSummary -Text`.

- [ ] **Step 1: Escrever os testes que falham**

Acrescente ao final de `delivery-queue/tests/TestHelpers.ps1`:

```powershell
function New-IoFake {
    [CmdletBinding()]
    param(
        [scriptblock]$Collect, [scriptblock]$AcquireLock, [scriptblock]$ReleaseLock,
        [scriptblock]$FetchDefault, [scriptblock]$GetDefaultHead, [scriptblock]$EnsureWorktree,
        [scriptblock]$ReadAttempt, [scriptblock]$UpsertAttempt, [scriptblock]$DispatchWorker,
        [scriptblock]$GetPr, [scriptblock]$RunLocalChecks, [scriptblock]$UpdateBranch,
        [scriptblock]$MergePr, [scriptblock]$VerifyPostMerge, [scriptblock]$WriteSummary,
        [scriptblock]$GetNow, [scriptblock]$IsCancelled, [scriptblock]$Sleep, [scriptblock]$Log
    )

    if (-not $Collect) { $Collect = { param($Repository, $Epic, $Only) throw 'Collect fake nao configurado' } }
    if (-not $AcquireLock) { $AcquireLock = { param($Repository) [pscustomobject]@{ Acquired = $true; Path = 'lock'; Stream = $null; Repository = $Repository } } }
    if (-not $ReleaseLock) { $ReleaseLock = { param($Lock) } }
    if (-not $FetchDefault) { $FetchDefault = { param($Repository, $Branch) 'base-sha' } }
    if (-not $EnsureWorktree) { $EnsureWorktree = { param($Repository, $Branch, $Base, $Root) [pscustomobject]@{ path = 'wt'; branch = $Branch } } }
    if (-not $ReadAttempt) { $ReadAttempt = { param($Repository, $Issue) $null } }
    if (-not $UpsertAttempt) { $UpsertAttempt = { param($Repository, $Issue, $Record) 'c1' } }
    if (-not $DispatchWorker) { $DispatchWorker = { param($Issue, $Repository, $Base, $Worktree, $TimeoutMinutes) [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' } } }
    if (-not $GetPr) { $GetPr = { param($Repository, $Number) [pscustomobject]@{ number = $Number; state = 'OPEN'; isDraft = $false; hasConflict = $false; checksComplete = $true; headSha = 'h1'; url = 'u'; baseRefName = 'master'; headRefName = 'feat/x' } } }
    if (-not $RunLocalChecks) { $RunLocalChecks = { param($Worktree, $Commands) @() } }
    if (-not $UpdateBranch) { $UpdateBranch = { param($Repository, $Number, $Base) [pscustomobject]@{ updated = $true; conflict = $false } } }
    if (-not $MergePr) { $MergePr = { param($Repository, $Number, $Method, $HeadSha, $AllowAdmin) [pscustomobject]@{ state = 'MERGED'; mergeCommit = 'm1'; mergedAt = 't' } } }
    if (-not $VerifyPostMerge) { $VerifyPostMerge = { param($Repository, $Branch, $Commands) [pscustomobject]@{ baseSha = 'base-sha'; result = 'pass'; at = 't' } } }
    if (-not $WriteSummary) { $WriteSummary = { param($Text) } }
    if (-not $GetNow) { $GetNow = { '2026-09-18T14:22:00Z' } }
    if (-not $GetDefaultHead) { $GetDefaultHead = { param($Repository, $Branch) 'base-sha' } }
    if (-not $IsCancelled) { $IsCancelled = { $false } }
    if (-not $Sleep) { $Sleep = { param($Seconds) } }
    if (-not $Log) { $Log = { param($Message) } }

    return [pscustomobject]@{
        Collect = $Collect; AcquireLock = $AcquireLock; ReleaseLock = $ReleaseLock
        FetchDefault = $FetchDefault; EnsureWorktree = $EnsureWorktree; ReadAttempt = $ReadAttempt
        UpsertAttempt = $UpsertAttempt; DispatchWorker = $DispatchWorker; GetPr = $GetPr
        RunLocalChecks = $RunLocalChecks; UpdateBranch = $UpdateBranch; MergePr = $MergePr
        VerifyPostMerge = $VerifyPostMerge; WriteSummary = $WriteSummary; GetNow = $GetNow
        GetDefaultHead = $GetDefaultHead; IsCancelled = $IsCancelled; Sleep = $Sleep; Log = $Log
    }
}
```

Crie `delivery-queue/tests/DeliveryQueue.DriverLoop.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Pages.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Attempt.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Collector.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.DriverCore.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Driver.ps1"
    . "$PSScriptRoot/TestHelpers.ps1"

    function New-Options {
        param($Policy, [int]$MaxIssues = 0, [int[]]$Only = @(), [bool]$Retry = $false, [bool]$WhatIf = $false)
        [pscustomobject]@{
            Repository = 'o/r'; Epic = 9; MaxIssues = $(if ($MaxIssues -gt 0) { $MaxIssues } else { $null })
            HasLimit = ($MaxIssues -gt 0); Only = $Only; Retry = $Retry
            WorkerTimeoutMinutes = 60; WhatIf = $WhatIf
        }
    }
    function New-Snapshot {
        param($Policy, [object[]]$Issues)
        $gh = New-GhFake -GetSubIssues ({ param($Repository, $Epic) $Issues }.GetNewClosure())
        return (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $Policy -Gh $gh).Snapshot
    }
    function New-Issue {
        param([int]$Number, [string]$State = 'OPEN', [object[]]$BlockedBy = @(), [object]$Pr = $null)
        [pscustomobject]@{ number = $Number; nodeId = "n$Number"; title = "Issue $Number"; state = $State; stateReason = $(if ($State -eq 'CLOSED') { 'COMPLETED' } else { $null }); labels = @(); blockedBy = $BlockedBy }
    }
}

Describe 'Invoke-DeliveryLoop' {
    It 'despacha a primeira issue e registra a tentativa' {
        $policy = New-TestPolicy
        $snapshots = New-Object System.Collections.Queue
        $snapshots.Enqueue((New-Snapshot -Policy $policy -Issues @((New-Issue -Number 1), (New-Issue -Number 2 -BlockedBy @('o/r#1')))))
        $snapshots.Enqueue((New-Snapshot -Policy $policy -Issues @((New-Issue -Number 1 -State 'CLOSED'))))
        $dispatchCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $snapshots.Dequeue() }.GetNewClosure()) `
            -DispatchWorker ({ param($Issue, $Repository, $Base, $Worktree, $TimeoutMinutes) $dispatchCount.Value++; [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' } }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io

        $dispatchCount.Value | Should -Be 1
        $summary.Failed | Should -Be 0
    }

    It 'respeita o teto -MaxIssues' {
        $policy = New-TestPolicy
        $snapshots = New-Object System.Collections.Queue
        $snapshots.Enqueue((New-Snapshot -Policy $policy -Issues @((New-Issue -Number 1), (New-Issue -Number 2))))
        $snapshots.Enqueue((New-Snapshot -Policy $policy -Issues @((New-Issue -Number 1), (New-Issue -Number 2))))
        $io = New-IoFake -Collect ({ param($Repository, $Epic, $Only) $snapshots.Dequeue() }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy -MaxIssues 1) -Io $io
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 1
    }

    It 'nao mergeia em modo humano e aguarda merge' {
        $policy = New-TestPolicy
        $pr = [pscustomobject]@{ number = 7; url = 'u'; state = 'OPEN'; isDraft = $false; baseRefName = 'master'; headRefName = 'feat/1'; headSha = 'h1'; hasConflict = $false; checks = @(); checksKnown = $true }
        $gh = New-GhFake -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() }) } -GetIssuePrs { param($Repository, $Issue) @($pr) }
        $snapshot = (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $policy -Gh $gh).Snapshot
        $snapshots = New-Object System.Collections.Queue
        $snapshots.Enqueue($snapshot)
        $mergeCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $snapshots.Dequeue() }.GetNewClosure()) `
            -MergePr ({ param($Repository, $Number, $Method, $HeadSha, $AllowAdmin) $mergeCount.Value++; [pscustomobject]@{ state = 'MERGED'; mergeCommit = 'm1'; mergedAt = 't' } }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io
        $mergeCount.Value | Should -Be 0
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 2
    }

    It 'mergeia em modo auto com gate verde e roda pos-merge' {
        $policy = New-TestPolicy -MergeMode 'auto' -Verify $true
        $pr = [pscustomobject]@{ number = 7; url = 'u'; state = 'OPEN'; isDraft = $false; baseRefName = 'master'; headRefName = 'feat/1'; headSha = 'h1'; hasConflict = $false; checks = @(); checksKnown = $true }
        $record = [pscustomobject]@{
            attemptId = 'a1'; repository = 'o/r'; epic = 9; issue = 1; branch = 'feat/1-x'; status = 'delivered'
            review = [pscustomobject]@{ iterations = 1; blocking = 0; headSha = 'h1' }
            checks = @([pscustomobject]@{ command = 'npm run build'; result = 'pass'; headSha = 'h1'; at = 't' })
            pr = 7; headSha = 'h1'
        }
        $open = (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $policy -Gh (New-GhFake -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() }) } -GetIssuePrs { param($Repository, $Issue) @($pr) })).Snapshot
        $done = (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $policy -Gh (New-GhFake -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'CLOSED'; stateReason = 'COMPLETED'; labels = @(); blockedBy = @() }) })).Snapshot
        $snapshots = New-Object System.Collections.Queue
        $snapshots.Enqueue($open); $snapshots.Enqueue($done)
        $mergeCount = [ref]0; $verifyCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $snapshots.Dequeue() }.GetNewClosure()) `
            -ReadAttempt ({ param($Repository, $Issue) $record }.GetNewClosure()) `
            -MergePr ({ param($Repository, $Number, $Method, $HeadSha, $AllowAdmin) $mergeCount.Value++; [pscustomobject]@{ state = 'MERGED'; mergeCommit = 'm1'; mergedAt = 't' } }.GetNewClosure()) `
            -VerifyPostMerge ({ param($Repository, $Branch, $Commands) $verifyCount.Value++; [pscustomobject]@{ baseSha = 'base-sha'; result = 'pass'; at = 't' } }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io
        $mergeCount.Value | Should -Be 1
        $verifyCount.Value | Should -Be 1
        $summary.Failed | Should -Be 0
    }

    It 'lock ocupado encerra como infra sem coletar' {
        $policy = New-TestPolicy
        $collectCount = [ref]0
        $io = New-IoFake `
            -AcquireLock { param($Repository) [pscustomobject]@{ Acquired = $false; Path = 'lock'; Stream = $null; Repository = $Repository } } `
            -Collect ({ param($Repository, $Epic, $Only) $collectCount.Value++; throw 'nao deveria coletar' }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io
        $collectCount.Value | Should -Be 0
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 4
    }

    It 'cancelamento encerra sem despachar' {
        $policy = New-TestPolicy
        $snapshots = New-Object System.Collections.Queue
        $snapshots.Enqueue((New-Snapshot -Policy $policy -Issues @((New-Issue -Number 1))))
        $dispatchCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $snapshots.Dequeue() }.GetNewClosure()) `
            -IsCancelled { $true } `
            -DispatchWorker ({ param($Issue, $Repository, $Base, $Worktree, $TimeoutMinutes) $dispatchCount.Value++; [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' } }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io
        $dispatchCount.Value | Should -Be 0
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 130
    }

    It 'falha de coleta persistente encerra como infra em no maximo tres tentativas' {
        $policy = New-TestPolicy
        $collectCount = [ref]0
        $io = New-IoFake -Collect ({ param($Repository, $Epic, $Only) $collectCount.Value++; throw 'api fora' }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io
        $collectCount.Value | Should -Be 3
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 4
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.DriverLoop.Tests.ps1" -Output Detailed`
Expected: FAIL (`DeliveryQueue.Driver.ps1` nao existe).

- [ ] **Step 3: Implementar**

Crie `delivery-queue/src/DeliveryQueue.Driver.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Attempt.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.DriverCore.ps1')

function Invoke-RecoverAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Io,
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Options,
        [Parameter(Mandatory)] [object]$Issue
    )

    $repository = [string]$Options.Repository
    $number = [int](Get-Prop -Object $Issue -Name 'Number')
    $prNumber = Get-Prop -Object $Issue -Name 'PrNumber'
    $messages = @()

    if ($null -eq $prNumber) {
        return @("issue $number: reconciliacao sem PR")
    }

    $pr = & $Io.GetPr -Repository $repository -Number ([int]$prNumber)
    $record = & $Io.ReadAttempt -Repository $repository -Issue $number

    if ($null -eq $record) {
        return @("issue $number: reconciliacao sem registro de tentativa")
    }

    if ([string](Get-Prop -Object $pr -Name 'state') -eq 'MERGED') {
        $merge = Get-Prop -Object $Policy -Name 'merge'
        if ([bool](Get-Prop -Object $merge -Name 'verifyDefaultBranchAfterMerge' -Default $false)) {
            $existing = Get-Prop -Object $record -Name 'postMerge'
            $currentHead = & $Io.GetDefaultHead -Repository $repository -Branch ([string](Get-Prop -Object $Policy -Name 'defaultBranch'))
            $valid = ([string](Get-Prop -Object $existing -Name 'result') -eq 'pass') -and ([string](Get-Prop -Object $existing -Name 'baseSha') -eq [string]$currentHead) -and (-not [string]::IsNullOrWhiteSpace([string]$currentHead))
            if (-not $valid) {
                $checked = & $Io.VerifyPostMerge -Repository $repository -Branch ([string](Get-Prop -Object $Policy -Name 'defaultBranch')) -Commands (Get-Array -Value (Get-Prop -Object $Policy -Name 'requiredChecks'))
                $record.postMerge = $checked
            }
        }
        $record.status = 'merged'
        $record.updatedAt = & $Io.GetNow
        & $Io.UpsertAttempt -Repository $repository -Issue $number -Record $record | Out-Null
        return @("issue $number: merge reconciliado")
    }

    return @("issue $number: merge pendente")
}

function Invoke-UpdateBranchAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Io,
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Options,
        [Parameter(Mandatory)] [object]$Issue
    )

    $repository = [string]$Options.Repository
    $number = [int](Get-Prop -Object $Issue -Name 'Number')
    $prNumber = Get-Prop -Object $Issue -Name 'PrNumber'
    $result = & $Io.UpdateBranch -Repository $repository -Number ([int]$prNumber) -Base ([string](Get-Prop -Object $Policy -Name 'defaultBranch'))

    $record = & $Io.ReadAttempt -Repository $repository -Issue $number
    if ($null -ne $record) {
        if ([bool](Get-Prop -Object $result -Name 'conflict' -Default $false)) {
            $record.status = 'blocked'
            $record.reason = 'needs_manual'
            $record.updatedAt = & $Io.GetNow
            & $Io.UpsertAttempt -Repository $repository -Issue $number -Record $record | Out-Null
            return @("issue $number: conflito nao resolvido, needs_manual")
        }
        $record.checks = @()
        $record.review = $null
        $record.status = 'started'
        $record.updatedAt = & $Io.GetNow
        & $Io.UpsertAttempt -Repository $repository -Issue $number -Record $record | Out-Null
    }

    return @("issue $number: branch atualizada, nova verificacao requerida")
}

function Invoke-MergeAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Io,
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Options,
        [Parameter(Mandatory)] [object]$Issue
    )

    $repository = [string]$Options.Repository
    $number = [int](Get-Prop -Object $Issue -Name 'Number')
    $prNumber = [int](Get-Prop -Object $Issue -Name 'PrNumber')
    $pr = & $Io.GetPr -Repository $repository -Number $prNumber
    $record = & $Io.ReadAttempt -Repository $repository -Issue $number
    $headSha = [string](Get-Prop -Object $pr -Name 'headSha')

    $readiness = Test-MergeReadiness -Pr $pr -Attempt $record -Policy $Policy -HeadSha $headSha
    if (-not $readiness.Ready) {
        return @("issue $number: gate recusou ($((Get-Array -Value $readiness.Reasons) -join ','))")
    }

    $merge = Get-Prop -Object $Policy -Name 'merge'
    $method = [string](Get-Prop -Object $merge -Name 'method')
    $allowAdmin = [bool](Get-Prop -Object $merge -Name 'allowAdminBypass' -Default $false)
    $result = & $Io.MergePr -Repository $repository -Number $prNumber -Method $method -HeadSha $headSha -AllowAdmin $allowAdmin

    $record.merge = [pscustomobject]@{ mergeCommit = Get-Prop -Object $result -Name 'mergeCommit'; method = $method }
    if ([string](Get-Prop -Object $result -Name 'state') -ne 'MERGED') {
        $record.status = 'delivered'
        $record.reason = 'merge_pending'
        $record.updatedAt = & $Io.GetNow
        & $Io.UpsertAttempt -Repository $repository -Issue $number -Record $record | Out-Null
        return @("issue $number: merge pendente (merge queue)")
    }

    $record.status = 'merged'
    $record.reason = $null
    $postMergeFailed = $false
    if ([bool](Get-Prop -Object $merge -Name 'verifyDefaultBranchAfterMerge' -Default $false)) {
        $record.postMerge = & $Io.VerifyPostMerge -Repository $repository -Branch ([string](Get-Prop -Object $Policy -Name 'defaultBranch')) -Commands (Get-Array -Value (Get-Prop -Object $Policy -Name 'requiredChecks'))
        if ([string](Get-Prop -Object $record.postMerge -Name 'result') -ne 'pass') {
            $postMergeFailed = $true
            $record.status = 'failed'
            $record.reason = 'post_merge_red'
        }
    }
    $record.updatedAt = & $Io.GetNow
    & $Io.UpsertAttempt -Repository $repository -Issue $number -Record $record | Out-Null
    if ($postMergeFailed) {
        return @("issue $number: pos-merge vermelho, loop encerra em failed")
    }
    return @("issue $number: merged")
}

function Invoke-DispatchAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Io,
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Options,
        [Parameter(Mandatory)] [object]$Issue,
        [int]$Suffix = 1
    )

    $repository = [string]$Options.Repository
    $number = [int](Get-Prop -Object $Issue -Name 'Number')
    $title = [string](Get-Prop -Object $Issue -Name 'Title')
    if ([string]::IsNullOrWhiteSpace($title)) { $title = "issue $number" }
    $branch = 'feat/{0}-{1}' -f $number, (Get-BranchSlug -Title $title)
    $base = [string](Get-Prop -Object $Policy -Name 'defaultBranch')

    $baseSha = & $Io.FetchDefault -Repository $repository -Branch $base
    $worktree = & $Io.EnsureWorktree -Repository $repository -Branch $branch -Base $base -Root ([string](Get-Prop -Object $Policy -Name 'worktreeRoot'))

    $attemptId = New-AttemptId -Now (& $Io.GetNow) -Suffix $Suffix
    $record = New-AttemptRecord -AttemptId $attemptId -Repository $repository -Epic ([int]$Options.Epic) -Issue $number `
        -Branch $branch -Base $base -BaseSha $baseSha -Now (& $Io.GetNow)
    & $Io.UpsertAttempt -Repository $repository -Issue $number -Record $record | Out-Null

    $result = & $Io.DispatchWorker -Issue $number -Repository $repository -Base $base -Worktree ([string](Get-Prop -Object $worktree -Name 'path')) -TimeoutMinutes ([int](Get-Prop -Object $Options -Name 'WorkerTimeoutMinutes'))

    $current = & $Io.ReadAttempt -Repository $repository -Issue $number
    if ($null -ne $current) { $record = $current }

    $evidence = @(& $Io.RunLocalChecks -Worktree ([string](Get-Prop -Object $worktree -Name 'path')) -Commands (Get-Array -Value (Get-Prop -Object $Policy -Name 'requiredChecks')))
    $record.checks = $evidence

    if ([bool](Get-Prop -Object $result -Name 'timedOut' -Default $false)) {
        $record.status = 'failed'
        $record.reason = 'timeout'
    }
    elseif ([int](Get-Prop -Object $result -Name 'exitCode' -Default 0) -ne 0 -and [string](Get-Prop -Object $record -Name 'status') -eq 'started') {
        $record.status = 'failed'
        $record.reason = 'worker_failed'
    }

    $record.updatedAt = & $Io.GetNow
    & $Io.UpsertAttempt -Repository $repository -Issue $number -Record $record | Out-Null

    return @("issue $number: despachada em $branch")
}

function Invoke-DeliveryLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Options,
        [Parameter(Mandatory)] [object]$Io
    )

    $attempted = @()
    $messages = @()
    $infra = $false
    $cancelled = $false
    $limit = $false
    $plan = $null
    $lock = $null

    try {
        $preflight = Test-DeliveryQueuePreflight -Policy $Policy -Options $Options -DefaultBranchName $null
        if ($preflight.Count -gt 0) {
            foreach ($problem in $preflight) { $messages += $problem }
            $infra = $true
            $summary = New-DeliverySummary -Plan $null -Attempted $attempted -Infra $infra -Messages $messages
            & $Io.WriteSummary -Text $summary.Text
            return $summary
        }

        if ([bool](Get-Prop -Object $Options -Name 'WhatIf' -Default $false)) {
            $snapshot = & $Io.Collect -Repository $Options.Repository -Epic $Options.Epic -Only $Options.Only
            if (-not $snapshot.Ok) {
                return (New-DeliverySummary -Plan $null -Attempted $attempted -Infra $true -Messages $snapshot.Error.Messages)
            }
            $plan = Resolve-QueuePlan -Snapshot $snapshot.Snapshot -Attempted $attempted -Retry $Options.Retry
            if ($null -ne $plan.Error) {
                return (New-DeliverySummary -Plan $plan -Attempted $attempted -Infra $true -Messages $plan.Error.Messages)
            }
            $summary = New-DeliverySummary -Plan $plan -Attempted $attempted
            & $Io.WriteSummary -Text $summary.Text
            return $summary
        }

        $lock = & $Io.AcquireLock -Repository $Options.Repository
        if (-not [bool](Get-Prop -Object $lock -Name 'Acquired' -Default $false)) {
            $messages += "lock indisponivel para $($Options.Repository)"
            $summary = New-DeliverySummary -Plan $null -Attempted $attempted -Infra $true -Messages $messages
            & $Io.WriteSummary -Text $summary.Text
            return $summary
        }

        $suffix = 0

        while ($true) {
            if (& $Io.IsCancelled) { $cancelled = $true; break }

            $snapshot = $null
            $collectAttempts = 0
            while ($true) {
                $collectAttempts++
                try {
                    $snapshot = & $Io.Collect -Repository $Options.Repository -Epic $Options.Epic -Only $Options.Only
                    break
                }
                catch {
                    if ($collectAttempts -ge 3) {
                        $infra = $true
                        $messages += "falha de coleta: $($_.Exception.Message)"
                        break
                    }
                    & $Io.Sleep -Seconds 0
                }
            }
            if ($infra) { break }

            if (-not $snapshot.Ok) {
                $infra = $true
                $messages += $snapshot.Error.Messages
                break
            }

            $plan = Resolve-QueuePlan -Snapshot $snapshot.Snapshot -Attempted $attempted -Retry $Options.Retry
            if ($null -ne $plan.Error) {
                $infra = $true
                $messages += $plan.Error.Messages
                break
            }

            $maxIssues = 0
            if ($null -ne (Get-Prop -Object $Options -Name 'MaxIssues')) { $maxIssues = [int]$Options.MaxIssues }
            $action = Select-DeliveryAction -Plan $plan -Attempted $attempted -MaxIssues $maxIssues -HasLimit ([bool](Get-Prop -Object $Options -Name 'HasLimit' -Default $false))

            if ($action.Kind -eq 'none') { break }
            if ($action.Kind -eq 'limit') { $limit = $true; break }

            switch ($action.Kind) {
                'recover' { $messages += Invoke-RecoverAction -Io $Io -Policy $Policy -Options $Options -Issue $action.Issue }
                'update_branch' { $messages += Invoke-UpdateBranchAction -Io $Io -Policy $Policy -Options $Options -Issue $action.Issue }
                'merge' { $messages += Invoke-MergeAction -Io $Io -Policy $Policy -Options $Options -Issue $action.Issue }
                'dispatch' {
                    $suffix++
                    $attempted += [int](Get-Prop -Object $action.Issue -Name 'Number')
                    $messages += Invoke-DispatchAction -Io $Io -Policy $Policy -Options $Options -Issue $action.Issue -Suffix $suffix
                }
            }
        }
    }
    finally {
        if ($null -ne $lock -and [bool](Get-Prop -Object $lock -Name 'Acquired' -Default $false)) {
            & $Io.ReleaseLock -Lock $lock
        }
    }

    $summary = New-DeliverySummary -Plan $plan -Attempted $attempted -Infra $infra -Cancelled $cancelled -LimitReached $limit -Messages $messages
    & $Io.WriteSummary -Text $summary.Text
    return $summary
}
```

- [ ] **Step 4: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.DriverLoop.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 7, Failed: 0`.

- [ ] **Step 5: Rodar a suite inteira**

Run: `Invoke-Pester -Path "delivery-queue/tests" -Output Detailed`
Expected: `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Driver.ps1 delivery-queue/tests/TestHelpers.ps1 delivery-queue/tests/DeliveryQueue.DriverLoop.Tests.ps1
git commit -m "feat(delivery-queue): driver loop with injected effects"
```

---

### Task 10: Adapter de efeitos real e CLI `Deliver-Queue.ps1`

**Files:**
- Create: `delivery-queue/src/DeliveryQueue.Io.ps1`
- Create: `delivery-queue/src/Deliver-Queue.ps1`
- Test: `delivery-queue/tests/DeliveryQueue.DriverCli.Tests.ps1`

**Interfaces:**
- Consumes: `New-DeliveryQueueGhAdapter`, `New-QueueSnapshot`, `Read-DeliveryQueuePolicy`, `Invoke-DeliveryLoop`, `Get-DeliveryExitCode`, `Enter-QueueLock`/`Exit-QueueLock`.
- Produces:
  - `ConvertTo-CommandLineArgument -Value <string> -> string` (puro).
  - `New-DeliveryQueueIoAdapter -Policy <object> [-InvokeProcess <scriptblock>] -> object` (contrato `$Io`).
  - CLI `Deliver-Queue.ps1 <epic> -Repository <owner/repo> [-MaxIssues N] [-Only <n,n>] [-Retry] [-WorkerTimeoutMinutes N] [-WhatIf] [-PolicyPath <path>] [-Io <object>]` — codigos de saida da spec secao 8.

Este task entrega o adapter real (efeitos) e o CLI. O adapter real e verificado por inspecao e pelo smoke E2E adiado; a logica de decisao ja esta coberta na Task 9.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.DriverCli.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Pages.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Attempt.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Common.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Collector.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.DriverCore.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Driver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Gh.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Io.ps1"
    . "$PSScriptRoot/TestHelpers.ps1"

    function Write-PolicyFile {
        param([object]$Policy)
        $path = Join-Path $TestDrive 'policy.json'
        ($Policy | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $path -Encoding UTF8
        return $path
    }
}

Describe 'ConvertTo-CommandLineArgument' {
    It 'nao cita argumento simples' {
        ConvertTo-CommandLineArgument -Value '--auto' | Should -Be '--auto'
    }
    It 'cita argumento com espaco' {
        ConvertTo-CommandLineArgument -Value 'a b' | Should -Be '"a b"'
    }
}

Describe 'Deliver-Queue.ps1 (CLI)' {
    It 'retorna 4 quando a politica esta ausente' {
        & "$PSScriptRoot/../src/Deliver-Queue.ps1" 9 -Repository 'o/r' -PolicyPath (Join-Path $TestDrive 'nao-existe.json') | Out-Null
        $LASTEXITCODE | Should -Be 4
    }

    It 'retorna 0 sem trabalho quando a fila esta vazia' {
        $policyPath = Write-PolicyFile -Policy (New-TestPolicy)
        $empty = (New-SnapshotFromIssues -Policy (New-TestPolicy) -Issues @())
        $io = New-IoFake -Collect ({ param($Repository, $Epic, $Only) $empty }.GetNewClosure())
        & "$PSScriptRoot/../src/Deliver-Queue.ps1" 9 -Repository 'o/r' -PolicyPath $policyPath -Io $io | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'WhatIf nao adquire lock nem despacha' {
        $policy = New-TestPolicy
        $policyPath = Write-PolicyFile -Policy $policy
        $snapshot = (New-SnapshotFromIssues -Policy $policy -Issues @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() }))
        $lockCount = [ref]0; $dispatchCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $snapshot }.GetNewClosure()) `
            -AcquireLock ({ param($Repository) $lockCount.Value++; [pscustomobject]@{ Acquired = $true; Path = 'l'; Stream = $null; Repository = $Repository } }.GetNewClosure()) `
            -DispatchWorker ({ param($Issue, $Repository, $Base, $Worktree, $TimeoutMinutes) $dispatchCount.Value++; [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' } }.GetNewClosure())
        & "$PSScriptRoot/../src/Deliver-Queue.ps1" 9 -Repository 'o/r' -PolicyPath $policyPath -WhatIf -Io $io | Out-Null
        $LASTEXITCODE | Should -Be 0
        $lockCount.Value | Should -Be 0
        $dispatchCount.Value | Should -Be 0
    }
}
```

`New-SnapshotFromIssues` e um helper novo. Acrescente ao final de `delivery-queue/tests/TestHelpers.ps1`:

```powershell
function New-SnapshotFromIssues {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Policy, [AllowEmptyCollection()] [object[]]$Issues = @())
    $gh = New-GhFake -GetSubIssues ({ param($Repository, $Epic) $Issues }.GetNewClosure())
    return (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $Policy -Gh $gh).Snapshot
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.DriverCli.Tests.ps1" -Output Detailed`
Expected: FAIL (`DeliveryQueue.Io.ps1` nao existe).

- [ ] **Step 3: Implementar o adapter de efeitos**

Crie `delivery-queue/src/DeliveryQueue.Io.ps1`:

```powershell
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Attempt.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Lock.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Gh.ps1')

function ConvertTo-CommandLineArgument {
    [CmdletBinding()]
    param([AllowNull()] [string]$Value)

    $text = [string]$Value
    if ($text -match '[\s"]') {
        $escaped = $text -replace '\\', '\\\\' -replace '"', '\"'
        return '"' + $escaped + '"'
    }
    return $text
}

function Invoke-Process {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [AllowEmptyCollection()] [string[]]$Arguments = @(),
        [AllowNull()] [string]$WorkingDirectory,
        [int]$TimeoutSeconds = 0
    )

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = (@($Arguments | ForEach-Object { ConvertTo-CommandLineArgument -Value $_ }) -join ' ')
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { $info.WorkingDirectory = $WorkingDirectory }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $process.Start() | Out-Null
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()

    $timedOut = $false
    if ($TimeoutSeconds -gt 0) {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            & taskkill /PID $process.Id /T /F 2>&1 | Out-Null
            $process.WaitForExit()
        }
    }
    else {
        $process.WaitForExit()
    }

    $output = ($stdout.Result + $stderr.Result)
    return [pscustomobject]@{ exitCode = $process.ExitCode; timedOut = $timedOut; output = $output }
}

function Invoke-GitIn {
    [CmdletBinding()]
    param([string]$WorkingDirectory, [Parameter(Mandatory)] [string[]]$Arguments)

    $result = Invoke-Process -FilePath 'git' -Arguments $Arguments -WorkingDirectory $WorkingDirectory
    if ($result.exitCode -ne 0) {
        throw "git $($Arguments -join ' ') falhou: $($result.output)"
    }
    return $result.output
}

function New-DeliveryQueueIoAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Policy,
        [scriptblock]$InvokeProcess
    )

    if (-not $InvokeProcess) {
        $InvokeProcess = { param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds) Invoke-Process -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds }
    }

    $adapter = [pscustomobject]@{}
    $adapter | Add-Member NoteProperty GetNow ({ [datetimeoffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }.GetNewClosure())
    $adapter | Add-Member NoteProperty Log ({ param($Message) [Console]::Error.WriteLine($Message) }.GetNewClosure())
    $adapter | Add-Member NoteProperty Sleep ({ param($Seconds) Start-Sleep -Seconds $Seconds }.GetNewClosure())
    $adapter | Add-Member NoteProperty IsCancelled ({ $false }.GetNewClosure())

    $adapter | Add-Member NoteProperty Collect ({
        param($Repository, $Epic, $Only)
        $gh = New-DeliveryQueueGhAdapter
        $filter = [pscustomobject]@{ only = $Only }
        return (New-QueueSnapshot -Repository $Repository -Epic $Epic -Policy $Policy -Gh $gh -Filter $filter)
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty AcquireLock ({ param($Repository) Enter-QueueLock -Repository $Repository }.GetNewClosure())
    $adapter | Add-Member NoteProperty ReleaseLock ({ param($Lock) Exit-QueueLock -Lock $Lock }.GetNewClosure())

    $adapter | Add-Member NoteProperty FetchDefault ({
        param($Repository, $Branch)
        Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('fetch', 'origin', $Branch) | Out-Null
        return (Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('rev-parse', "origin/$Branch")).Trim()
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty GetDefaultHead ({
        param($Repository, $Branch)
        Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('fetch', 'origin', $Branch) | Out-Null
        return (Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('rev-parse', "origin/$Branch")).Trim()
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty EnsureWorktree ({
        param($Repository, $Branch, $Base, $Root)
        $path = Join-Path $Root ($Branch -replace '[^A-Za-z0-9._-]', '_')
        $existing = (Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('worktree', 'list', '--porcelain'))
        if ($existing -match [regex]::Escape("branch refs/heads/$Branch")) {
            return [pscustomobject]@{ path = $path; branch = $Branch }
        }
        Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('worktree', 'add', $path, '-b', $Branch, "origin/$Base") | Out-Null
        return [pscustomobject]@{ path = $path; branch = $Branch }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty ReadAttempt ({
        param($Repository, $Issue)
        $data = Invoke-GhJson -Arguments @('issue', 'view', [string]$Issue, '--repo', $Repository, '--json', 'comments')
        $bodies = @()
        foreach ($comment in @($data.comments)) { $bodies += [string]$comment.body }
        return (Select-LatestAttempt -Comments $bodies)
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty UpsertAttempt ({
        param($Repository, $Issue, $Record)
        $body = ConvertTo-AttemptComment -Record $Record
        $data = Invoke-GhJson -Arguments @('issue', 'view', [string]$Issue, '--repo', $Repository, '--json', 'comments')
        $targetId = $null
        foreach ($comment in @($data.comments)) {
            $commentId = Get-Prop -Object $comment -Name 'id'
            if ($null -eq $commentId) { continue }
            if ((ConvertFrom-AttemptComment -Body ([string]$comment.body)) -and ([string](Get-Prop -Object (ConvertFrom-AttemptComment -Body ([string]$comment.body)) -Name 'attemptId')) -eq [string](Get-Prop -Object $Record -Name 'attemptId')) {
                $targetId = $commentId
                break
            }
        }
        if ($null -ne $targetId) {
            Invoke-GhJson -Arguments @('api', '-X', 'PATCH', "repos/$Repository/issues/comments/$targetId", '-f', "body=$body") | Out-Null
            return [string]$targetId
        }
        $created = Invoke-GhJson -Arguments @('api', "repos/$Repository/issues/$Issue/comments", '-f', "body=$body")
        return [string](Get-Prop -Object $created -Name 'id')
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty DispatchWorker ({
        param($Issue, $Repository, $Base, $Worktree, $TimeoutMinutes)
        $prompt = "$Issue --repo $Repository --base $Base"
        $arguments = @('run', '--auto', '--command', 'delivery-queue-deliver-issue', '--format', 'json', $prompt)
        $result = & $InvokeProcess -FilePath 'opencode' -Arguments $arguments -WorkingDirectory $Worktree -TimeoutSeconds ($TimeoutMinutes * 60)
        return [pscustomobject]@{ exitCode = $result.exitCode; timedOut = $result.timedOut; output = $result.output }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty GetPr ({
        param($Repository, $Number)
        $json = 'number,state,isDraft,baseRefName,headRefName,headRefOid,url,mergeable,statusCheckRollup'
        $pr = Invoke-GhJson -Arguments @('pr', 'view', [string]$Number, '--repo', $Repository, '--json', $json)
        $checks = @()
        $known = $null -ne (Get-Prop -Object $pr -Name 'statusCheckRollup')
        foreach ($entry in @(Get-Prop -Object $pr -Name 'statusCheckRollup')) {
            $context = [string](Get-Prop -Object $entry -Name 'name')
            if ([string]::IsNullOrWhiteSpace($context)) { $context = [string](Get-Prop -Object $entry -Name 'context') }
            $conclusion = [string](Get-Prop -Object $entry -Name 'conclusion')
            if ([string]::IsNullOrWhiteSpace($conclusion)) { $conclusion = [string](Get-Prop -Object $entry -Name 'state') }
            $checks += [pscustomobject]@{ context = $context; conclusion = $conclusion }
        }
        $complete = Test-RemoteChecksComplete -Checks $checks -ChecksKnown $known -Policy $Policy
        return [pscustomobject]@{
            number = [int](Get-Prop -Object $pr -Name 'number'); state = [string](Get-Prop -Object $pr -Name 'state')
            isDraft = [bool](Get-Prop -Object $pr -Name 'isDraft' -Default $false)
            hasConflict = ([string](Get-Prop -Object $pr -Name 'mergeable') -eq 'CONFLICTING')
            checksComplete = $complete; headSha = [string](Get-Prop -Object $pr -Name 'headRefOid')
            url = [string](Get-Prop -Object $pr -Name 'url'); baseRefName = [string](Get-Prop -Object $pr -Name 'baseRefName')
            headRefName = [string](Get-Prop -Object $pr -Name 'headRefName')
        }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty RunLocalChecks ({
        param($Worktree, $Commands)
        $head = (Invoke-GitIn -WorkingDirectory $Worktree -Arguments @('rev-parse', 'HEAD')).Trim()
        $evidence = @()
        foreach ($command in @($Commands)) {
            $result = & $InvokeProcess -FilePath 'cmd.exe' -Arguments @('/d', '/s', '/c', $command) -WorkingDirectory $Worktree -TimeoutSeconds 0
            $evidence += [pscustomobject]@{ command = [string]$command; result = $(if ($result.exitCode -eq 0) { 'pass' } else { 'fail' }); headSha = $head; at = [datetimeoffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
        }
        return ,$evidence
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty UpdateBranch ({
        param($Repository, $Number, $Base)
        $worktree = Join-Path ([System.IO.Path]::GetTempPath()) "dq-update-$Number"
        Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('fetch', 'origin', $Base) | Out-Null
        $result = & $InvokeProcess -FilePath 'git' -Arguments @('merge', "origin/$Base", '--no-edit') -WorkingDirectory (Get-Location).Path -TimeoutSeconds 0
        return [pscustomobject]@{ updated = ($result.exitCode -eq 0); conflict = ($result.exitCode -ne 0) }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty MergePr ({
        param($Repository, $Number, $Method, $HeadSha, $AllowAdmin)
        $arguments = @('pr', 'merge', [string]$Number, '--repo', $Repository, "--$Method", '--match-head-commit', $HeadSha)
        if ($AllowAdmin) { $arguments += '--admin' }
        $result = & $InvokeProcess -FilePath 'gh' -Arguments $arguments -TimeoutSeconds 300
        if ($result.exitCode -ne 0) { throw "gh pr merge falhou: $($result.output)" }
        $view = Invoke-GhJson -Arguments @('pr', 'view', [string]$Number, '--repo', $Repository, '--json', 'state,mergeCommit,mergedAt')
        return [pscustomobject]@{
            state = [string](Get-Prop -Object $view -Name 'state')
            mergeCommit = [string](Get-Prop -Object (Get-Prop -Object $view -Name 'mergeCommit') -Name 'oid')
            mergedAt = [string](Get-Prop -Object $view -Name 'mergedAt')
        }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty VerifyPostMerge ({
        param($Repository, $Branch, $Commands)
        Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('fetch', 'origin', $Branch) | Out-Null
        $baseSha = (Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('rev-parse', "origin/$Branch")).Trim()
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("dq-verify-" + [Guid]::NewGuid().ToString('N'))
        Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('worktree', 'add', '--detach', $temp, "origin/$Branch") | Out-Null
        $result = 'pass'
        try {
            foreach ($command in @($Commands)) {
                $run = & $InvokeProcess -FilePath 'cmd.exe' -Arguments @('/d', '/s', '/c', $command) -WorkingDirectory $temp -TimeoutSeconds 0
                if ($run.exitCode -ne 0) { $result = 'fail'; break }
            }
        }
        finally {
            Invoke-GitIn -WorkingDirectory (Get-Location).Path -Arguments @('worktree', 'remove', '--force', $temp) | Out-Null
        }
        return [pscustomobject]@{ baseSha = $baseSha; result = $result; at = [datetimeoffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty WriteSummary ({ param($Text) [Console]::Out.WriteLine($Text) }.GetNewClosure())

    return $adapter
}
```

- [ ] **Step 4: Implementar o CLI**

Crie `delivery-queue/src/Deliver-Queue.ps1`:

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [int]$Epic,
    [Parameter(Mandatory)] [string]$Repository,
    [int]$MaxIssues = 0,
    [AllowEmptyCollection()] [int[]]$Only = @(),
    [switch]$Retry,
    [int]$WorkerTimeoutMinutes = 0,
    [switch]$WhatIf,
    [string]$PolicyPath = '.delivery-queue/policy.json',
    [AllowNull()] [object]$Io = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Pages.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Attempt.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Common.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.DriverCore.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Driver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Gh.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Io.ps1')

if ($Epic -lt 1) {
    [Console]::Error.WriteLine('epic deve ser um inteiro positivo')
    exit 4
}

$loaded = Read-DeliveryQueuePolicy -Path $PolicyPath
if (-not $loaded.Ok) {
    [Console]::Error.WriteLine(($loaded.Messages -join '; '))
    exit 4
}

if ($Repository -notmatch '^[^/]+/[^/]+$') {
    [Console]::Error.WriteLine("repository invalido: $Repository")
    exit 4
}

if ($MaxIssues -lt 0 -or $WorkerTimeoutMinutes -lt 0) {
    [Console]::Error.WriteLine('MaxIssues e WorkerTimeoutMinutes devem ser nao negativos')
    exit 4
}

$timeout = $WorkerTimeoutMinutes
if ($timeout -eq 0) { $timeout = [int](Get-Prop -Object $loaded.Policy -Name 'workerTimeoutMinutes' -Default 60) }

$options = [pscustomobject]@{
    Repository = $Repository
    Epic = $Epic
    MaxIssues = $(if ($MaxIssues -gt 0) { $MaxIssues } else { $null })
    HasLimit = ($MaxIssues -gt 0)
    Only = $Only
    Retry = [bool]$Retry
    WorkerTimeoutMinutes = $timeout
    WhatIf = [bool]$WhatIf
}

$driverIo = $Io
if ($null -eq $driverIo) { $driverIo = New-DeliveryQueueIoAdapter -Policy $loaded.Policy }

$summary = Invoke-DeliveryLoop -Policy $loaded.Policy -Options $options -Io $driverIo
exit (Get-DeliveryExitCode -Summary $summary)
```

Hmm: `$driverIo` as a function name and a variable name differ only by `$`. `$driverIo` variable vs `New-DeliveryQueueIoAdapter`. The text says `$driverIo = $Io`, then `$driverIo = New-DeliveryQueueIoAdapter`. That's a variable assignment; fine. But `$Io` parameter and `$driverIo` variable. OK.

Wait, `exit (Get-DeliveryExitCode -Summary $summary)` — `exit` with an expression. PS supports `exit <int>`. Parenthesized command substitution works: `exit (Get-DeliveryExitCode ...)`. Should be fine.

- [ ] **Step 5: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.DriverCli.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 5, Failed: 0`.

- [ ] **Step 6: Rodar a suite inteira**

Run: `Invoke-Pester -Path "delivery-queue/tests" -Output Detailed`
Expected: `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Io.ps1 delivery-queue/src/Deliver-Queue.ps1 delivery-queue/tests/DeliveryQueue.DriverCli.Tests.ps1 delivery-queue/tests/TestHelpers.ps1
git commit -m "feat(delivery-queue): real effects adapter and deliver CLI"
```

---

### Task 11: Agentes, comando, schema da politica e politica do pvsdev

**Files:**
- Create: `.opencode/agent/delivery-queue-worker.md`
- Create: `.opencode/agent/delivery-queue-reviewer.md`
- Create: `.opencode/agent/delivery-queue-fixer.md`
- Create: `.opencode/command/delivery-queue-deliver-issue.md`
- Create: `delivery-queue/schema/policy-v1.json`
- Create: `.delivery-queue/policy.json`
- Test: `delivery-queue/tests/DeliveryQueue.Package.Tests.ps1`

**Interfaces:**
- Consumes: nada de codigo (arquivos de configuracao/agente).
- Produces: o comando `delivery-queue-deliver-issue` com frontmatter `agent: delivery-queue-worker`, os tres agentes com `model` explicito, o schema publicado e a politica local do pvsdev.

Notas de plataforma (OpenCode 1.18.26): agentes ficam em `.opencode/agent/<nome>.md`; o corpo vira o `prompt`; campos validos de frontmatter incluem `description`, `mode`, `model`, `permission`. O comando fica em `.opencode/command/<nome>.md`; o corpo vira o `template`; `$ARGUMENTS` recebe o texto apos o comando. A precedencia verificada pela spec faz o `agent` do comando vencer `--agent`, e o modelo do agente vencer `--model`. Os IDs de modelo abaixo sao o default do consumidor e devem ser ajustados ao provedor instalado; o reviewer usa um modelo mais barato.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.Package.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path

    function Get-Frontmatter {
        param([string]$Path)
        $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $match = [regex]::Match($text, '(?s)^---\s*(.*?)\s*---')
        if (-not $match.Success) { return $null }
        return $match.Groups[1].Value
    }
}

Describe 'schema/policy-v1.json' {
    It 'e JSON valido com schema draft e propriedades' {
        $path = Join-Path $repoRoot 'delivery-queue/schema/policy-v1.json'
        (Test-Path -LiteralPath $path) | Should -BeTrue
        $schema = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $schema.'$schema' | Should -Match 'json-schema.org'
        $schema.properties.version.type | Should -Be 'integer'
        $schema.properties.merge.properties.authorizedByLocalRules.type | Should -Be 'boolean'
    }
}

Describe 'agentes' {
    It 'declara modelo e descricao em cada agente' {
        foreach ($name in @('delivery-queue-worker', 'delivery-queue-reviewer', 'delivery-queue-fixer')) {
            $path = Join-Path $repoRoot ".opencode/agent/$name.md"
            (Test-Path -LiteralPath $path) | Should -BeTrue
            $front = Get-Frontmatter -Path $path
            $front | Should -Match 'description:'
            $front | Should -Match 'model:'
        }
    }

    It 'worker nega question e doom_loop' {
        $front = Get-Frontmatter -Path (Join-Path $repoRoot '.opencode/agent/delivery-queue-worker.md')
        $front | Should -Match '(?m)^\s*question:\s*deny'
        $front | Should -Match '(?m)^\s*doom_loop:\s*deny'
    }

    It 'reviewer e read-only' {
        $front = Get-Frontmatter -Path (Join-Path $repoRoot '.opencode/agent/delivery-queue-reviewer.md')
        $front | Should -Match '(?m)^\s*edit:\s*deny'
    }
}

Describe 'comando delivery-queue-deliver-issue' {
    It 'aponta para o worker e tem template com ARGUMENTS' {
        $path = Join-Path $repoRoot '.opencode/command/delivery-queue-deliver-issue.md'
        (Test-Path -LiteralPath $path) | Should -BeTrue
        $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        (Get-Frontmatter -Path $path) | Should -Match 'agent:\s*delivery-queue-worker'
        $text | Should -Match '\$ARGUMENTS'
    }
}

Describe 'politica local do pvsdev' {
    It 'usa mergeMode human e nao autoriza auto' {
        $path = Join-Path $repoRoot '.delivery-queue/policy.json'
        (Test-Path -LiteralPath $path) | Should -BeTrue
        $policy = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $policy.mergeMode | Should -Be 'human'
        $policy.merge.authorizedByLocalRules | Should -BeFalse
        $policy.defaultBranch | Should -Be 'master'
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Package.Tests.ps1" -Output Detailed`
Expected: FAIL (arquivos nao existem).

- [ ] **Step 3: Criar os agentes**

Crie `.opencode/agent/delivery-queue-worker.md`:

```markdown
---
description: Entrega uma issue da fila de delivery de ponta a ponta no worktree designado. Implementa, roda os checks exigidos, faz review adversarial, corrige e publica o registro de tentativa. Nao pergunta ao usuario.
mode: subagent
model: opencode-go/deepseek-v4.1
permission:
  question: deny
  doom_loop: deny
  edit: allow
  bash: allow
---

Voce entrega uma unica issue da delivery queue, do inicio ao fim, no worktree
em que foi iniciado. O texto do comando traz `<issue> --repo <owner/repo>
--base <branch>`.

Fluxo obrigatorio:

1. Leia a issue, a epic-pai e as regras locais (`AGENTS.md`, `docs/project/WORKFLOW.md`).
2. Implemente o menor incremento que satisfaz os criterios de aceite no branch ja criado pelo driver.
3. Rode as verificacoes exigidas pela politica no worktree e guarde comando e resultado.
4. Faca review adversarial do proprio diff; no maximo tres ciclos de correcao/re-review.
5. Faca commit e push do branch.
6. Abra a PR mirando a branch padrao, com `Closes #<issue>` no corpo.
7. Publique/atualize o comentario de tentativa (marcador `delivery-queue-attempt:v1`)
   com `status: delivered`, `pr`, `headSha`, `review {iterations, blocking, headSha}`
   e `checks` locais no formato `{scope:"local", command, result, headSha, at}`.

Regras:
- Nunca pergunte ao usuario; decida com a evidencia disponivel.
- Nao altere a branch padrao; nao faca merge.
- Nao invente evidencia: registre exatamente o que foi executado.
- Se um blocker externo ou dado desconhecido impedir, registre `blocked` e pare.
```

Crie `.opencode/agent/delivery-queue-reviewer.md`:

```markdown
---
description: Review adversarial somente-leitura de um diff da delivery queue. Aponta achados bloqueantes contra a spec e os criterios de aceite. Nao edita arquivos.
mode: subagent
model: opencode-go/deepseek-v4.1-flash
permission:
  edit: deny
  question: deny
  doom_loop: deny
---

Voce e um reviewer adversarial. Leia a issue, a spec e o diff da PR e responda
com achados classificados em `blocking` e `non-blocking`, cada um com
`file:line` e a regra violada. Nao edite arquivos. Nao aprove por simpatia.
Se nao houver achados bloqueantes, diga explicitamente `blocking: 0`.
```

Crie `.opencode/agent/delivery-queue-fixer.md`:

```markdown
---
description: Corrige achados bloqueantes do reviewer no diff da delivery queue, sem ampliar o escopo. Roda verificacoes apos corrigir.
mode: subagent
model: opencode-go/deepseek-v4.1
permission:
  question: deny
  doom_loop: deny
  edit: allow
  bash: allow
---

Voce corrige exatamente os achados bloqueantes apontados no diff, sem ampliar o
escopo nem refatorar o que nao foi pedido. Depois de corrigir, rode as
verificacoes exigidas pela politica e registre o resultado. No maximo tres
ciclos de correcao/re-review no total.
```

- [ ] **Step 4: Criar o comando**

Crie `.opencode/command/delivery-queue-deliver-issue.md`:

```markdown
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
```

- [ ] **Step 5: Criar o schema e a politica do pvsdev**

Crie `delivery-queue/schema/policy-v1.json`:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://example.invalid/delivery-queue/policy-v1.json",
  "title": "delivery-queue policy v1",
  "type": "object",
  "required": ["version", "repository", "mergeMode", "defaultBranch", "merge", "completionWithoutCode"],
  "additionalProperties": true,
  "properties": {
    "$schema": { "type": "string" },
    "version": { "type": "integer", "const": 1 },
    "repository": { "type": "string", "pattern": "^[^/]+/[^/]+$" },
    "mergeMode": { "type": "string", "enum": ["human", "auto"] },
    "defaultBranch": { "type": "string", "minLength": 1 },
    "project": {
      "type": ["object", "null"],
      "required": ["owner", "number", "eligibleStates", "resumableStates"],
      "properties": {
        "owner": { "type": "string" },
        "number": { "type": "integer" },
        "eligibleStates": { "type": "array", "items": { "type": "string" } },
        "resumableStates": { "type": "array", "items": { "type": "string" } }
      }
    },
    "fallbackEligibility": { "type": ["string", "null"] },
    "requiredChecks": { "type": "array", "items": { "type": "string" } },
    "requiredRemoteChecks": { "type": "array", "items": { "type": "string" } },
    "merge": {
      "type": "object",
      "required": ["method", "requireChecksOnPr", "verifyDefaultBranchAfterMerge", "authorizedByLocalRules", "allowAdminBypass"],
      "properties": {
        "method": { "type": "string", "enum": ["merge", "squash", "rebase"] },
        "requireChecksOnPr": { "type": "boolean" },
        "verifyDefaultBranchAfterMerge": { "type": "boolean" },
        "authorizedByLocalRules": { "type": "boolean" },
        "allowAdminBypass": { "type": "boolean" }
      }
    },
    "completionWithoutCode": { "type": "string", "enum": ["requires-evidence", "allow-closed"] },
    "workerTimeoutMinutes": { "type": "integer", "minimum": 1 },
    "worktreeRoot": { "type": "string" }
  }
}
```

Crie `.delivery-queue/policy.json`:

```json
{
  "$schema": "delivery-queue/schema/policy-v1.json",
  "version": 1,
  "repository": "paulop2/pvsdev",
  "mergeMode": "human",
  "defaultBranch": "master",
  "project": null,
  "fallbackEligibility": "label:delivery-queue-ready",
  "requiredChecks": ["npm run typecheck", "npm run build"],
  "requiredRemoteChecks": [],
  "merge": {
    "method": "merge",
    "requireChecksOnPr": true,
    "verifyDefaultBranchAfterMerge": true,
    "authorizedByLocalRules": false,
    "allowAdminBypass": false
  },
  "completionWithoutCode": "requires-evidence",
  "workerTimeoutMinutes": 60,
  "worktreeRoot": ".."
}
```

- [ ] **Step 6: Rodar e ver que passa**

Run: `Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Package.Tests.ps1" -Output Detailed`
Expected: `Tests Passed: 6, Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add .opencode .delivery-queue delivery-queue/schema delivery-queue/tests/DeliveryQueue.Package.Tests.ps1
git commit -m "feat(delivery-queue): agents, command, policy schema and pvsdev policy"
```

---

## Desvios e limites conhecidos

- **Refs/SHAs locais no snapshot (spec secao 6):** o snapshot nao inclui `localRefs`; o resolver congelado nao consome esse campo e o driver le `git` diretamente pelo adapter `$Io`. O metodo `GetRefSha` do contrato `$Gh` fica disponivel para um incremento futuro.
- **`parent_failed` apos pos-merge vermelho:** o driver marca `failed` e para; como o resolver congelado mapeia `postMerge` nao-pass para `parent_unverified`, dependentes ficam `blocked/parent_unverified` em vez de `parent_failed`. Um ajuste no resolver e follow-up.
- **`hasCode`:** derivado do label `no-code` por convencao do consumidor (issue sem codigo); nao ha campo dedicado na spec.
- **`UpdateBranch`:** apos atualizar a branch o driver apenas invalida review/checks e deixa a proxima resolucao decidir; o resolver nao sinaliza redespacho com PR aberta, entao a re-verificacao/re-review pode exigir uma tentativa explicita.
- **Preempcao de cancelamento:** `IsCancelled` e um ponto de injecao; o adapter real retorna `$false` e o tratamento de Ctrl+C fica como follow-up.

## Definição de pronto

- `Invoke-Pester -Path "delivery-queue/tests"` sai com `Failed: 0`.
- `Get-QueueSnapshot.ps1` produz um snapshot que `Resolve-QueuePlan` consome, com adapter injetado nos testes.
- `Deliver-Queue.ps1` respeita os codigos de saida 0/1/2/3/4/130 e nao mergeia em `human`.
- `npm run typecheck` e `npm run build` passam (o aviso de multiplos lockfiles e pre-existente).
- Nenhuma funcao de `DeliveryQueue.Resolver.ps1` foi modificada; o resolver permanece puro.

## Verificacao manual adiada (smoke E2E real)

Fora do escopo automatizado deste incremento; executar antes de declarar o pacote
pronto para uso (spec secao 11):

1. Em um repositorio de teste, criar epic A -> B -> C e issue independente D.
2. Rodar o driver e confirmar C nascendo da padrao ja com B mergeada (sem rebase) e `Closes #n`.
3. Em cenario separado, falhar A e confirmar avanco de D sem B/C.
4. Exercitar `mergeMode` nos dois valores, retomada apos push e apos PR, e `-WhatIf` numa epic real.

## Fora do escopo deste plano

- Distribuicao do pacote (repositorio dedicado, instalacao, versao minima de PowerShell) — spec secao 10.
- Smoke E2E real com GitHub/opencode.
- Aposentar as copias locais do PJI240.
- Adocao no PJI240.

<!-- APPEND -->
