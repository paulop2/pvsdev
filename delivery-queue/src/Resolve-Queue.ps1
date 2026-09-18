[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$SnapshotPath,
    [AllowEmptyCollection()] [int[]]$Attempted = @(),
    [switch]$Retry
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')

if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) {
    [Console]::Error.WriteLine("snapshot nao encontrado: $SnapshotPath")
    exit 4
}

try {
    $snapshot = Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    [Console]::Error.WriteLine("snapshot invalido: $($_.Exception.Message)")
    exit 4
}

$plan = Resolve-QueuePlan -Snapshot $snapshot -Attempted $Attempted -Retry:$Retry
$plan | ConvertTo-Json -Depth 20

if ($null -eq $plan.Error) { exit 0 }
if ($plan.Error.Code -eq 'policy_invalid') { exit 2 }
if ($plan.Error.Code -eq 'policy_conflict') { exit 2 }
if ($plan.Error.Code -eq 'dependency_cycle') { exit 3 }
exit 4
