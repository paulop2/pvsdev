Set-StrictMode -Version Latest

function New-TestPolicy {
    [CmdletBinding()]
    param(
        [string]$MergeMode = 'human',
        [bool]$Verify = $false,
        [AllowEmptyCollection()] [string[]]$RequiredRemoteChecks = @(),
        [bool]$RequireChecksOnPr = $true,
        [AllowNull()] [object]$Project = $null,
        [AllowNull()] [string]$Fallback = $null
    )

    if ($null -eq $Project -and [string]::IsNullOrWhiteSpace($Fallback)) {
        $Project = [pscustomobject]@{
            owner = 'o'; number = 5
            eligibleStates = @('Ready'); resumableStates = @('In Progress')
        }
    }

    return [pscustomobject]@{
        version = 1
        defaultBranch = 'master'
        mergeMode = $MergeMode
        project = $Project
        fallbackEligibility = $Fallback
        requiredChecks = @('npm run build')
        requiredRemoteChecks = $RequiredRemoteChecks
        merge = [pscustomobject]@{
            method = 'merge'; requireChecksOnPr = $RequireChecksOnPr
            verifyDefaultBranchAfterMerge = $Verify
            authorizedByLocalRules = ($MergeMode -eq 'auto'); allowAdminBypass = $false
        }
        completionWithoutCode = 'allow-closed'
        workerTimeoutMinutes = 60
        worktreeRoot = '..'
    }
}

function New-GhFake {
    [CmdletBinding()]
    param(
        [scriptblock]$GetDefaultBranch,
        [scriptblock]$GetSubIssues,
        [scriptblock]$GetProjectState,
        [scriptblock]$GetIssueComments,
        [scriptblock]$GetIssuePrs,
        [scriptblock]$GetBlockerIssues,
        [scriptblock]$GetRefSha
    )

    if (-not $GetDefaultBranch) { $GetDefaultBranch = { param($Repository) [pscustomobject]@{ name = 'master'; headSha = 'base-sha' } } }
    if (-not $GetSubIssues) { $GetSubIssues = { param($Repository, $Epic) @() } }
    if (-not $GetProjectState) { $GetProjectState = { param($Owner, $Number, $NodeId) [pscustomobject]@{ found = $true; state = 'Ready' } } }
    if (-not $GetIssueComments) { $GetIssueComments = { param($Repository, $Issue) @() } }
    if (-not $GetIssuePrs) { $GetIssuePrs = { param($Repository, $Issue) @() } }
    if (-not $GetBlockerIssues) { $GetBlockerIssues = { param($Repository, $Ids) @{} } }
    if (-not $GetRefSha) { $GetRefSha = { param($Ref) $null } }

    return [pscustomobject]@{
        GetDefaultBranch = $GetDefaultBranch
        GetSubIssues     = $GetSubIssues
        GetProjectState  = $GetProjectState
        GetIssueComments = $GetIssueComments
        GetIssuePrs      = $GetIssuePrs
        GetBlockerIssues = $GetBlockerIssues
        GetRefSha        = $GetRefSha
    }
}

function New-IoFake {
    [CmdletBinding()]
    param(
        [scriptblock]$Collect, [scriptblock]$AcquireLock, [scriptblock]$ReleaseLock,
        [scriptblock]$FetchDefault, [scriptblock]$GetDefaultHead, [scriptblock]$EnsureWorktree,
        [scriptblock]$ReadAttempt, [scriptblock]$UpsertAttempt, [scriptblock]$DispatchWorker,
        [scriptblock]$GetPr, [scriptblock]$RunLocalChecks, [scriptblock]$UpdateBranch,
        [scriptblock]$MergePr, [scriptblock]$VerifyPostMerge, [scriptblock]$WriteSummary,
        [scriptblock]$GetNow, [scriptblock]$IsCancelled, [scriptblock]$Sleep, [scriptblock]$Log
    )

    if (-not $Collect) { $Collect = { param($Repository, $Epic, $Only) throw 'Collect fake nao configurado' } }
    if (-not $AcquireLock) { $AcquireLock = { param($Repository) [pscustomobject]@{ Acquired = $true; Path = 'lock'; Stream = $null; Repository = $Repository } } }
    if (-not $ReleaseLock) { $ReleaseLock = { param($Lock) } }
    if (-not $FetchDefault) { $FetchDefault = { param($Repository, $Branch) 'base-sha' } }
    if (-not $EnsureWorktree) { $EnsureWorktree = { param($Repository, $Branch, $Base, $Root) [pscustomobject]@{ path = 'wt'; branch = $Branch } } }
    if (-not $ReadAttempt) { $ReadAttempt = { param($Repository, $Issue) $null } }
    if (-not $UpsertAttempt) { $UpsertAttempt = { param($Repository, $Issue, $Record) 'c1' } }
    if (-not $DispatchWorker) { $DispatchWorker = { param($Issue, $Repository, $Base, $Worktree, $TimeoutMinutes) [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' } } }
    if (-not $GetPr) { $GetPr = { param($Repository, $Number) [pscustomobject]@{ number = $Number; state = 'OPEN'; isDraft = $false; hasConflict = $false; checksComplete = $true; headSha = 'h1'; url = 'u'; baseRefName = 'master'; headRefName = 'feat/x' } } }
    if (-not $RunLocalChecks) { $RunLocalChecks = { param($Worktree, $Commands) @() } }
    if (-not $UpdateBranch) { $UpdateBranch = { param($Repository, $Number, $Base) [pscustomobject]@{ updated = $true; conflict = $false } } }
    if (-not $MergePr) { $MergePr = { param($Repository, $Number, $Method, $HeadSha, $AllowAdmin) [pscustomobject]@{ state = 'MERGED'; mergeCommit = 'm1'; mergedAt = 't' } } }
    if (-not $VerifyPostMerge) { $VerifyPostMerge = { param($Repository, $Branch, $Commands) [pscustomobject]@{ baseSha = 'base-sha'; result = 'pass'; at = 't' } } }
    if (-not $WriteSummary) { $WriteSummary = { param($Text) } }
    if (-not $GetNow) { $GetNow = { '2026-09-18T14:22:00Z' } }
    if (-not $GetDefaultHead) { $GetDefaultHead = { param($Repository, $Branch) 'base-sha' } }
    if (-not $IsCancelled) { $IsCancelled = { $false } }
    if (-not $Sleep) { $Sleep = { param($Seconds) } }
    if (-not $Log) { $Log = { param($Message) } }

    return [pscustomobject]@{
        Collect = $Collect; AcquireLock = $AcquireLock; ReleaseLock = $ReleaseLock
        FetchDefault = $FetchDefault; EnsureWorktree = $EnsureWorktree; ReadAttempt = $ReadAttempt
        UpsertAttempt = $UpsertAttempt; DispatchWorker = $DispatchWorker; GetPr = $GetPr
        RunLocalChecks = $RunLocalChecks; UpdateBranch = $UpdateBranch; MergePr = $MergePr
        VerifyPostMerge = $VerifyPostMerge; WriteSummary = $WriteSummary; GetNow = $GetNow
        GetDefaultHead = $GetDefaultHead; IsCancelled = $IsCancelled; Sleep = $Sleep; Log = $Log
    }
}

function New-SnapshotFromIssues {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Policy, [AllowEmptyCollection()] [object[]]$Issues = @())
    $gh = New-GhFake -GetSubIssues ({ param($Repository, $Epic) $Issues }.GetNewClosure())
    return (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $Policy -Gh $gh).Snapshot
}
