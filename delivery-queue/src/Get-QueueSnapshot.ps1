[CmdletBinding()]
param(
    [Parameter(Mandatory)] [int]$Epic,
    [Parameter(Mandatory)] [string]$Repository,
    [string]$PolicyPath = '.delivery-queue/policy.json',
    [AllowEmptyCollection()] [int[]]$Only = @(),
    [string]$OutputPath,
    [AllowNull()] [object]$GhAdapter = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Pages.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Attempt.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Common.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Gh.ps1')

$loaded = Read-DeliveryQueuePolicy -Path $PolicyPath
if (-not $loaded.Ok) {
    [Console]::Error.WriteLine(($loaded.Messages -join '; '))
    exit 4
}

if ($Repository -notmatch '^[^/]+/[^/]+$') {
    [Console]::Error.WriteLine("repository invalido: $Repository")
    exit 4
}

$gh = $GhAdapter
if ($null -eq $gh) { $gh = New-DeliveryQueueGhAdapter }

$filter = [pscustomobject]@{ only = $Only }
$result = New-QueueSnapshot -Repository $Repository -Epic $Epic -Policy $loaded.Policy -Gh $gh -Filter $filter

if (-not $result.Ok) {
    [Console]::Error.WriteLine(($result.Error.Messages -join '; '))
    exit 4
}

$json = $result.Snapshot | ConvertTo-Json -Depth 30
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $json
}
else {
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
}

exit 0
