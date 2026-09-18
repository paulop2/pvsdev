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
