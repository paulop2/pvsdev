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
