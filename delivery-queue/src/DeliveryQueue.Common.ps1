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

function ConvertTo-CommandLineArgument {
    [CmdletBinding()]
    param([AllowNull()] [string]$Value)

    $text = [string]$Value
    if ($text -match '[\s"]') {
        $escaped = $text -replace '\\', '\\\\' -replace '"', '\"'
        return '"' + $escaped + '"'
    }
    return $text
}

function Invoke-Process {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [AllowEmptyCollection()] [string[]]$Arguments = @(),
        [AllowNull()] [string]$WorkingDirectory,
        [int]$TimeoutSeconds = 0
    )

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = (@($Arguments | ForEach-Object { ConvertTo-CommandLineArgument -Value $_ }) -join ' ')
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { $info.WorkingDirectory = $WorkingDirectory }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $process.Start() | Out-Null
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()

    $timedOut = $false
    if ($TimeoutSeconds -gt 0) {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            & taskkill /PID $process.Id /T /F 2>&1 | Out-Null
            $process.WaitForExit()
        }
    }
    else {
        $process.WaitForExit()
    }

    $output = ($stdout.Result + $stderr.Result)
    return [pscustomobject]@{ exitCode = $process.ExitCode; timedOut = $timedOut; output = $output }
}

function Invoke-VerifyCommands {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [string[]]$Commands = @(),
        [AllowEmptyCollection()] [string[]]$SetupCommands = @(),
        [Parameter(Mandatory)] [string]$WorkingDirectory,
        [int]$Retries = 0,
        [scriptblock]$InvokeProcess = $null,
        [scriptblock]$Sleep = $null
    )

    if ($Retries -lt 0) { $Retries = 0 }
    if (-not $InvokeProcess) {
        $InvokeProcess = { param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds) Invoke-Process -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds }.GetNewClosure()
    }
    if (-not $Sleep) {
        $Sleep = { param($Seconds) Start-Sleep -Seconds $Seconds }.GetNewClosure()
    }

    foreach ($command in @(@($SetupCommands) + @($Commands))) {
        $run = $null
        for ($attempt = 0; $attempt -le $Retries; $attempt++) {
            if ($attempt -gt 0) { & $Sleep 3 }
            $run = & $InvokeProcess -FilePath 'cmd.exe' -Arguments @('/d', '/s', '/c', $command) -WorkingDirectory $WorkingDirectory -TimeoutSeconds 0
            if ($run.exitCode -eq 0) { break }
        }
        if ($null -eq $run -or $run.exitCode -ne 0) { return 'fail' }
    }
    return 'pass'
}
