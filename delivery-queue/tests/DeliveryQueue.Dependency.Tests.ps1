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

    It 'bloqueia quando o postMerge pass nao traz baseSha' {
        $attempt = [pscustomobject]@{ postMerge = [pscustomobject]@{ result = 'pass' } }
        $result = Get-IssueCompletion -Node (New-ClosedNode -Number 1 -Attempt $attempt) -Policy $policyVerify -DefaultHeadSha 'abc'
        $result.Status | Should -Be 'blocked'
        $result.Reason | Should -Be 'parent_unverified'
    }

    It 'bloqueia quando o head atual e desconhecido mesmo com postMerge pass' {
        $attempt = [pscustomobject]@{ postMerge = [pscustomobject]@{ result = 'pass'; baseSha = 'abc' } }
        $result = Get-IssueCompletion -Node (New-ClosedNode -Number 1 -Attempt $attempt) -Policy $policyVerify -DefaultHeadSha $null
        $result.Status | Should -Be 'blocked'
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
