Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')

function ConvertTo-AttemptComment {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Record)

    $json = $Record | ConvertTo-Json -Depth 20
    return "<!-- delivery-queue-attempt:v1`n$json`n-->"
}

function ConvertFrom-AttemptComment {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string]$Body)

    if ([string]::IsNullOrWhiteSpace($Body)) { return $null }

    $pattern = '(?s)<!--\s*delivery-queue-attempt:v1\s*(\{.*?\})\s*-->'
    $match = [regex]::Match($Body, $pattern)
    if (-not $match.Success) { return $null }

    try {
        return ($match.Groups[1].Value | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Select-LatestAttempt {
    [CmdletBinding()]
    param([AllowEmptyCollection()] [string[]]$Comments = @())

    $latest = $null
    $latestStamp = $null

    foreach ($body in @($Comments)) {
        $record = ConvertFrom-AttemptComment -Body $body
        if ($null -eq $record) { continue }

        $stamp = [string](Get-Prop -Object $record -Name 'updatedAt')
        if ($null -eq $latest) {
            $latest = $record
            $latestStamp = $stamp
            continue
        }
        if ($stamp -gt $latestStamp) {
            $latest = $record
            $latestStamp = $stamp
        }
    }

    return $latest
}

function New-AttemptRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$AttemptId,
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [int]$Epic,
        [Parameter(Mandatory)] [int]$Issue,
        [AllowNull()] [string]$Branch,
        [AllowNull()] [string]$Base,
        [AllowNull()] [string]$BaseSha,
        [Parameter(Mandatory)] [string]$Now
    )

    return [pscustomobject]@{
        attemptId = $AttemptId
        repository = $Repository
        epic = $Epic
        issue = $Issue
        branch = $Branch
        pr = $null
        base = $Base
        baseSha = $BaseSha
        headSha = $null
        status = 'started'
        reason = $null
        checks = @()
        review = $null
        merge = $null
        postMerge = $null
        nextAction = $null
        updatedAt = $Now
    }
}
