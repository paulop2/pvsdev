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
