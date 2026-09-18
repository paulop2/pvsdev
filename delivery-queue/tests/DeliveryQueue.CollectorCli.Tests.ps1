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
