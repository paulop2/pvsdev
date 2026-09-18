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

function New-CollectorError {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Code, [Parameter(Mandatory)] [string]$Message)
    return [pscustomobject]@{
        Ok = $false
        Error = [pscustomobject]@{ Code = $Code; Messages = @($Message) }
        Snapshot = $null
    }
}

function New-CollectorIssueNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Raw,
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [object]$DefaultBranch,
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Gh,
        [bool]$InScope = $true
    )

    $number = [int](Get-Prop -Object $Raw -Name 'number')
    $id = [string](Get-Prop -Object $Raw -Name 'id')
    if ([string]::IsNullOrWhiteSpace($id)) {
        $id = New-IssueId -Repository $Repository -Number $number
    }

    $unknown = $false

    $project = Get-Prop -Object $Policy -Name 'project'
    $projectState = $null
    if ($null -ne $project) {
        try {
            $projectState = & $Gh.GetProjectState `
                -Owner ([string](Get-Prop -Object $project -Name 'owner')) `
                -Number ([int](Get-Prop -Object $project -Name 'number')) `
                -NodeId ([string](Get-Prop -Object $Raw -Name 'nodeId'))
        }
        catch {
            $projectState = [pscustomobject]@{ found = $false; state = $null }
        }
    }
    $eligibility = Get-IssueEligibility -Issue $Raw -Policy $Policy -ProjectState $projectState
    if ([bool]$eligibility.Unknown) { $unknown = $true }

    $attempt = $null
    try {
        $comments = @(& $Gh.GetIssueComments -Repository $Repository -Issue $number)
        $attempt = Select-LatestAttempt -Comments $comments
    }
    catch { $unknown = $true }

    $pr = $null
    $ambiguous = $false
    try {
        $prs = @(& $Gh.GetIssuePrs -Repository $Repository -Issue $number)
        $selected = Select-IssuePr -Prs $prs -Repository $Repository -Issue $number -DefaultBranch $DefaultBranch -Policy $Policy
        $pr = $selected.Pr
        $ambiguous = [bool]$selected.Ambiguous
    }
    catch { $unknown = $true }

    $blockedBy = @()
    foreach ($blocker in (Get-Array -Value (Get-Prop -Object $Raw -Name 'blockedBy'))) {
        $blockedBy += [string]$blocker
    }

    return [pscustomobject]@{
        id          = $id
        number      = $number
        title       = [string](Get-Prop -Object $Raw -Name 'title')
        state       = [string](Get-Prop -Object $Raw -Name 'state')
        stateReason = Get-Prop -Object $Raw -Name 'stateReason'
        hasCode     = [bool](Get-Prop -Object $Raw -Name 'hasCode' -Default $true)
        inScope     = $InScope
        eligible    = [bool]$eligibility.Eligible
        unknown     = $unknown
        ambiguousPr = $ambiguous
        blockedBy   = $blockedBy
        pr          = $pr
        attempt     = $attempt
    }
}

function New-QueueSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [int]$Epic,
        [Parameter(Mandatory)] [object]$Policy,
        [Parameter(Mandatory)] [object]$Gh,
        [AllowNull()] [object]$Filter = $null
    )

    if ($null -eq $Filter) { $Filter = [pscustomobject]@{ only = @() } }

    try {
        $defaultBranch = & $Gh.GetDefaultBranch -Repository $Repository
    }
    catch {
        return New-CollectorError -Code 'infra' -Message "falha ao ler a branch padrao: $($_.Exception.Message)"
    }
    if ($null -eq $defaultBranch) {
        return New-CollectorError -Code 'infra' -Message 'branch padrao indisponivel'
    }

    try {
        $subIssues = @(& $Gh.GetSubIssues -Repository $Repository -Epic $Epic)
    }
    catch {
        return New-CollectorError -Code 'infra' -Message "falha ao coletar sub-issues: $($_.Exception.Message)"
    }

    $rawByNumber = @{}
    foreach ($raw in $subIssues) {
        $rawByNumber[[int](Get-Prop -Object $raw -Name 'number')] = $raw
    }

    $externalIds = @()
    foreach ($raw in $subIssues) {
        foreach ($blocker in (Get-Array -Value (Get-Prop -Object $raw -Name 'blockedBy'))) {
            $blockerId = [string]$blocker
            if ($blockerId -match '#(?<n>\d+)$') {
                $blockerNumber = [int]$Matches['n']
                if (-not $rawByNumber.ContainsKey($blockerNumber) -and ($externalIds -notcontains $blockerId)) {
                    $externalIds += $blockerId
                }
            }
        }
    }

    $externalStates = @{}
    if ($externalIds.Count -gt 0) {
        try {
            $externalStates = & $Gh.GetBlockerIssues -Repository $Repository -Ids $externalIds
            if ($null -eq $externalStates) { throw 'blockers externos indisponiveis' }
        }
        catch {
            return New-CollectorError -Code 'infra' -Message "falha ao coletar blockers externos: $($_.Exception.Message)"
        }
    }

    $issues = @()
    foreach ($raw in $subIssues) {
        $issues += New-CollectorIssueNode -Raw $raw -Repository $Repository -DefaultBranch $defaultBranch -Policy $Policy -Gh $Gh -InScope $true
    }

    foreach ($externalId in $externalIds) {
        $state = $null
        if ($externalStates.ContainsKey($externalId)) { $state = $externalStates[$externalId] }
        $number = 0
        if ($externalId -match '#(?<n>\d+)$') { $number = [int]$Matches['n'] }
        $issues += [pscustomobject]@{
            id          = $externalId
            number      = $number
            title       = ''
            state       = [string](Get-Prop -Object $state -Name 'state')
            stateReason = Get-Prop -Object $state -Name 'stateReason'
            hasCode     = $true
            inScope     = $false
            eligible    = $true
            unknown     = ($null -eq $state)
            ambiguousPr = $false
            blockedBy   = @()
            pr          = $null
            attempt     = $null
        }
    }

    $snapshot = [pscustomobject]@{
        schemaVersion = 1
        repository    = $Repository
        epic          = [pscustomobject]@{ number = $Epic }
        defaultBranch = [pscustomobject]@{
            name    = [string](Get-Prop -Object $defaultBranch -Name 'name')
            headSha = [string](Get-Prop -Object $defaultBranch -Name 'headSha')
        }
        policy        = $Policy
        filter        = [pscustomobject]@{ only = (Get-Array -Value (Get-Prop -Object $Filter -Name 'only')) }
        attempted     = @()
        issues        = $issues
    }

    return [pscustomobject]@{ Ok = $true; Error = $null; Snapshot = $snapshot }
}
