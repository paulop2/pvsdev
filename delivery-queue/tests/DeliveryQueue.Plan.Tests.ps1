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
