Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')

function Get-QueueLockPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [string]$Root = $env:TEMP
    )

    $slug = ($Repository -replace '[^A-Za-z0-9._-]', '_')
    return (Join-Path $Root "delivery-queue-$slug.lock")
}

function Enter-QueueLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [string]$Root = $env:TEMP
    )

    $path = Get-QueueLockPath -Repository $Repository -Root $Root
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $path,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
    }
    catch [System.IO.IOException] {
        return [pscustomobject]@{ Acquired = $false; Path = $path; Stream = $null; Repository = $Repository }
    }

    return [pscustomobject]@{ Acquired = $true; Path = $path; Stream = $stream; Repository = $Repository }
}

function Exit-QueueLock {
    [CmdletBinding()]
    param([AllowNull()] [object]$Lock)

    if ($null -eq $Lock) { return }

    $stream = Get-Prop -Object $Lock -Name 'Stream'
    if ($null -ne $stream) { $stream.Dispose() }

    $path = [string](Get-Prop -Object $Lock -Name 'Path')
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}
