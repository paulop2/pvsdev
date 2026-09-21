# Delivery Queue — Resolver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar `Resolve-QueuePlan`, o resolver puro que transforma um snapshot da fila em ordem topológica, status, motivo e próxima ação por issue — sem rede, sem shell, sem mutação.

**Architecture:** Uma única responsabilidade por arquivo: `DeliveryQueue.Resolver.ps1` expõe funções puras (política, grafo, dependências, classificação, plano) e é dot-sourced pelos testes; `Resolve-Queue.ps1` é um CLI fino que lê um snapshot JSON do disco e imprime o plano. Toda a lógica é coberta por Pester com fixtures, sem tocar no GitHub.

**Tech Stack:** Windows PowerShell 5.1, Pester 6.2.0 (instalado em escopo CurrentUser), `ConvertFrom-Json` / `ConvertTo-Json`.

**Spec:** `docs/superpowers/specs/2026-09-17-fila-de-issues-autonoma-design.md` (v2.1), seções 5, 6 e 9.

## Global Constraints

- Runtime: **Windows PowerShell 5.1** (não há `pwsh` na máquina). Nenhum código pode depender do PowerShell 7.
- Testes: **Pester 6.2.0**, instalado em escopo `CurrentUser`. A sintaxe `Should -Be` é suportada.
- `Set-StrictMode -Version Latest` em todos os arquivos de `src/`. Acesso a propriedade inexistente **lança erro**; sempre use `Get-Prop`.
- O resolver é **puro**: não chama `gh`, `git`, `Invoke-RestMethod`, não escreve arquivo, não lê ambiente. Entrada e saída são objetos.
- Estado de status (spec seção 6): `done`, `runnable`, `in_progress`, `blocked`, `failed`, `excluded`.
- Códigos de `reason` (spec seção 6): `blocked_by_issue`, `parent_failed`, `parent_unverified`, `awaiting_merge`, `merge_pending`, `checks_pending`, `policy_conflict`, `ambiguous_pr`, `needs_manual`, `infra`, mais `not_eligible`, `filtered`, `attempted`, `closed_not_planned`.
- Precedência sobre regras locais (spec seção 5): `mergeMode: auto` exige `merge.authorizedByLocalRules: true`; sem isso, `policy_conflict` antes de qualquer despacho.
- Dado desconhecido é gate (spec seção 6): nunca tratar ausência como lista vazia.
- Identidade de issue: `"<owner>/<repo>#<number>"`.
- Sem comentários no código.

## File Structure

```text
delivery-queue/
├── src/
│   ├── DeliveryQueue.Resolver.ps1   funções puras; dot-source nos testes
│   └── Resolve-Queue.ps1            CLI fino: lê JSON, chama o resolver, imprime JSON
└── tests/
    ├── DeliveryQueue.Policy.Tests.ps1
    ├── DeliveryQueue.Graph.Tests.ps1
    ├── DeliveryQueue.Dependency.Tests.ps1
    ├── DeliveryQueue.Classify.Tests.ps1
    ├── DeliveryQueue.Plan.Tests.ps1
    └── fixtures/
        ├── snapshot-linear.json
        └── snapshot-diamond.json
```

`DeliveryQueue.Resolver.ps1` cresce por task (política → helpers → grafo → dependência → classificação → plano). Cada função tem um teste próprio no arquivo de teste da sua responsabilidade.

---

### Task 0: Ambiente e esqueleto

**Files:**
- Create: `delivery-queue/tests/Smoke.Tests.ps1`

**Interfaces:**
- Consumes: nada.
- Produces: Pester 6 disponível; diretórios `delivery-queue/src` e `delivery-queue/tests`.

- [ ] **Step 1: Instalar Pester 6.2.0 em escopo CurrentUser**

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force -SkipPublisherCheck
```

Esperado: comando termina sem erro. O `Install-PackageProvider`/NuGet já está presente na máquina, então não deve pedir bootstrap.

Se o `Install-Module` falhar com erro de provedor, rode antes: `Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force`.

- [ ] **Step 2: Verificar que a 6.2.0 é a selecionada**

```powershell
Get-Module -ListAvailable Pester | Select-Object Name, Version, Path | Format-Table -AutoSize
```

Esperado: a lista inclui `Pester 6.2.0` em `...\Documents\WindowsPowerShell\Modules\Pester\6.2.0`. A 3.4.0 continua instalada em `Program Files`; não é problema, o carregamento pega a maior versão.

- [ ] **Step 3: Criar o esqueleto de diretórios**

```powershell
New-Item -ItemType Directory -Force -Path "delivery-queue/src" | Out-Null
New-Item -ItemType Directory -Force -Path "delivery-queue/tests/fixtures" | Out-Null
```

- [ ] **Step 4: Escrever o teste de fumaça**

Crie `delivery-queue/tests/Smoke.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest

Describe 'ambiente' {
    It 'carrega Pester 6' {
        (Get-Module -ListAvailable Pester |
            Sort-Object Version -Descending |
            Select-Object -First 1).Version.Major | Should -Be 6
    }

    It 'roda no Windows PowerShell 5.1' {
        $PSVersionTable.PSVersion.Major | Should -Be 5
        $PSVersionTable.PSVersion.Minor | Should -Be 1
    }
}
```

- [ ] **Step 5: Rodar e ver que passa**

```powershell
Invoke-Pester -Path "delivery-queue/tests/Smoke.Tests.ps1" -Output Detailed
```

Esperado: `Tests Passed: 2, Failed: 0`.

Se o Pester 6 tiver renomeado `-Output Detailed`, rode só `Invoke-Pester -Path "delivery-queue/tests/Smoke.Tests.ps1"` e use a saída padrão. Fixe a forma que funcionar e use-a em todos os passos seguintes.

- [ ] **Step 6: Commit**

```bash
git add delivery-queue/tests/Smoke.Tests.ps1
git commit -m "test(delivery-queue): bootstrap Pester suite on PowerShell 5.1"
```

---

### Task 1: Helpers de acesso seguro e validação de política

**Files:**
- Create: `delivery-queue/src/DeliveryQueue.Resolver.ps1`
- Create: `delivery-queue/tests/DeliveryQueue.Policy.Tests.ps1`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `Get-Prop -Object <object|null> -Name <string> [-Default <object>] -> object|null` — leitura segura de propriedade sob StrictMode.
  - `Get-Array -Value <object|null> -> object[]` — normaliza ausente/nulo para `@()`, nunca retorna `$null`.
  - `Test-DeliveryQueuePolicy -Policy <object|null> -> string[]` — lista de problemas; vazia significa política válida.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.Policy.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
}

Describe 'Get-Prop' {
    It 'retorna o valor quando a propriedade existe' {
        Get-Prop -Object ([pscustomobject]@{ a = 1 }) -Name 'a' | Should -Be 1
    }

    It 'retorna default quando a propriedade nao existe (sem lancar sob StrictMode)' {
        Get-Prop -Object ([pscustomobject]@{ a = 1 }) -Name 'b' -Default 'x' | Should -Be 'x'
    }

    It 'retorna default quando o objeto e nulo' {
        Get-Prop -Object $null -Name 'a' | Should -BeNullOrEmpty
    }
}

Describe 'Get-Array' {
    It 'normaliza nulo para array vazio' {
        (Get-Array -Value $null).Count | Should -Be 0
    }

    It 'preserva um item unico como array de um' {
        (Get-Array -Value 'x').Count | Should -Be 1
    }

    It 'preserva array existente' {
        (Get-Array -Value @(1, 2)).Count | Should -Be 2
    }
}

Describe 'Test-DeliveryQueuePolicy' {
    BeforeAll {
        $base = [pscustomobject]@{
            version               = 1
            defaultBranch         = 'master'
            mergeMode             = 'human'
            project               = [pscustomobject]@{ owner = 'o'; number = 5; eligibleStates = @('Ready'); resumableStates = @('In Progress') }
            fallbackEligibility   = $null
            requiredChecks        = @('npm run build')
            requiredRemoteChecks  = @()
            merge                 = [pscustomobject]@{ method = 'merge'; requireChecksOnPr = $true; verifyDefaultBranchAfterMerge = $true; authorizedByLocalRules = $false; allowAdminBypass = $false }
            completionWithoutCode = 'requires-evidence'
        }
    }

    It 'aceita politica valida' {
        (Test-DeliveryQueuePolicy -Policy $base).Count | Should -Be 0
    }

    It 'rejeita politica ausente' {
        Test-DeliveryQueuePolicy -Policy $null | Should -Contain 'policy ausente'
    }

    It 'rejeita version diferente de 1' {
        $p = $base.PSObject.Copy(); $p.version = 2
        (Test-DeliveryQueuePolicy -Policy $p) | Should -Match 'version'
    }

    It 'rejeita mergeMode invalido' {
        $p = $base.PSObject.Copy(); $p.mergeMode = 'sometimes'
        (Test-DeliveryQueuePolicy -Policy $p) | Should -Match 'mergeMode'
    }

    It 'rejeita auto sem atestacao de regra local' {
        $p = $base.PSObject.Copy(); $p.mergeMode = 'auto'; $p.merge = $base.merge.PSObject.Copy(); $p.merge.authorizedByLocalRules = $false
        (Test-DeliveryQueuePolicy -Policy $p) | Should -Match 'authorizedByLocalRules'
    }

    It 'aceita auto com atestacao' {
        $p = $base.PSObject.Copy(); $p.mergeMode = 'auto'; $p.merge = $base.merge.PSObject.Copy(); $p.merge.authorizedByLocalRules = $true
        (Test-DeliveryQueuePolicy -Policy $p).Count | Should -Be 0
    }

    It 'exige projeto ou fallback de elegibilidade' {
        $p = $base.PSObject.Copy(); $p.project = $null; $p.fallbackEligibility = $null
        (Test-DeliveryQueuePolicy -Policy $p) | Should -Match 'fallbackEligibility'
    }

    It 'aceita fallback no lugar do projeto' {
        $p = $base.PSObject.Copy(); $p.project = $null; $p.fallbackEligibility = 'label:agent-ready'
        (Test-DeliveryQueuePolicy -Policy $p).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

```powershell
Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Policy.Tests.ps1" -Output Detailed
```

Esperado: FAIL, porque `DeliveryQueue.Resolver.ps1` ainda não existe (o `BeforeAll` falha ao dot-source).

- [ ] **Step 3: Implementar os helpers e a validação**

Crie `delivery-queue/src/DeliveryQueue.Resolver.ps1`:

```powershell
Set-StrictMode -Version Latest

function Get-Prop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] [object]$Object,
        [Parameter(Mandatory)] [string]$Name,
        [AllowNull()] [object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    if ($null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-Array {
    [CmdletBinding()]
    param([AllowNull()] [object]$Value)

    if ($null -eq $Value) { return @() }
    return @($Value)
}

function Test-DeliveryQueuePolicy {
    [CmdletBinding()]
    param([AllowNull()] [object]$Policy)

    if ($null -eq $Policy) { return @('policy ausente') }

    $problems = @()

    if ((Get-Prop -Object $Policy -Name 'version') -ne 1) {
        $problems += "version deve ser 1, veio '$(Get-Prop -Object $Policy -Name 'version')'"
    }

    if ([string]::IsNullOrWhiteSpace([string](Get-Prop -Object $Policy -Name 'defaultBranch'))) {
        $problems += 'defaultBranch obrigatorio'
    }

    $mergeMode = [string](Get-Prop -Object $Policy -Name 'mergeMode')
    if ($mergeMode -notin @('human', 'auto')) {
        $problems += "mergeMode invalido: '$mergeMode'"
    }

    $merge = Get-Prop -Object $Policy -Name 'merge'
    if ($mergeMode -eq 'auto' -and -not [bool](Get-Prop -Object $merge -Name 'authorizedByLocalRules' -Default $false)) {
        $problems += 'policy_conflict: mergeMode auto exige merge.authorizedByLocalRules=true (regras locais prevalecem)'
    }

    if ($null -eq (Get-Prop -Object $Policy -Name 'project') -and
        [string]::IsNullOrWhiteSpace([string](Get-Prop -Object $Policy -Name 'fallbackEligibility'))) {
        $problems += 'sem project e sem fallbackEligibility: elegibilidade indefinida'
    }

    $completion = [string](Get-Prop -Object $Policy -Name 'completionWithoutCode')
    if ($completion -notin @('requires-evidence', 'allow-closed')) {
        $problems += "completionWithoutCode invalido: '$completion'"
    }

    return $problems
}
```

`Get-Prop` existe porque `Set-StrictMode -Version Latest` faz `$obj.ausente` lançar erro, e o snapshot tem campos opcionais (`pr`, `attempt`, `postMerge`). `Get-Array` existe porque `ConvertFrom-Json` do PowerShell 5.1 devolve `$null` para `[]` em alguns casos, e a spec exige que ausência seja desconhecida, não lista vazia.

- [ ] **Step 4: Rodar e ver que passa**

```powershell
Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Policy.Tests.ps1" -Output Detailed
```

Esperado: `Tests Passed: 14, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Resolver.ps1 delivery-queue/tests/DeliveryQueue.Policy.Tests.ps1
git commit -m "feat(delivery-queue): safe accessors and policy validation"
```

---

### Task 2: Grafo e ordem topológica

**Files:**
- Modify: `delivery-queue/src/DeliveryQueue.Resolver.ps1` (append)
- Create: `delivery-queue/tests/DeliveryQueue.Graph.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Prop`, `Get-Array` (Task 1).
- Produces:
  - `New-IssueId -Repository <string> -Number <int> -> string` — `"owner/repo#42"`.
  - `Get-NodeIndex -Snapshot <object> -> hashtable` — `id -> node`, aceitando nó sem `id` (compõe de `repository` + `number`).
  - `Get-TopologicalOrder -Snapshot <object> -> [pscustomobject]@{ Order = string[]; Cycle = string[]; Index = hashtable }` — Kahn sobre `blockedBy`, restrito a `inScope = true`. Desempate por número da issue, depois por id. `Cycle` são os nós que a ordenação não conseguiu emitir.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.Graph.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"

    function New-TestNode {
        param(
            [int]$Number,
            [string[]]$BlockedBy = @(),
            [bool]$InScope = $true
        )
        [pscustomobject]@{
            id        = "o/r#$Number"
            number    = $Number
            state     = 'OPEN'
            inScope   = $InScope
            blockedBy = $BlockedBy
        }
    }

    function New-TestSnapshot {
        param([object[]]$Issues)
        [pscustomobject]@{ repository = 'o/r'; epic = [pscustomobject]@{ number = 9 }; issues = $Issues }
    }
}

Describe 'New-IssueId' {
    It 'compõe owner/repo#numero' {
        New-IssueId -Repository 'paulop2/pvsdev' -Number 42 | Should -Be 'paulop2/pvsdev#42'
    }
}

Describe 'Get-NodeIndex' {
    It 'indexa por id' {
        $snapshot = New-TestSnapshot -Issues @((New-TestNode -Number 1), (New-TestNode -Number 2))
        (Get-NodeIndex -Snapshot $snapshot).Count | Should -Be 2
    }

    It 'compõe id quando o nó não traz o campo id' {
        $node = [pscustomobject]@{ number = 7; inScope = $true; blockedBy = @() }
        $index = Get-NodeIndex -Snapshot (New-TestSnapshot -Issues @($node))
        $index.ContainsKey('o/r#7') | Should -BeTrue
    }
}

Describe 'Get-TopologicalOrder' {
    It 'ordena cadeia linear pela dependência' {
        $snapshot = New-TestSnapshot -Issues @(
            (New-TestNode -Number 3 -BlockedBy @('o/r#2')),
            (New-TestNode -Number 2 -BlockedBy @('o/r#1')),
            (New-TestNode -Number 1)
        )
        (Get-TopologicalOrder -Snapshot $snapshot).Order | Should -Be @('o/r#1', 'o/r#2', 'o/r#3')
    }

    It 'desempata por numero da issue' {
        $snapshot = New-TestSnapshot -Issues @((New-TestNode -Number 10), (New-TestNode -Number 2))
        (Get-TopologicalOrder -Snapshot $snapshot).Order | Should -Be @('o/r#2', 'o/r#10')
    }

    It 'ignora blocker fora do escopo na ordenação' {
        $snapshot = New-TestSnapshot -Issues @(
            (New-TestNode -Number 4 -BlockedBy @('o/r#99')),
            (New-TestNode -Number 99 -InScope $false)
        )
        (Get-TopologicalOrder -Snapshot $snapshot).Order | Should -Be @('o/r#4')
    }

    It 'ignora blocker ausente do índice sem quebrar' {
        $snapshot = New-TestSnapshot -Issues @((New-TestNode -Number 5 -BlockedBy @('o/r#404')))
        (Get-TopologicalOrder -Snapshot $snapshot).Order | Should -Be @('o/r#5')
    }

    It 'detecta ciclo e não o emite na ordem' {
        $snapshot = New-TestSnapshot -Issues @(
            (New-TestNode -Number 6 -BlockedBy @('o/r#7')),
            (New-TestNode -Number 7 -BlockedBy @('o/r#6')),
            (New-TestNode -Number 8)
        )
        $result = Get-TopologicalOrder -Snapshot $snapshot
        $result.Order | Should -Be @('o/r#8')
        $result.Cycle | Should -Contain 'o/r#6'
        $result.Cycle | Should -Contain 'o/r#7'
    }

    It 'resolve diamante (dois pais independentes, um filho)' {
        $snapshot = New-TestSnapshot -Issues @(
            (New-TestNode -Number 1),
            (New-TestNode -Number 2),
            (New-TestNode -Number 3 -BlockedBy @('o/r#1', 'o/r#2'))
        )
        (Get-TopologicalOrder -Snapshot $snapshot).Order | Should -Be @('o/r#1', 'o/r#2', 'o/r#3')
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

```powershell
Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Graph.Tests.ps1" -Output Detailed
```

Esperado: FAIL em `New-IssueId: CommandNotFoundException`.

- [ ] **Step 3: Implementar o grafo**

Acrescente ao final de `delivery-queue/src/DeliveryQueue.Resolver.ps1`:

```powershell
function New-IssueId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [int]$Number
    )

    return "$Repository#$Number"
}

function Get-NodeIndex {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Snapshot)

    $repository = [string](Get-Prop -Object $Snapshot -Name 'repository')
    $index = @{}

    foreach ($node in (Get-Array -Value (Get-Prop -Object $Snapshot -Name 'issues'))) {
        $id = [string](Get-Prop -Object $node -Name 'id')
        if ([string]::IsNullOrWhiteSpace($id)) {
            $id = New-IssueId -Repository $repository -Number ([int](Get-Prop -Object $node -Name 'number'))
        }
        $index[$id] = $node
    }

    return $index
}

function Get-TopologicalOrder {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Snapshot)

    $index = Get-NodeIndex -Snapshot $Snapshot

    $inScope = @()
    foreach ($key in $index.Keys) {
        if ([bool](Get-Prop -Object $index[$key] -Name 'inScope' -Default $true)) {
            $inScope += [string]$key
        }
    }

    $sortKey = @{}
    $inDegree = @{}
    $dependents = @{}
    foreach ($id in $inScope) {
        $sortKey[$id] = '{0:D10}|{1}' -f [int](Get-Prop -Object $index[$id] -Name 'number' -Default 0), $id
        $inDegree[$id] = 0
        $dependents[$id] = @()
    }

    foreach ($id in $inScope) {
        foreach ($blocker in (Get-Array -Value (Get-Prop -Object $index[$id] -Name 'blockedBy'))) {
            $blockerId = [string]$blocker
            if ($inDegree.ContainsKey($blockerId)) {
                $inDegree[$id] = $inDegree[$id] + 1
                $dependents[$blockerId] += $id
            }
        }
    }

    $ready = @($inScope | Where-Object { $inDegree[$_] -eq 0 })
    $order = @()

    while ($ready.Count -gt 0) {
        $ready = @($ready | Sort-Object { $sortKey[$_] })
        $current = $ready[0]
        $ready = @($ready | Where-Object { $_ -ne $current })
        $order += $current

        foreach ($dependent in (Get-Array -Value $dependents[$current])) {
            $inDegree[$dependent] = $inDegree[$dependent] - 1
            if ($inDegree[$dependent] -eq 0) { $ready += $dependent }
        }
    }

    $cycle = @($inScope | Where-Object { $order -notcontains $_ })

    return [pscustomobject]@{
        Order = $order
        Cycle = $cycle
        Index = $index
    }
}
```

O blocker de fora do escopo não entra em `inDegree` porque só contamos ids presentes em `inScope`; ele continua existindo no índice para a etapa de dependência (Task 3) decidir se satisfaz ou não.

- [ ] **Step 4: Rodar e ver que passa**

```powershell
Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Graph.Tests.ps1" -Output Detailed
```

Esperado: `Tests Passed: 9, Failed: 0`.

- [ ] **Step 5: Rodar a suíte inteira para checar regressão**

```powershell
Invoke-Pester -Path "delivery-queue/tests" -Output Detailed
```

Esperado: nenhum teste falhando.

- [ ] **Step 6: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Resolver.ps1 delivery-queue/tests/DeliveryQueue.Graph.Tests.ps1
git commit -m "feat(delivery-queue): dependency graph and deterministic topological order"
```

---

### Task 3: Conclusão e satisfação de dependências

**Files:**
- Modify: `delivery-queue/src/DeliveryQueue.Resolver.ps1` (append)
- Create: `delivery-queue/tests/DeliveryQueue.Dependency.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Prop`, `Get-Array`, `Get-NodeIndex` (Tasks 1 e 2).
- Produces:
  - `Get-IssueCompletion -Node <object> -Policy <object> -DefaultHeadSha <string|null> -> [pscustomobject]@{ Status = 'done'|'blocked'|'excluded'; Reason <string|null> }` — decide se uma issue **fechada** conta como concluída. Só `done` satisfaz dependentes.
  - `Get-BlockerReason -BlockerIds <string[]> -Index <hashtable> -Policy <object> -DefaultHeadSha <string|null> -> string|null` — `$null` quando todos os blockers satisfazem; senão o motivo mais grave por precedência `infra > needs_manual > parent_failed > parent_unverified > blocked_by_issue`.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.Dependency.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"

    $policyVerify = [pscustomobject]@{
        merge                 = [pscustomobject]@{ verifyDefaultBranchAfterMerge = $true }
        completionWithoutCode = 'requires-evidence'
    }
    $policyLoose = [pscustomobject]@{
        merge                 = [pscustomobject]@{ verifyDefaultBranchAfterMerge = $false }
        completionWithoutCode = 'allow-closed'
    }

    function New-ClosedNode {
        param(
            [int]$Number,
            [string]$StateReason = 'COMPLETED',
            [object]$Attempt = $null,
            [bool]$HasCode = $true
        )
        [pscustomobject]@{
            id          = "o/r#$Number"
            number      = $Number
            state       = 'CLOSED'
            stateReason = $StateReason
            hasCode     = $HasCode
            attempt     = $Attempt
            blockedBy   = @()
            inScope     = $true
        }
    }

    function New-OpenNode {
        param([int]$Number, [string]$AttemptStatus = $null, [string[]]$BlockedBy = @())
        $attempt = $null
        if ($AttemptStatus) { $attempt = [pscustomobject]@{ status = $AttemptStatus } }
        [pscustomobject]@{
            id          = "o/r#$Number"
            number      = $Number
            state       = 'OPEN'
            stateReason = $null
            hasCode     = $true
            attempt     = $attempt
            blockedBy   = $BlockedBy
            inScope     = $true
        }
    }
}

Describe 'Get-IssueCompletion' {
    It 'conclui quando a verificacao pos-merge nao e exigida' {
        $result = Get-IssueCompletion -Node (New-ClosedNode -Number 1) -Policy $policyLoose -DefaultHeadSha 'abc'
        $result.Status | Should -Be 'done'
    }

    It 'conclui quando ha postMerge pass no head atual' {
        $attempt = [pscustomobject]@{ postMerge = [pscustomobject]@{ result = 'pass'; baseSha = 'abc' } }
        $result = Get-IssueCompletion -Node (New-ClosedNode -Number 1 -Attempt $attempt) -Policy $policyVerify -DefaultHeadSha 'abc'
        $result.Status | Should -Be 'done'
    }

    It 'bloqueia quando falta registro pos-merge' {
        $result = Get-IssueCompletion -Node (New-ClosedNode -Number 1) -Policy $policyVerify -DefaultHeadSha 'abc'
        $result.Status | Should -Be 'blocked'
        $result.Reason | Should -Be 'parent_unverified'
    }

    It 'bloqueia quando o postMerge e de um head antigo' {
        $attempt = [pscustomobject]@{ postMerge = [pscustomobject]@{ result = 'pass'; baseSha = 'velho' } }
        $result = Get-IssueCompletion -Node (New-ClosedNode -Number 1 -Attempt $attempt) -Policy $policyVerify -DefaultHeadSha 'novo'
        $result.Reason | Should -Be 'parent_unverified'
    }

    It 'bloqueia quando o postMerge falhou' {
        $attempt = [pscustomobject]@{ postMerge = [pscustomobject]@{ result = 'fail'; baseSha = 'abc' } }
        $result = Get-IssueCompletion -Node (New-ClosedNode -Number 1 -Attempt $attempt) -Policy $policyVerify -DefaultHeadSha 'abc'
        $result.Reason | Should -Be 'parent_unverified'
    }

    It 'marca not planned como excluido, nao como concluido' {
        $result = Get-IssueCompletion -Node (New-ClosedNode -Number 1 -StateReason 'NOT_PLANNED') -Policy $policyVerify -DefaultHeadSha 'abc'
        $result.Status | Should -Be 'excluded'
        $result.Reason | Should -Be 'closed_not_planned'
    }

    It 'exige evidencia para trabalho sem codigo quando a politica pede' {
        $result = Get-IssueCompletion -Node (New-ClosedNode -Number 1 -HasCode $false) -Policy $policyVerify -DefaultHeadSha 'abc'
        $result.Status | Should -Be 'blocked'
        $result.Reason | Should -Be 'needs_manual'
    }

    It 'aceita trabalho sem codigo com evidencia registrada' {
        $attempt = [pscustomobject]@{
            evidence  = @([pscustomobject]@{ url = 'https://example.test/x' })
            postMerge = [pscustomobject]@{ result = 'pass'; baseSha = 'abc' }
        }
        $result = Get-IssueCompletion -Node (New-ClosedNode -Number 1 -HasCode $false -Attempt $attempt) -Policy $policyVerify -DefaultHeadSha 'abc'
        $result.Status | Should -Be 'done'
    }
}

Describe 'Get-BlockerReason' {
    It 'retorna nulo quando todos os blockers concluiram' {
        $index = @{ 'o/r#1' = New-ClosedNode -Number 1 }
        Get-BlockerReason -BlockerIds @('o/r#1') -Index $index -Policy $policyLoose -DefaultHeadSha 'abc' | Should -BeNullOrEmpty
    }

    It 'bloqueia por issue aberta' {
        $index = @{ 'o/r#1' = New-OpenNode -Number 1 }
        Get-BlockerReason -BlockerIds @('o/r#1') -Index $index -Policy $policyLoose -DefaultHeadSha 'abc' | Should -Be 'blocked_by_issue'
    }

    It 'bloqueia por blocker que falhou' {
        $index = @{ 'o/r#1' = New-OpenNode -Number 1 -AttemptStatus 'failed' }
        Get-BlockerReason -BlockerIds @('o/r#1') -Index $index -Policy $policyLoose -DefaultHeadSha 'abc' | Should -Be 'parent_failed'
    }

    It 'marca needs_manual quando o blocker foi fechado como not planned' {
        $index = @{ 'o/r#1' = New-ClosedNode -Number 1 -StateReason 'NOT_PLANNED' }
        Get-BlockerReason -BlockerIds @('o/r#1') -Index $index -Policy $policyLoose -DefaultHeadSha 'abc' | Should -Be 'needs_manual'
    }

    It 'marca parent_unverified quando o blocker fechado nao tem postMerge' {
        $index = @{ 'o/r#1' = New-ClosedNode -Number 1 }
        Get-BlockerReason -BlockerIds @('o/r#1') -Index $index -Policy $policyVerify -DefaultHeadSha 'abc' | Should -Be 'parent_unverified'
    }

    It 'marca infra quando o blocker nao esta no snapshot' {
        Get-BlockerReason -BlockerIds @('o/r#404') -Index @{} -Policy $policyLoose -DefaultHeadSha 'abc' | Should -Be 'infra'
    }

    It 'aplica precedencia quando ha varios blockers' {
        $index = @{
            'o/r#1' = New-OpenNode -Number 1
            'o/r#2' = New-OpenNode -Number 2 -AttemptStatus 'failed'
        }
        Get-BlockerReason -BlockerIds @('o/r#1', 'o/r#2') -Index $index -Policy $policyLoose -DefaultHeadSha 'abc' | Should -Be 'parent_failed'
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

```powershell
Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Dependency.Tests.ps1" -Output Detailed
```

Esperado: FAIL em `Get-IssueCompletion: CommandNotFoundException`.

- [ ] **Step 3: Implementar conclusão e satisfação de dependências**

Acrescente ao final de `delivery-queue/src/DeliveryQueue.Resolver.ps1`:

```powershell
function Get-IssueCompletion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Node,
        [Parameter(Mandatory)] [object]$Policy,
        [AllowNull()] [string]$DefaultHeadSha
    )

    if ([string](Get-Prop -Object $Node -Name 'stateReason') -eq 'NOT_PLANNED') {
        return [pscustomobject]@{ Status = 'excluded'; Reason = 'closed_not_planned' }
    }

    $attempt = Get-Prop -Object $Node -Name 'attempt'
    $hasCode = [bool](Get-Prop -Object $Node -Name 'hasCode' -Default $true)
    $completionMode = [string](Get-Prop -Object $Policy -Name 'completionWithoutCode')

    if (-not $hasCode -and $completionMode -eq 'requires-evidence') {
        $evidence = Get-Array -Value (Get-Prop -Object $attempt -Name 'evidence')
        if ($evidence.Count -eq 0) {
            return [pscustomobject]@{ Status = 'blocked'; Reason = 'needs_manual' }
        }
    }

    $merge = Get-Prop -Object $Policy -Name 'merge'
    if ([bool](Get-Prop -Object $merge -Name 'verifyDefaultBranchAfterMerge' -Default $false)) {
        $postMerge = Get-Prop -Object $attempt -Name 'postMerge'
        $result = [string](Get-Prop -Object $postMerge -Name 'result')
        $baseSha = [string](Get-Prop -Object $postMerge -Name 'baseSha')
        if ($result -ne 'pass' -or $baseSha -ne $DefaultHeadSha) {
            return [pscustomobject]@{ Status = 'blocked'; Reason = 'parent_unverified' }
        }
    }

    return [pscustomobject]@{ Status = 'done'; Reason = $null }
}

function Get-BlockerReason {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [string[]]$BlockerIds = @(),
        [Parameter(Mandatory)] [hashtable]$Index,
        [Parameter(Mandatory)] [object]$Policy,
        [AllowNull()] [string]$DefaultHeadSha
    )

    $precedence = @{
        infra             = 5
        needs_manual      = 4
        parent_failed     = 3
        parent_unverified = 2
        blocked_by_issue  = 1
    }

    $worst = $null

    foreach ($blockerId in @($BlockerIds)) {
        if (-not $Index.ContainsKey($blockerId)) {
            $reason = 'infra'
        }
        else {
            $blocker = $Index[$blockerId]
            if ([string](Get-Prop -Object $blocker -Name 'state') -eq 'CLOSED') {
                $completion = Get-IssueCompletion -Node $blocker -Policy $Policy -DefaultHeadSha $DefaultHeadSha
                if ($completion.Status -eq 'done') {
                    $reason = $null
                }
                elseif ($completion.Reason -eq 'closed_not_planned' -or $completion.Reason -eq 'needs_manual') {
                    $reason = 'needs_manual'
                }
                else {
                    $reason = 'parent_unverified'
                }
            }
            else {
                $attemptStatus = [string](Get-Prop -Object (Get-Prop -Object $blocker -Name 'attempt') -Name 'status')
                if ($attemptStatus -eq 'failed') { $reason = 'parent_failed' }
                else { $reason = 'blocked_by_issue' }
            }
        }

        if ($null -ne $reason) {
            if ($null -eq $worst -or $precedence[$reason] -gt $precedence[$worst]) { $worst = $reason }
        }
    }

    return $worst
}
```

Um blocker aberto com PR não satisfaz a dependência: o merge é o ponto de sincronização, então o dependente é `blocked_by_issue`.

- [ ] **Step 4: Rodar e ver que passa**

```powershell
Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Dependency.Tests.ps1" -Output Detailed
```

Esperado: `Tests Passed: 15, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Resolver.ps1 delivery-queue/tests/DeliveryQueue.Dependency.Tests.ps1
git commit -m "feat(delivery-queue): completion rules and dependency satisfaction"
```

---

### Task 4: Classificação de status por issue

**Files:**
- Modify: `delivery-queue/src/DeliveryQueue.Resolver.ps1` (append)
- Create: `delivery-queue/tests/DeliveryQueue.Classify.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Prop`, `Get-Array`, `Get-IssueCompletion`, `Get-BlockerReason` (Tasks 1 e 3).
- Produces:
  - `New-IssueStatusResult -Status <string> -Reason <string|null> -NextAction <string> -> [pscustomobject]@{ Status; Reason; NextAction }`.
  - `Get-IssueStatus -Node <object> -Index <hashtable> -Policy <object> [-Filter <object>] [-Attempted <int[]>] [-Retry <bool>] [-DefaultHeadSha <string|null>] -> [pscustomobject]@{ Status; Reason; NextAction }`.
  - `NextAction` assume: `none`, `reconcile`, `stop`, `implement`, `resume`, `update_branch`, `wait_checks`, `wait_merge`, `merge`.

O resolver lê quatro campos que o **coletor** deve calcular, e que não são derivados aqui: `pr.isDraft`, `pr.hasConflict`, `pr.checksComplete` e `ambiguousPr`. O `maxIssues` não é aplicado pelo resolver — é decisão de despacho do driver.

- [ ] **Step 1: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.Classify.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"

    function New-Policy {
        param([string]$MergeMode = 'human', [bool]$Verify = $false)
        [pscustomobject]@{
            mergeMode             = $MergeMode
            completionWithoutCode = 'allow-closed'
            merge                 = [pscustomobject]@{ verifyDefaultBranchAfterMerge = $Verify; authorizedByLocalRules = ($MergeMode -eq 'auto') }
        }
    }

    function New-Node {
        param(
            [int]$Number,
            [string]$State = 'OPEN',
            [string]$StateReason = $null,
            [string[]]$BlockedBy = @(),
            [object]$Pr = $null,
            [object]$Attempt = $null,
            [bool]$Eligible = $true,
            [bool]$Unknown = $false,
            [bool]$AmbiguousPr = $false
        )
        [pscustomobject]@{
            id          = "o/r#$Number"
            number      = $Number
            state       = $State
            stateReason = $StateReason
            hasCode     = $true
            inScope     = $true
            eligible    = $Eligible
            unknown     = $Unknown
            ambiguousPr = $AmbiguousPr
            blockedBy   = $BlockedBy
            pr          = $Pr
            attempt     = $Attempt
        }
    }

    function New-Pr {
        param([bool]$IsDraft = $false, [bool]$HasConflict = $false, [bool]$ChecksComplete = $true, [string]$State = 'OPEN')
        [pscustomobject]@{ state = $State; isDraft = $IsDraft; hasConflict = $HasConflict; checksComplete = $ChecksComplete }
    }
}

Describe 'Get-IssueStatus' {
    It 'marca unknown como infra' {
        $node = New-Node -Number 1 -Unknown $true
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'blocked'
        $r.Reason | Should -Be 'infra'
    }

    It 'bloqueia quando ha mais de uma PR candidata' {
        $node = New-Node -Number 1 -AmbiguousPr $true
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'blocked'
        $r.Reason | Should -Be 'ambiguous_pr'
    }

    It 'conclui issue fechada' {
        $node = New-Node -Number 1 -State 'CLOSED' -StateReason 'COMPLETED'
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'done'
        $r.NextAction | Should -Be 'reconcile'
    }

    It 'exclui issue fechada como not planned' {
        $node = New-Node -Number 1 -State 'CLOSED' -StateReason 'NOT_PLANNED'
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'excluded'
        $r.Reason | Should -Be 'closed_not_planned'
    }

    It 'bloqueia dependente de blocker aberto' {
        $index = @{ 'o/r#1' = New-Node -Number 1 }
        $node = New-Node -Number 2 -BlockedBy @('o/r#1')
        $r = Get-IssueStatus -Node $node -Index $index -Policy (New-Policy) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'blocked'
        $r.Reason | Should -Be 'blocked_by_issue'
    }

    It 'exclui issue nao elegivel' {
        $node = New-Node -Number 1 -Eligible $false
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'excluded'
        $r.Reason | Should -Be 'not_eligible'
    }

    It 'exclui issue fora do filtro' {
        $node = New-Node -Number 1
        $filter = [pscustomobject]@{ only = @(7) }
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -Filter $filter -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'excluded'
        $r.Reason | Should -Be 'filtered'
    }

    It 'exclui issue ja tentada nesta execucao' {
        $node = New-Node -Number 1
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -Attempted @(1) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'excluded'
        $r.Reason | Should -Be 'attempted'
    }

    It 'marca como runnable quando esta livre' {
        $node = New-Node -Number 1
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'runnable'
        $r.NextAction | Should -Be 'implement'
    }

    It 'suspende tentativa interrompida sem retry' {
        $node = New-Node -Number 1 -Attempt ([pscustomobject]@{ status = 'started' })
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'failed'
    }

    It 'permite retomada com retry' {
        $node = New-Node -Number 1 -Attempt ([pscustomobject]@{ status = 'started' })
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -Retry $true -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'runnable'
        $r.NextAction | Should -Be 'resume'
    }

    It 'mantem draft em progresso aguardando checks' {
        $node = New-Node -Number 1 -Pr (New-Pr -IsDraft $true)
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'in_progress'
        $r.NextAction | Should -Be 'wait_checks'
    }

    It 'aguarda merge humano quando a PR esta pronta' {
        $node = New-Node -Number 1 -Pr (New-Pr)
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy -MergeMode 'human') -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'blocked'
        $r.Reason | Should -Be 'awaiting_merge'
        $r.NextAction | Should -Be 'wait_merge'
    }

    It 'sinaliza merge quando auto e a PR esta pronta' {
        $node = New-Node -Number 1 -Pr (New-Pr)
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy -MergeMode 'auto') -DefaultHeadSha 'abc'
        $r.NextAction | Should -Be 'merge'
    }

    It 'sinaliza atualizar branch quando ha conflito' {
        $node = New-Node -Number 1 -Pr (New-Pr -HasConflict $true)
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy) -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'in_progress'
        $r.NextAction | Should -Be 'update_branch'
    }

    It 'sinaliza merge pendente quando o merge foi disparado e nao confirmou' {
        $attempt = [pscustomobject]@{ status = 'delivered'; merge = [pscustomobject]@{ mergeCommit = 'deadbeef' } }
        $node = New-Node -Number 1 -Pr (New-Pr -State 'OPEN') -Attempt $attempt
        $r = Get-IssueStatus -Node $node -Index @{} -Policy (New-Policy -MergeMode 'auto') -DefaultHeadSha 'abc'
        $r.Status | Should -Be 'in_progress'
        $r.Reason | Should -Be 'merge_pending'
        $r.NextAction | Should -Be 'reconcile'
    }
}
```

- [ ] **Step 2: Rodar e ver que falha**

```powershell
Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Classify.Tests.ps1" -Output Detailed
```

Esperado: FAIL em `Get-IssueStatus: CommandNotFoundException`.

- [ ] **Step 3: Implementar a classificação**

Acrescente ao final de `delivery-queue/src/DeliveryQueue.Resolver.ps1`:

```powershell
function New-IssueStatusResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Status,
        [AllowNull()] [string]$Reason,
        [Parameter(Mandatory)] [string]$NextAction
    )

    return [pscustomobject]@{ Status = $Status; Reason = $Reason; NextAction = $NextAction }
}

function Get-IssueStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Node,
        [Parameter(Mandatory)] [hashtable]$Index,
        [Parameter(Mandatory)] [object]$Policy,
        [AllowNull()] [object]$Filter = $null,
        [AllowEmptyCollection()] [int[]]$Attempted = @(),
        [bool]$Retry = $false,
        [AllowNull()] [string]$DefaultHeadSha = $null
    )

    $number = [int](Get-Prop -Object $Node -Name 'number' -Default 0)
    $attempt = Get-Prop -Object $Node -Name 'attempt'
    $pr = Get-Prop -Object $Node -Name 'pr'
    $mergeMode = [string](Get-Prop -Object $Policy -Name 'mergeMode')

    if ([bool](Get-Prop -Object $Node -Name 'unknown' -Default $false)) {
        return New-IssueStatusResult -Status 'blocked' -Reason 'infra' -NextAction 'stop'
    }

    if ([string](Get-Prop -Object $Node -Name 'state') -eq 'CLOSED') {
        $completion = Get-IssueCompletion -Node $Node -Policy $Policy -DefaultHeadSha $DefaultHeadSha
        if ($completion.Status -eq 'done') {
            return New-IssueStatusResult -Status 'done' -Reason $null -NextAction 'reconcile'
        }
        return New-IssueStatusResult -Status $completion.Status -Reason $completion.Reason -NextAction 'none'
    }

    if ([bool](Get-Prop -Object $Node -Name 'ambiguousPr' -Default $false)) {
        return New-IssueStatusResult -Status 'blocked' -Reason 'ambiguous_pr' -NextAction 'stop'
    }

    $blockerReason = Get-BlockerReason `
        -BlockerIds (Get-Array -Value (Get-Prop -Object $Node -Name 'blockedBy')) `
        -Index $Index -Policy $Policy -DefaultHeadSha $DefaultHeadSha
    if ($null -ne $blockerReason) {
        return New-IssueStatusResult -Status 'blocked' -Reason $blockerReason -NextAction 'none'
    }

    if (-not [bool](Get-Prop -Object $Node -Name 'eligible' -Default $true)) {
        return New-IssueStatusResult -Status 'excluded' -Reason 'not_eligible' -NextAction 'none'
    }

    $only = @(Get-Array -Value (Get-Prop -Object $Filter -Name 'only'))
    if ($only.Count -gt 0 -and ($only -notcontains $number)) {
        return New-IssueStatusResult -Status 'excluded' -Reason 'filtered' -NextAction 'none'
    }

    $attemptStatus = [string](Get-Prop -Object $attempt -Name 'status')
    if ($attemptStatus -in @('failed', 'started') -and -not $Retry) {
        return New-IssueStatusResult -Status 'failed' -Reason 'needs_manual' -NextAction 'stop'
    }

    if ($null -ne $pr) {
        $isDraft = [bool](Get-Prop -Object $pr -Name 'isDraft' -Default $false)
        $hasConflict = [bool](Get-Prop -Object $pr -Name 'hasConflict' -Default $false)
        $checksComplete = [bool](Get-Prop -Object $pr -Name 'checksComplete' -Default $false)
        $review = Get-Prop -Object $attempt -Name 'review'
        $reviewBlocking = [int](Get-Prop -Object $review -Name 'blocking' -Default 0)
        $mergeTriggered = $null -ne (Get-Prop -Object $attempt -Name 'merge')

        if ($hasConflict) {
            return New-IssueStatusResult -Status 'in_progress' -Reason $null -NextAction 'update_branch'
        }

        if ($mergeTriggered -and [string](Get-Prop -Object $pr -Name 'state') -ne 'MERGED') {
            return New-IssueStatusResult -Status 'in_progress' -Reason 'merge_pending' -NextAction 'reconcile'
        }

        $ready = (-not $isDraft) -and $checksComplete -and ($reviewBlocking -eq 0)
        if ($ready) {
            if ($mergeMode -eq 'human') {
                return New-IssueStatusResult -Status 'blocked' -Reason 'awaiting_merge' -NextAction 'wait_merge'
            }
            return New-IssueStatusResult -Status 'in_progress' -Reason $null -NextAction 'merge'
        }

        return New-IssueStatusResult -Status 'in_progress' -Reason 'checks_pending' -NextAction 'wait_checks'
    }

    if ($Attempted -contains $number) {
        return New-IssueStatusResult -Status 'excluded' -Reason 'attempted' -NextAction 'none'
    }

    if ($attemptStatus -in @('started', 'failed')) {
        return New-IssueStatusResult -Status 'runnable' -Reason $null -NextAction 'resume'
    }

    return New-IssueStatusResult -Status 'runnable' -Reason $null -NextAction 'implement'
}
```

A ordem dos gates segue a spec seção 6: primeiro conclusão/entrega, depois dados (`unknown`), depois dependências, depois elegibilidade e filtro. `-Attempted` só rebaixa quem seria `runnable`.

- [ ] **Step 4: Rodar e ver que passa**

```powershell
Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Classify.Tests.ps1" -Output Detailed
```

Esperado: `Tests Passed: 16, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add delivery-queue/src/DeliveryQueue.Resolver.ps1 delivery-queue/tests/DeliveryQueue.Classify.Tests.ps1
git commit -m "feat(delivery-queue): per-issue status classification"
```

---

### Task 5: Plano, CLI e ponta a ponta

**Files:**
- Modify: `delivery-queue/src/DeliveryQueue.Resolver.ps1` (append)
- Create: `delivery-queue/src/Resolve-Queue.ps1`
- Create: `delivery-queue/tests/fixtures/snapshot-linear.json`
- Create: `delivery-queue/tests/fixtures/snapshot-diamond.json`
- Create: `delivery-queue/tests/DeliveryQueue.Plan.Tests.ps1`

**Interfaces:**
- Consumes: tudo das Tasks 1–4.
- Produces:
  - `Resolve-QueuePlan -Snapshot <object> [-Attempted <int[]>] [-Retry <bool>] -> [pscustomobject]@{ Repository; Epic; DefaultBranch; Error; Order; Runnable; Issues; Diagnostics }`.
  - `Error` é `$null` ou `[pscustomobject]@{ Code = 'policy_invalid'|'dependency_cycle'; Messages = string[] }`.
  - `Issues` é ordenado topologicamente, com `{ IssueId, Number, Blockers, Status, Reason, NextAction, PrNumber, PrUrl, Branch, AttemptId }`.
  - CLI `Resolve-Queue.ps1 -SnapshotPath <path> [-Attempted <int[]>] [-Retry]`, imprime o plano em JSON. Saída: `0` plano produzido, `2` política inválida, `3` ciclo, `4` snapshot ausente/inválido.

Os fixtures são **ASCII puro** (sem acento) de propósito: `Get-Content -Raw` no PowerShell 5.1 pode interpretar arquivo sem BOM como ANSI, e isso corromperia strings.

- [ ] **Step 1: Criar o fixture linear**

Crie `delivery-queue/tests/fixtures/snapshot-linear.json`:

```json
{
  "schemaVersion": 1,
  "repository": "o/r",
  "epic": { "number": 9 },
  "defaultBranch": { "name": "master", "headSha": "aaa111" },
  "policy": {
    "version": 1,
    "defaultBranch": "master",
    "mergeMode": "human",
    "project": { "owner": "o", "number": 5, "eligibleStates": ["Ready"], "resumableStates": ["In Progress"] },
    "fallbackEligibility": null,
    "requiredChecks": [],
    "requiredRemoteChecks": [],
    "merge": { "method": "merge", "requireChecksOnPr": false, "verifyDefaultBranchAfterMerge": false, "authorizedByLocalRules": false, "allowAdminBypass": false },
    "completionWithoutCode": "allow-closed"
  },
  "filter": { "only": [] },
  "attempted": [],
  "issues": [
    { "id": "o/r#3", "number": 3, "title": "C", "state": "OPEN", "stateReason": null, "inScope": true, "eligible": true, "unknown": false, "blockedBy": ["o/r#2"], "pr": null, "attempt": null },
    { "id": "o/r#1", "number": 1, "title": "A", "state": "OPEN", "stateReason": null, "inScope": true, "eligible": true, "unknown": false, "blockedBy": [], "pr": null, "attempt": null },
    { "id": "o/r#2", "number": 2, "title": "B", "state": "OPEN", "stateReason": null, "inScope": true, "eligible": true, "unknown": false, "blockedBy": ["o/r#1"], "pr": null, "attempt": null }
  ]
}
```

- [ ] **Step 2: Criar o fixture diamante**

Crie `delivery-queue/tests/fixtures/snapshot-diamond.json`:

```json
{
  "schemaVersion": 1,
  "repository": "o/r",
  "epic": { "number": 9 },
  "defaultBranch": { "name": "master", "headSha": "aaa111" },
  "policy": {
    "version": 1,
    "defaultBranch": "master",
    "mergeMode": "human",
    "project": { "owner": "o", "number": 5, "eligibleStates": ["Ready"], "resumableStates": ["In Progress"] },
    "fallbackEligibility": null,
    "requiredChecks": [],
    "requiredRemoteChecks": [],
    "merge": { "method": "merge", "requireChecksOnPr": false, "verifyDefaultBranchAfterMerge": false, "authorizedByLocalRules": false, "allowAdminBypass": false },
    "completionWithoutCode": "allow-closed"
  },
  "filter": { "only": [] },
  "attempted": [],
  "issues": [
    { "id": "o/r#3", "number": 3, "title": "C", "state": "OPEN", "stateReason": null, "inScope": true, "eligible": true, "unknown": false, "blockedBy": ["o/r#1", "o/r#2"], "pr": null, "attempt": null },
    { "id": "o/r#1", "number": 1, "title": "A", "state": "OPEN", "stateReason": null, "inScope": true, "eligible": true, "unknown": false, "blockedBy": [], "pr": null, "attempt": null },
    { "id": "o/r#2", "number": 2, "title": "B", "state": "OPEN", "stateReason": null, "inScope": true, "eligible": true, "unknown": false, "blockedBy": [], "pr": null, "attempt": null }
  ]
}
```

- [ ] **Step 3: Escrever os testes que falham**

Crie `delivery-queue/tests/DeliveryQueue.Plan.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"

    $fixtureDir = "$PSScriptRoot/fixtures"

    function Read-Snapshot {
        param([string]$Name)
        Get-Content -LiteralPath "$fixtureDir/$Name" -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    function New-CycleSnapshot {
        [pscustomobject]@{
            repository    = 'o/r'
            epic          = [pscustomobject]@{ number = 9 }
            defaultBranch = [pscustomobject]@{ name = 'master'; headSha = 'aaa' }
            policy        = [pscustomobject]@{
                version = 1; defaultBranch = 'master'; mergeMode = 'human'
                project = [pscustomobject]@{ owner = 'o'; number = 5 }
                completionWithoutCode = 'allow-closed'
                merge   = [pscustomobject]@{ verifyDefaultBranchAfterMerge = $false; authorizedByLocalRules = $false }
            }
            filter        = [pscustomobject]@{ only = @() }
            attempted     = @()
            issues        = @(
                [pscustomobject]@{ id = 'o/r#1'; number = 1; state = 'OPEN'; inScope = $true; eligible = $true; blockedBy = @('o/r#2'); pr = $null; attempt = $null },
                [pscustomobject]@{ id = 'o/r#2'; number = 2; state = 'OPEN'; inScope = $true; eligible = $true; blockedBy = @('o/r#1'); pr = $null; attempt = $null }
            )
        }
    }

    function New-AutoWithoutAttestationSnapshot {
        [pscustomobject]@{
            repository    = 'o/r'
            epic          = [pscustomobject]@{ number = 9 }
            defaultBranch = [pscustomobject]@{ name = 'master'; headSha = 'aaa' }
            policy        = [pscustomobject]@{
                version = 1; defaultBranch = 'master'; mergeMode = 'auto'
                project = [pscustomobject]@{ owner = 'o'; number = 5 }
                completionWithoutCode = 'allow-closed'
                merge   = [pscustomobject]@{ verifyDefaultBranchAfterMerge = $false; authorizedByLocalRules = $false }
            }
            filter        = [pscustomobject]@{ only = @() }
            attempted     = @()
            issues        = @()
        }
    }
}

Describe 'Resolve-QueuePlan' {
    It 'ordena a cadeia linear e so libera a primeira' {
        $plan = Resolve-QueuePlan -Snapshot (Read-Snapshot 'snapshot-linear.json')
        $plan.Error | Should -BeNullOrEmpty
        $plan.Order | Should -Be @('o/r#1', 'o/r#2', 'o/r#3')
        $plan.Runnable | Should -Be @('o/r#1')
    }

    It 'bloqueia dependentes com o motivo da dependencia' {
        $plan = Resolve-QueuePlan -Snapshot (Read-Snapshot 'snapshot-linear.json')
        ($plan.Issues | Where-Object Number -eq 2).Reason | Should -Be 'blocked_by_issue'
        ($plan.Issues | Where-Object Number -eq 3).Reason | Should -Be 'blocked_by_issue'
    }

    It 'resolve diamante: os dois pais entram antes do filho' {
        $plan = Resolve-QueuePlan -Snapshot (Read-Snapshot 'snapshot-diamond.json')
        $plan.Order | Should -Be @('o/r#1', 'o/r#2', 'o/r#3')
        $plan.Runnable | Should -Be @('o/r#1', 'o/r#2')
    }

    It 'falha com erro explicito em ciclo, sem produzir ordem' {
        $plan = Resolve-QueuePlan -Snapshot (New-CycleSnapshot)
        $plan.Error.Code | Should -Be 'dependency_cycle'
        $plan.Order.Count | Should -Be 0
        $plan.Runnable.Count | Should -Be 0
    }

    It 'bloqueia antes de despachar quando auto nao tem atestacao' {
        $plan = Resolve-QueuePlan -Snapshot (New-AutoWithoutAttestationSnapshot)
        $plan.Error.Code | Should -Be 'policy_conflict'
        ($plan.Error.Messages -join ' ') | Should -Match 'authorizedByLocalRules'
    }

    It 'distingue politica malformada de conflito de precedencia' {
        $snapshot = New-AutoWithoutAttestationSnapshot
        $snapshot.policy.mergeMode = 'human'
        $snapshot.policy.version = 7
        $plan = Resolve-QueuePlan -Snapshot $snapshot
        $plan.Error.Code | Should -Be 'policy_invalid'
    }

    It 'exclui issue ja tentada nesta execucao' {
        $snapshot = Read-Snapshot 'snapshot-linear.json'
        $plan = Resolve-QueuePlan -Snapshot $snapshot -Attempted @(1)
        $plan.Runnable.Count | Should -Be 0
        ($plan.Issues | Where-Object Number -eq 1).Reason | Should -Be 'attempted'
    }
}

Describe 'Resolve-Queue.ps1 (CLI)' {
    It 'imprime o plano em JSON' {
        $output = & "$PSScriptRoot/../src/Resolve-Queue.ps1" -SnapshotPath "$fixtureDir/snapshot-linear.json"
        $plan = ($output | Out-String) | ConvertFrom-Json
        $plan.Order | Should -Be @('o/r#1', 'o/r#2', 'o/r#3')
        $plan.DefaultBranch.name | Should -Be 'master'
    }

    It 'retorna 3 para ciclo' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) 'cycle-snapshot.json'
        (New-CycleSnapshot) | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
        & "$PSScriptRoot/../src/Resolve-Queue.ps1" -SnapshotPath $path | Out-Null
        $LASTEXITCODE | Should -Be 3
    }

    It 'retorna 4 para snapshot inexistente' {
        & "$PSScriptRoot/../src/Resolve-Queue.ps1" -SnapshotPath "$PSScriptRoot/fixtures/nao-existe.json" | Out-Null
        $LASTEXITCODE | Should -Be 4
    }
}
```

- [ ] **Step 4: Rodar e ver que falha**

```powershell
Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Plan.Tests.ps1" -Output Detailed
```

Esperado: FAIL em `Resolve-QueuePlan: CommandNotFoundException`.

- [ ] **Step 5: Implementar o plano**

Acrescente ao final de `delivery-queue/src/DeliveryQueue.Resolver.ps1`:

```powershell
function Get-PolicyErrorCode {
    [CmdletBinding()]
    param([AllowEmptyCollection()] [string[]]$Problems = @())

    foreach ($problem in @($Problems)) {
        if ($problem -match '^policy_conflict:') { return 'policy_conflict' }
    }
    return 'policy_invalid'
}

function Resolve-QueuePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Snapshot,
        [AllowEmptyCollection()] [int[]]$Attempted = @(),
        [bool]$Retry = $false
    )

    $repository = [string](Get-Prop -Object $Snapshot -Name 'repository')
    $epicNumber = Get-Prop -Object (Get-Prop -Object $Snapshot -Name 'epic') -Name 'number'
    $policy = Get-Prop -Object $Snapshot -Name 'policy'
    $filter = Get-Prop -Object $Snapshot -Name 'filter'
    $defaultBranch = Get-Prop -Object $Snapshot -Name 'defaultBranch'
    $defaultBranchName = [string](Get-Prop -Object $defaultBranch -Name 'name')
    $defaultHeadSha = [string](Get-Prop -Object $defaultBranch -Name 'headSha')

    $policyProblems = @(Test-DeliveryQueuePolicy -Policy $policy)
    if ($policyProblems.Count -gt 0) {
        return New-PlanResult -ErrorCode (Get-PolicyErrorCode -Problems $policyProblems) -Repository $repository `
            -Epic $epicNumber -DefaultBranchName $defaultBranchName -DefaultHeadSha $defaultHeadSha -Messages $policyProblems
    }

    $topology = Get-TopologicalOrder -Snapshot $Snapshot

    if ($topology.Cycle.Count -gt 0) {
        return New-PlanResult -ErrorCode 'dependency_cycle' -Repository $repository -Epic $epicNumber `
            -DefaultBranchName $defaultBranchName -DefaultHeadSha $defaultHeadSha -Messages @($topology.Cycle)
    }

    $index = $topology.Index
    $attemptedNumbers = @(
        Get-Array -Value (Get-Prop -Object $Snapshot -Name 'attempted')
        Get-Array -Value $Attempted
    ) | ForEach-Object { [int]$_ }
    $issues = @()

    foreach ($id in $topology.Order) {
        $node = $index[$id]
        $status = Get-IssueStatus -Node $node -Index $index -Policy $policy -Filter $filter `
            -Attempted $attemptedNumbers -Retry $Retry -DefaultHeadSha $defaultHeadSha
        $pr = Get-Prop -Object $node -Name 'pr'
        $attempt = Get-Prop -Object $node -Name 'attempt'

        $issues += [pscustomobject]@{
            IssueId    = [string]$id
            Number     = [int](Get-Prop -Object $node -Name 'number' -Default 0)
            Blockers   = @(Get-Array -Value (Get-Prop -Object $node -Name 'blockedBy'))
            Status     = $status.Status
            Reason     = $status.Reason
            NextAction = $status.NextAction
            PrNumber   = Get-Prop -Object $pr -Name 'number'
            PrUrl      = Get-Prop -Object $pr -Name 'url'
            Branch     = [string](Get-Prop -Object $attempt -Name 'branch')
            AttemptId  = [string](Get-Prop -Object $attempt -Name 'attemptId')
        }
    }

    return [pscustomobject]@{
        Repository    = $repository
        Epic          = $epicNumber
        DefaultBranch = [pscustomobject]@{ name = $defaultBranchName; headSha = $defaultHeadSha }
        Error         = $null
        Order         = @($topology.Order)
        Runnable      = @($issues | Where-Object { $_.Status -eq 'runnable' } | ForEach-Object { $_.IssueId })
        Issues        = $issues
        Diagnostics   = @()
    }
}

function New-PlanResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ErrorCode,
        [AllowNull()] [string]$Repository,
        [AllowNull()] [object]$Epic,
        [AllowNull()] [string]$DefaultBranchName,
        [AllowNull()] [string]$DefaultHeadSha,
        [AllowEmptyCollection()] [string[]]$Messages = @()
    )

    return [pscustomobject]@{
        Repository    = $Repository
        Epic          = $Epic
        DefaultBranch = [pscustomobject]@{ name = $DefaultBranchName; headSha = $DefaultHeadSha }
        Error         = [pscustomobject]@{ Code = $ErrorCode; Messages = @($Messages) }
        Order         = @()
        Runnable      = @()
        Issues        = @()
        Diagnostics   = @()
    }
}
```

O parâmetro `Policy` inválida retorna erro antes de tocar no grafo, e o ciclo retorna erro sem produzir ordem — é o "antes de qualquer mutação" da spec seção 6.

- [ ] **Step 6: Implementar o CLI**

Crie `delivery-queue/src/Resolve-Queue.ps1`:

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$SnapshotPath,
    [AllowEmptyCollection()] [int[]]$Attempted = @(),
    [switch]$Retry
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')

if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) {
    Write-Error "snapshot nao encontrado: $SnapshotPath"
    exit 4
}

try {
    $snapshot = Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    Write-Error "snapshot invalido: $($_.Exception.Message)"
    exit 4
}

$plan = Resolve-QueuePlan -Snapshot $snapshot -Attempted $Attempted -Retry:$Retry
$plan | ConvertTo-Json -Depth 20

if ($null -eq $plan.Error) { exit 0 }
if ($plan.Error.Code -eq 'policy_invalid') { exit 2 }
if ($plan.Error.Code -eq 'dependency_cycle') { exit 3 }
exit 4
```

- [ ] **Step 7: Rodar e ver que passa**

```powershell
Invoke-Pester -Path "delivery-queue/tests/DeliveryQueue.Plan.Tests.ps1" -Output Detailed
```

Esperado: `Tests Passed: 10, Failed: 0`.

- [ ] **Step 8: Rodar a suíte inteira**

```powershell
Invoke-Pester -Path "delivery-queue/tests" -Output Detailed
```

Esperado: `Tests Passed: 66, Failed: 0` (2 de fumaça + 14 política + 9 grafo + 15 dependência + 16 classificação + 10 plano). Se o número divergir, o que importa é `Failed: 0`.

- [ ] **Step 9: Verificar o resolver contra o fixture pela linha de comando, como o driver faria**

```powershell
& "delivery-queue/src/Resolve-Queue.ps1" -SnapshotPath "delivery-queue/tests/fixtures/snapshot-linear.json" |
    Out-String | ConvertFrom-Json |
    Select-Object -ExpandProperty Issues |
    Format-Table Number, Status, Reason, NextAction -AutoSize
```

Esperado:

```text
Number Status    Reason            NextAction
------ ------    ------            ----------
     1 runnable                    implement
     2 blocked   blocked_by_issue  none
     3 blocked   blocked_by_issue  none
```

- [ ] **Step 10: Commit**

```bash
git add delivery-queue/src/Resolve-Queue.ps1 delivery-queue/tests/fixtures delivery-queue/tests/DeliveryQueue.Plan.Tests.ps1
git commit -m "feat(delivery-queue): plan assembly, CLI entrypoint and end-to-end fixtures"
```

---

## Definição de pronto

- `Invoke-Pester -Path "delivery-queue/tests"` sai com `Failed: 0`.
- `Resolve-Queue.ps1` roda pela linha de comando sobre os dois fixtures e devolve o plano em JSON.
- Nenhuma função em `DeliveryQueue.Resolver.ps1` chama `gh`, `git`, ou toca em disco.
- Ciclo de dependência e política inválida falham **antes** de qualquer ordenação consumível.

## Fora do escopo deste plano

- `Get-QueueSnapshot.ps1` (o coletor que produz o snapshot): próximo plano.
- `Deliver-Queue.ps1` (lock, despacho, merge, resumo): próximo plano.
- Agentes `delivery-queue-worker` / `-reviewer` / `-fixer` e o comando `delivery-queue-deliver-issue`.
- `schema/policy-v1.json` formal em JSON Schema: a validação da Task 1 é imperativa e cobre a v2.1, mas o schema publicado fica para o pacote inteiro.
- Decisões de distribuição (repositório do pacote e instalação).


