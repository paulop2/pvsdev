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
