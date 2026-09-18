Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Pages.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Attempt.ps1')

function Get-CollectorLabels {
    [CmdletBinding()]
    param([AllowNull()] [object]$Issue)

    $names = @()
    foreach ($label in (Get-Array -Value (Get-Prop -Object $Issue -Name 'labels'))) {
        if ($label -is [string]) { $names += $label; continue }
        $name = [string](Get-Prop -Object $label -Name 'name')
        if (-not [string]::IsNullOrWhiteSpace($name)) { $names += $name }
    }
    return ,$names
}

function Get-IssueEligibility {
    [CmdletBinding()]
    param(
        [AllowNull()] [object]$Issue,
        [Parameter(Mandatory)] [object]$Policy,
        [AllowNull()] [object]$ProjectState
    )

    $project = Get-Prop -Object $Policy -Name 'project'
    if ($null -ne $project) {
        $found = [bool](Get-Prop -Object $ProjectState -Name 'found' -Default $false)
        $state = [string](Get-Prop -Object $ProjectState -Name 'state')
        $states = Get-Array -Value (Get-Prop -Object $project -Name 'eligibleStates')
        $states += Get-Array -Value (Get-Prop -Object $project -Name 'resumableStates')
        return [pscustomobject]@{ Eligible = ($found -and ($states -contains $state)); Unknown = (-not $found) }
    }

    $fallback = [string](Get-Prop -Object $Policy -Name 'fallbackEligibility')
    if ($fallback -match '^label:(?<name>.+)$') {
        $label = $Matches['name']
        $labels = Get-CollectorLabels -Issue $Issue
        return [pscustomobject]@{ Eligible = ($labels -contains $label); Unknown = $false }
    }

    return [pscustomobject]@{ Eligible = $false; Unknown = $true }
}

function Test-RemoteChecksComplete {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [object[]]$Checks = @(),
        [bool]$ChecksKnown = $false,
        [Parameter(Mandatory)] [object]$Policy
    )

    if (-not $ChecksKnown) { return $false }

    $merge = Get-Prop -Object $Policy -Name 'merge'
    $requireChecks = [bool](Get-Prop -Object $merge -Name 'requireChecksOnPr' -Default $false)
    if (-not $requireChecks) { return $true }

    $accepted = @('SUCCESS', 'NEUTRAL', 'SKIPPED')
    $byContext = @{}
    foreach ($check in @($Checks)) {
        $context = [string](Get-Prop -Object $check -Name 'context')
        $conclusion = [string](Get-Prop -Object $check -Name 'conclusion')
        $byContext[$context] = $conclusion
    }

    $required = Get-Array -Value (Get-Prop -Object $Policy -Name 'requiredRemoteChecks')
    if ($required.Count -gt 0) {
        foreach ($context in $required) {
            if (-not $byContext.ContainsKey($context)) { return $false }
            if ($byContext[$context] -notin $accepted) { return $false }
        }
        return $true
    }

    foreach ($context in $byContext.Keys) {
        if ($byContext[$context] -notin $accepted) { return $false }
    }
    return $true
}

function Select-IssuePr {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [object[]]$Prs = @(),
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [int]$Issue,
        [Parameter(Mandatory)] [object]$DefaultBranch,
        [Parameter(Mandatory)] [object]$Policy
    )

    $defaultName = [string](Get-Prop -Object $DefaultBranch -Name 'name')
    $candidates = @()
    foreach ($pr in @($Prs)) {
        if ([string](Get-Prop -Object $pr -Name 'baseRefName') -eq $defaultName) {
            $candidates += $pr
        }
    }

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{ Pr = $null; Ambiguous = $false }
    }
    if ($candidates.Count -gt 1) {
        return [pscustomobject]@{ Pr = $null; Ambiguous = $true }
    }

    $pr = $candidates[0]
    $checks = Get-Array -Value (Get-Prop -Object $pr -Name 'checks')
    $checksKnown = [bool](Get-Prop -Object $pr -Name 'checksKnown' -Default $false)
    $complete = Test-RemoteChecksComplete -Checks $checks -ChecksKnown $checksKnown -Policy $Policy

    return [pscustomobject]@{
        Pr = [pscustomobject]@{
            number         = [int](Get-Prop -Object $pr -Name 'number')
            url            = [string](Get-Prop -Object $pr -Name 'url')
            state          = [string](Get-Prop -Object $pr -Name 'state')
            isDraft        = [bool](Get-Prop -Object $pr -Name 'isDraft' -Default $false)
            hasConflict    = [bool](Get-Prop -Object $pr -Name 'hasConflict' -Default $false)
            checksComplete = $complete
            headSha        = [string](Get-Prop -Object $pr -Name 'headSha')
            baseRefName    = $defaultName
            headRefName    = [string](Get-Prop -Object $pr -Name 'headRefName')
        }
        Ambiguous = $false
    }
}
