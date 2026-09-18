Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')

function Read-DeliveryQueuePolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            Ok = $false; Code = 'policy_missing'
            Messages = @("policy ausente: $Path"); Policy = $null
        }
    }

    try {
        $policy = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            Ok = $false; Code = 'policy_invalid'
            Messages = @("policy invalida: $($_.Exception.Message)"); Policy = $null
        }
    }

    $problems = Test-DeliveryQueuePolicy -Policy $policy
    if ($problems.Count -gt 0) {
        $code = 'policy_invalid'
        foreach ($problem in $problems) {
            if ($problem -match '^policy_conflict:') { $code = 'policy_conflict' }
        }
        return [pscustomobject]@{ Ok = $false; Code = $code; Messages = $problems; Policy = $policy }
    }

    return [pscustomobject]@{ Ok = $true; Code = $null; Messages = @(); Policy = $policy }
}
