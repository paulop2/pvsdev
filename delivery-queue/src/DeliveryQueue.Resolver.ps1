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

    if ($null -eq $Value) { return ,@() }
    return ,@($Value)
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

    return ,$problems
}

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
            $number = Get-Prop -Object $node -Name 'number'
            if ($null -ne $number -and [int]$number -gt 0) {
                $id = New-IssueId -Repository $repository -Number ([int]$number)
            }
            else {
                $id = "$repository#unknown-$($index.Count)"
                if ($null -eq $node.PSObject.Properties['unknown']) {
                    $node | Add-Member -NotePropertyName 'unknown' -NotePropertyValue $true
                }
                else {
                    $node.unknown = $true
                }
            }
        }
        if ($index.ContainsKey($id)) {
            throw "id duplicado no snapshot: $id"
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
        $currentHead = [string]$DefaultHeadSha
        if ($result -ne 'pass' -or
            [string]::IsNullOrWhiteSpace($baseSha) -or
            [string]::IsNullOrWhiteSpace($currentHead) -or
            $baseSha -ne $currentHead) {
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

    if ($null -ne $pr -and [string](Get-Prop -Object $pr -Name 'state') -eq 'MERGED') {
        $completion = Get-IssueCompletion -Node $Node -Policy $Policy -DefaultHeadSha $DefaultHeadSha
        if ($completion.Status -eq 'done') {
            return New-IssueStatusResult -Status 'done' -Reason $null -NextAction 'reconcile'
        }
        return New-IssueStatusResult -Status $completion.Status -Reason $completion.Reason -NextAction 'reconcile'
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

    $only = Get-Array -Value (Get-Prop -Object $Filter -Name 'only')
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

    $policyProblems = @()
    $policyProblems += Test-DeliveryQueuePolicy -Policy $policy

    $policyDefaultBranch = [string](Get-Prop -Object $policy -Name 'defaultBranch')
    if (-not [string]::IsNullOrWhiteSpace($policyDefaultBranch) -and
        -not [string]::IsNullOrWhiteSpace($defaultBranchName) -and
        $policyDefaultBranch -ne $defaultBranchName) {
        $policyProblems += "policy_conflict: defaultBranch da policy '$policyDefaultBranch' difere do defaultBranch do snapshot '$defaultBranchName'"
    }

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
    $attemptedNumbers = @()
    $attemptedNumbers += Get-Array -Value (Get-Prop -Object $Snapshot -Name 'attempted')
    $attemptedNumbers += Get-Array -Value $Attempted
    $attemptedNumbers = @($attemptedNumbers | ForEach-Object { [int]$_ })
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
            Blockers   = (Get-Array -Value (Get-Prop -Object $node -Name 'blockedBy'))
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
