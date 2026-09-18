Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Attempt.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.DriverCore.ps1')

function Complete-AttemptRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Record)

    foreach ($field in @('base', 'baseSha', 'headSha', 'reason', 'review', 'merge', 'postMerge', 'nextAction', 'updatedAt')) {
        if ($null -eq $Record.PSObject.Properties[$field]) {
            $Record | Add-Member -NotePropertyName $field -NotePropertyValue $null -Force
        }
    }
    if ($null -eq $Record.PSObject.Properties['checks']) {
        $Record | Add-Member -NotePropertyName 'checks' -NotePropertyValue @() -Force
    }
    return $Record
}

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
        return @("issue ${number}: reconciliacao sem PR")
    }

    $pr = & $Io.GetPr -Repository $repository -Number ([int]$prNumber)
    $record = & $Io.ReadAttempt -Repository $repository -Issue $number

    if ($null -eq $record) {
        return @("issue ${number}: reconciliacao sem registro de tentativa")
    }
    $record = Complete-AttemptRecord -Record $record

    if ([string](Get-Prop -Object $pr -Name 'state') -eq 'MERGED') {
        $merge = Get-Prop -Object $Policy -Name 'merge'
        $record.status = 'merged'
        $record.reason = $null
        if ([bool](Get-Prop -Object $merge -Name 'verifyDefaultBranchAfterMerge' -Default $false)) {
            $existing = Get-Prop -Object $record -Name 'postMerge'
            $currentHead = & $Io.GetDefaultHead -Repository $repository -Branch ([string](Get-Prop -Object $Policy -Name 'defaultBranch'))
            $valid = ([string](Get-Prop -Object $existing -Name 'result') -eq 'pass') -and ([string](Get-Prop -Object $existing -Name 'baseSha') -eq [string]$currentHead) -and (-not [string]::IsNullOrWhiteSpace([string]$currentHead))
            if (-not $valid) {
                $checked = & $Io.VerifyPostMerge -Repository $repository -Branch ([string](Get-Prop -Object $Policy -Name 'defaultBranch')) -Commands (Get-Array -Value (Get-Prop -Object $Policy -Name 'requiredChecks'))
                $record.postMerge = $checked
            }
            if ([string](Get-Prop -Object (Get-Prop -Object $record -Name 'postMerge') -Name 'result') -ne 'pass') {
                $record.status = 'failed'
                $record.reason = 'post_merge_red'
            }
        }
        $record.updatedAt = & $Io.GetNow
        & $Io.UpsertAttempt -Repository $repository -Issue $number -Record $record | Out-Null
        if ($record.status -eq 'failed') {
            return @("issue ${number}: pos-merge vermelho, loop encerra em failed")
        }
        return @("issue ${number}: merge reconciliado")
    }

    return @("issue ${number}: merge pendente")
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
    if (-not [bool](Get-Prop -Object $result -Name 'updated' -Default $false) -and -not [bool](Get-Prop -Object $result -Name 'conflict' -Default $false)) {
        return @("issue ${number}: worktree ausente para atualizar a branch")
    }

    $record = & $Io.ReadAttempt -Repository $repository -Issue $number
    if ($null -ne $record) {
        $record = Complete-AttemptRecord -Record $record
        if ([bool](Get-Prop -Object $result -Name 'conflict' -Default $false)) {
            $record.status = 'blocked'
            $record.reason = 'needs_manual'
            $record.updatedAt = & $Io.GetNow
            & $Io.UpsertAttempt -Repository $repository -Issue $number -Record $record | Out-Null
            return @("issue ${number}: conflito nao resolvido, needs_manual")
        }
        $record.checks = @()
        $record.review = $null
        $record.status = 'started'
        $record.updatedAt = & $Io.GetNow
        & $Io.UpsertAttempt -Repository $repository -Issue $number -Record $record | Out-Null
    }

    return @("issue ${number}: branch atualizada, nova verificacao requerida")
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
    if ($null -ne $record) { $record = Complete-AttemptRecord -Record $record }

    $readiness = Test-MergeReadiness -Pr $pr -Attempt $record -Policy $Policy -HeadSha $headSha
    if (-not $readiness.Ready) {
        return @("issue ${number}: gate recusou ($((Get-Array -Value $readiness.Reasons) -join ','))")
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
        return @("issue ${number}: merge pendente (merge queue)")
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
        return @("issue ${number}: pos-merge vermelho, loop encerra em failed")
    }
    return @("issue ${number}: merged")
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
    if ($null -ne $current) { $record = Complete-AttemptRecord -Record $current }

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

    return @("issue ${number}: despachada em $branch")
}

function Invoke-DeliveryLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Options,
        [Parameter(Mandatory)] [object]$Io
    )

    $attempted = @()
    $handled = @()
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
            $collected = & $Io.Collect -Repository $Options.Repository -Epic $Options.Epic -Only $Options.Only
            $snapshot = $collected
            if ($null -eq (Get-Prop -Object $collected -Name 'Ok')) {
                $snapshot = [pscustomobject]@{ Ok = $true; Error = $null; Snapshot = $collected }
            }
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
            $collected = $null
            $collectAttempts = 0
            while ($true) {
                $collectAttempts++
                try {
                    $collected = & $Io.Collect -Repository $Options.Repository -Epic $Options.Epic -Only $Options.Only
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

            $snapshot = $collected
            if ($null -eq (Get-Prop -Object $collected -Name 'Ok')) {
                $snapshot = [pscustomobject]@{ Ok = $true; Error = $null; Snapshot = $collected }
            }

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
            $action = Select-DeliveryAction -Plan $plan -Attempted $attempted -MaxIssues $maxIssues -HasLimit ([bool](Get-Prop -Object $Options -Name 'HasLimit' -Default $false)) -Handled $handled

            if ($action.Kind -eq 'none') { break }
            if ($action.Kind -eq 'limit') { $limit = $true; break }

            switch ($action.Kind) {
                'recover' {
                    $messages += Invoke-RecoverAction -Io $Io -Policy $Policy -Options $Options -Issue $action.Issue
                    $handled += [string](Get-Prop -Object $action.Issue -Name 'IssueId')
                }
                'update_branch' {
                    $messages += Invoke-UpdateBranchAction -Io $Io -Policy $Policy -Options $Options -Issue $action.Issue
                    $handled += [string](Get-Prop -Object $action.Issue -Name 'IssueId')
                }
                'merge' {
                    $messages += Invoke-MergeAction -Io $Io -Policy $Policy -Options $Options -Issue $action.Issue
                    $handled += [string](Get-Prop -Object $action.Issue -Name 'IssueId')
                }
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
