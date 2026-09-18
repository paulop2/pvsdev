[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [int]$Epic,
    [Parameter(Mandatory)] [string]$Repository,
    [int]$MaxIssues = 0,
    [AllowEmptyCollection()] [int[]]$Only = @(),
    [switch]$Retry,
    [int]$WorkerTimeoutMinutes = 0,
    [switch]$WhatIf,
    [string]$PolicyPath = '.delivery-queue/policy.json',
    [AllowNull()] [object]$Io = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Pages.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Attempt.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Common.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.DriverCore.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Driver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Gh.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Io.ps1')

if ($Epic -lt 1) {
    [Console]::Error.WriteLine('epic deve ser um inteiro positivo')
    exit 4
}

$loaded = Read-DeliveryQueuePolicy -Path $PolicyPath
if (-not $loaded.Ok) {
    [Console]::Error.WriteLine(($loaded.Messages -join '; '))
    exit 4
}

if ($Repository -notmatch '^[^/]+/[^/]+$') {
    [Console]::Error.WriteLine("repository invalido: $Repository")
    exit 4
}

if ($MaxIssues -lt 0 -or $WorkerTimeoutMinutes -lt 0) {
    [Console]::Error.WriteLine('MaxIssues e WorkerTimeoutMinutes devem ser nao negativos')
    exit 4
}

$timeout = $WorkerTimeoutMinutes
if ($timeout -eq 0) { $timeout = [int](Get-Prop -Object $loaded.Policy -Name 'workerTimeoutMinutes' -Default 60) }

$options = [pscustomobject]@{
    Repository = $Repository
    Epic = $Epic
    MaxIssues = $(if ($MaxIssues -gt 0) { $MaxIssues } else { $null })
    HasLimit = ($MaxIssues -gt 0)
    Only = $Only
    Retry = [bool]$Retry
    WorkerTimeoutMinutes = $timeout
    WhatIf = [bool]$WhatIf
}

$driverIo = $Io
if ($null -eq $driverIo) { $driverIo = New-DeliveryQueueIoAdapter -Policy $loaded.Policy }

$summary = Invoke-DeliveryLoop -Policy $loaded.Policy -Options $options -Io $driverIo
exit (Get-DeliveryExitCode -Summary $summary)
