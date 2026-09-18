Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')

function Test-DeliveryQueuePreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Options,
        [AllowNull()] [string]$DefaultBranchName
    )

    $problems = @()
    $problems += Test-DeliveryQueuePolicy -Policy $Policy

    $repository = [string](Get-Prop -Object $Options -Name 'Repository')
    if ($repository -notmatch '^[^/]+/[^/]+$') {
        $problems += "repository invalido: '$repository'"
    }

    $max = Get-Prop -Object $Options -Name 'MaxIssues'
    if ($null -ne $max -and [int]$max -lt 1) {
        $problems += 'MaxIssues deve ser um inteiro positivo'
    }

    $timeout = Get-Prop -Object $Options -Name 'WorkerTimeoutMinutes'
    if ($null -ne $timeout -and [int]$timeout -lt 1) {
        $problems += 'WorkerTimeoutMinutes deve ser um inteiro positivo'
    }

    $policyBranch = [string](Get-Prop -Object $Policy -Name 'defaultBranch')
    if (-not [string]::IsNullOrWhiteSpace($DefaultBranchName) -and $policyBranch -ne $DefaultBranchName) {
        $problems += "policy_conflict: defaultBranch da policy '$policyBranch' difere de '$DefaultBranchName'"
    }

    return ,$problems
}

function Select-DeliveryAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Plan,
        [AllowEmptyCollection()] [int[]]$Attempted = @(),
        [int]$MaxIssues = 0,
        [bool]$HasLimit = $false
    )

    $issues = Get-Array -Value (Get-Prop -Object $Plan -Name 'Issues')

    foreach ($issue in $issues) {
        $action = [string](Get-Prop -Object $issue -Name 'NextAction')
        $status = [string](Get-Prop -Object $issue -Name 'Status')
        if ($action -eq 'reconcile' -and $status -notin @('done', 'excluded')) {
            return [pscustomobject]@{ Kind = 'recover'; Issue = $issue }
        }
    }
    foreach ($issue in $issues) {
        if ([string](Get-Prop -Object $issue -Name 'NextAction') -eq 'update_branch') {
            return [pscustomobject]@{ Kind = 'update_branch'; Issue = $issue }
        }
    }
    foreach ($issue in $issues) {
        if ([string](Get-Prop -Object $issue -Name 'NextAction') -eq 'merge') {
            return [pscustomobject]@{ Kind = 'merge'; Issue = $issue }
        }
    }
    foreach ($issue in $issues) {
        if ([string](Get-Prop -Object $issue -Name 'Status') -eq 'runnable') {
            if ($HasLimit -and $Attempted.Count -ge $MaxIssues) {
                return [pscustomobject]@{ Kind = 'limit'; Issue = $null }
            }
            return [pscustomobject]@{ Kind = 'dispatch'; Issue = $issue }
        }
    }

    return [pscustomobject]@{ Kind = 'none'; Issue = $null }
}

function New-DeliverySummary {
    [CmdletBinding()]
    param(
        [AllowNull()] [object]$Plan,
        [AllowEmptyCollection()] [int[]]$Attempted = @(),
        [bool]$Infra = $false,
        [bool]$Cancelled = $false,
        [bool]$LimitReached = $false,
        [AllowEmptyCollection()] [string[]]$Messages = @()
    )

    $lines = @()
    $failed = 0
    $blocked = 0
    $done = 0
    $excluded = 0
    $runnable = 0
    $allDelivered = $true

    $issues = @()
    if ($null -ne $Plan) { $issues = Get-Array -Value (Get-Prop -Object $Plan -Name 'Issues') }

    foreach ($issue in $issues) {
        $id = [string](Get-Prop -Object $issue -Name 'IssueId')
        $status = [string](Get-Prop -Object $issue -Name 'Status')
        $reason = [string](Get-Prop -Object $issue -Name 'Reason')
        $action = [string](Get-Prop -Object $issue -Name 'NextAction')

        switch ($status) {
            'failed' { $failed++ }
            'blocked' { $blocked++ }
            'done' { $done++ }
            'excluded' { $excluded++ }
            'runnable' { $runnable++ }
            'in_progress' {
                if ($reason -in @('checks_pending', 'merge_pending')) { $blocked++ }
            }
        }

        if ($status -notin @('done', 'excluded')) { $allDelivered = $false }

        $pr = [string](Get-Prop -Object $issue -Name 'PrNumber')
        $lines += ('{0}: status={1} reason={2} action={3} pr={4}' -f $id, $status, $reason, $action, $pr)
    }

    foreach ($message in @($Messages)) { $lines += "nota: $message" }

    return [pscustomobject]@{
        Infra = $Infra
        Cancelled = $Cancelled
        LimitReached = $LimitReached
        Failed = $failed
        Blocked = $blocked
        Done = $done
        Excluded = $excluded
        Runnable = $runnable
        AllDelivered = $allDelivered
        Text = ($lines -join "`n")
    }
}

function Get-DeliveryExitCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Summary)

    if ([bool](Get-Prop -Object $Summary -Name 'Infra' -Default $false)) { return 4 }
    if ([bool](Get-Prop -Object $Summary -Name 'Cancelled' -Default $false)) { return 130 }
    if ([int](Get-Prop -Object $Summary -Name 'Failed' -Default 0) -gt 0) { return 3 }
    if ([int](Get-Prop -Object $Summary -Name 'Blocked' -Default 0) -gt 0) { return 2 }
    if ([bool](Get-Prop -Object $Summary -Name 'LimitReached' -Default $false)) { return 1 }
    return 0
}

function New-AttemptId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Now,
        [Parameter(Mandatory)] [int]$Suffix
    )

    $stamp = $null
    try {
        $stamp = ([datetimeoffset]::Parse($Now)).UtcDateTime.ToString('yyyyMMddTHHmmZ')
    }
    catch {
        $stamp = ($Now -replace '[^0-9TZ]', '')
    }
    if ([string]::IsNullOrWhiteSpace($stamp)) { $stamp = '00000000T0000Z' }
    return ('{0}-{1:x4}' -f $stamp, $Suffix)
}

function Get-BranchSlug {
    [CmdletBinding()]
    param([AllowNull()] [string]$Title)

    $slug = ([string]$Title).ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'issue' }
    if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).Trim('-') }
    return $slug
}
