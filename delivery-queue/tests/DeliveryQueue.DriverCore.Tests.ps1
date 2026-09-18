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
    It 'nao recupera issue done com reconcile' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'done' -NextAction 'reconcile'))
        (Select-DeliveryAction -Plan $plan).Kind | Should -Be 'none'
    }
    It 'nao recupera issue excluded com reconcile' {
        $plan = New-Plan @((New-PlanIssue -IssueId 'o/r#1' -Number 1 -Status 'excluded' -NextAction 'reconcile'))
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
