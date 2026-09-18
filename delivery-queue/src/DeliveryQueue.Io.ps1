Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Attempt.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Lock.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Gh.ps1')

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

function Invoke-GitIn {
    [CmdletBinding()]
    param([string]$WorkingDirectory, [Parameter(Mandatory)] [string[]]$Arguments)

    $result = Invoke-Process -FilePath 'git' -Arguments $Arguments -WorkingDirectory $WorkingDirectory
    if ($result.exitCode -ne 0) {
        throw "git $($Arguments -join ' ') falhou: $($result.output)"
    }
    return $result.output
}

function New-DeliveryQueueIoAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Policy,
        [scriptblock]$InvokeProcess
    )

    $getProp = Get-Command -Name Get-Prop -CommandType Function
    $newGh = Get-Command -Name New-DeliveryQueueGhAdapter -CommandType Function
    $newSnapshot = Get-Command -Name New-QueueSnapshot -CommandType Function
    $selectLatest = Get-Command -Name Select-LatestAttempt -CommandType Function
    $toAttempt = Get-Command -Name ConvertTo-AttemptComment -CommandType Function
    $fromAttempt = Get-Command -Name ConvertFrom-AttemptComment -CommandType Function
    $invokeGhJson = Get-Command -Name Invoke-GhJson -CommandType Function
    $testChecks = Get-Command -Name Test-RemoteChecksComplete -CommandType Function
    $enterLock = Get-Command -Name Enter-QueueLock -CommandType Function
    $exitLock = Get-Command -Name Exit-QueueLock -CommandType Function
    $invokeGitIn = Get-Command -Name Invoke-GitIn -CommandType Function
    $invokeProcessFn = Get-Command -Name Invoke-Process -CommandType Function

    if (-not $InvokeProcess) {
        $InvokeProcess = { param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds) & $invokeProcessFn -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds }.GetNewClosure()
    }

    $adapter = [pscustomobject]@{}
    $adapter | Add-Member NoteProperty GetNow ({ [datetimeoffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }.GetNewClosure())
    $adapter | Add-Member NoteProperty Log ({ param($Message) [Console]::Error.WriteLine($Message) }.GetNewClosure())
    $adapter | Add-Member NoteProperty Sleep ({ param($Seconds) Start-Sleep -Seconds $Seconds }.GetNewClosure())
    $adapter | Add-Member NoteProperty IsCancelled ({ $false }.GetNewClosure())

    $adapter | Add-Member NoteProperty Collect ({
        param($Repository, $Epic, $Only)
        $gh = & $newGh
        $filter = [pscustomobject]@{ only = $Only }
        return (& $newSnapshot -Repository $Repository -Epic $Epic -Policy $Policy -Gh $gh -Filter $filter)
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty AcquireLock ({ param($Repository) & $enterLock -Repository $Repository }.GetNewClosure())
    $adapter | Add-Member NoteProperty ReleaseLock ({ param($Lock) & $exitLock -Lock $Lock }.GetNewClosure())

    $adapter | Add-Member NoteProperty FetchDefault ({
        param($Repository, $Branch)
        & $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('fetch', 'origin', $Branch) | Out-Null
        return (& $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('rev-parse', "origin/$Branch")).Trim()
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty GetDefaultHead ({
        param($Repository, $Branch)
        & $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('fetch', 'origin', $Branch) | Out-Null
        return (& $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('rev-parse', "origin/$Branch")).Trim()
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty EnsureWorktree ({
        param($Repository, $Branch, $Base, $Root)
        $path = Join-Path $Root ($Branch -replace '[^A-Za-z0-9._-]', '_')
        $existing = (& $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('worktree', 'list', '--porcelain'))
        if ($existing -match [regex]::Escape("branch refs/heads/$Branch")) {
            return [pscustomobject]@{ path = $path; branch = $Branch }
        }
        & $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('worktree', 'add', $path, '-b', $Branch, "origin/$Base") | Out-Null
        return [pscustomobject]@{ path = $path; branch = $Branch }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty ReadAttempt ({
        param($Repository, $Issue)
        $data = & $invokeGhJson -Arguments @('issue', 'view', [string]$Issue, '--repo', $Repository, '--json', 'comments')
        $bodies = @()
        foreach ($comment in @($data.comments)) { $bodies += [string]$comment.body }
        return (& $selectLatest -Comments $bodies)
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty UpsertAttempt ({
        param($Repository, $Issue, $Record)
        $body = & $toAttempt -Record $Record
        $data = & $invokeGhJson -Arguments @('issue', 'view', [string]$Issue, '--repo', $Repository, '--json', 'comments')
        $targetId = $null
        foreach ($comment in @($data.comments)) {
            $commentId = & $getProp -Object $comment -Name 'id'
            if ($null -eq $commentId) { continue }
            $parsed = & $fromAttempt -Body ([string]$comment.body)
            if ($parsed -and ([string](& $getProp -Object $parsed -Name 'attemptId')) -eq [string](& $getProp -Object $Record -Name 'attemptId')) {
                $targetId = $commentId
                break
            }
        }
        if ($null -ne $targetId) {
            & $invokeGhJson -Arguments @('api', '-X', 'PATCH', "repos/$Repository/issues/comments/$targetId", '-f', "body=$body") | Out-Null
            return [string]$targetId
        }
        $created = & $invokeGhJson -Arguments @('api', "repos/$Repository/issues/$Issue/comments", '-f', "body=$body")
        return [string](& $getProp -Object $created -Name 'id')
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty DispatchWorker ({
        param($Issue, $Repository, $Base, $Worktree, $TimeoutMinutes)
        $prompt = "$Issue --repo $Repository --base $Base"
        $arguments = @('run', '--auto', '--command', 'delivery-queue-deliver-issue', '--format', 'json', $prompt)
        $result = & $InvokeProcess -FilePath 'opencode' -Arguments $arguments -WorkingDirectory $Worktree -TimeoutSeconds ($TimeoutMinutes * 60)
        return [pscustomobject]@{ exitCode = $result.exitCode; timedOut = $result.timedOut; output = $result.output }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty GetPr ({
        param($Repository, $Number)
        $json = 'number,state,isDraft,baseRefName,headRefName,headRefOid,url,mergeable,statusCheckRollup'
        $pr = & $invokeGhJson -Arguments @('pr', 'view', [string]$Number, '--repo', $Repository, '--json', $json)
        $checks = @()
        $known = $null -ne (& $getProp -Object $pr -Name 'statusCheckRollup')
        foreach ($entry in @(& $getProp -Object $pr -Name 'statusCheckRollup')) {
            $context = [string](& $getProp -Object $entry -Name 'name')
            if ([string]::IsNullOrWhiteSpace($context)) { $context = [string](& $getProp -Object $entry -Name 'context') }
            $conclusion = [string](& $getProp -Object $entry -Name 'conclusion')
            if ([string]::IsNullOrWhiteSpace($conclusion)) { $conclusion = [string](& $getProp -Object $entry -Name 'state') }
            $checks += [pscustomobject]@{ context = $context; conclusion = $conclusion }
        }
        $complete = & $testChecks -Checks $checks -ChecksKnown $known -Policy $Policy
        return [pscustomobject]@{
            number = [int](& $getProp -Object $pr -Name 'number'); state = [string](& $getProp -Object $pr -Name 'state')
            isDraft = [bool](& $getProp -Object $pr -Name 'isDraft' -Default $false)
            hasConflict = ([string](& $getProp -Object $pr -Name 'mergeable') -eq 'CONFLICTING')
            checksComplete = $complete; headSha = [string](& $getProp -Object $pr -Name 'headRefOid')
            url = [string](& $getProp -Object $pr -Name 'url'); baseRefName = [string](& $getProp -Object $pr -Name 'baseRefName')
            headRefName = [string](& $getProp -Object $pr -Name 'headRefName')
        }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty RunLocalChecks ({
        param($Worktree, $Commands)
        $head = (& $invokeGitIn -WorkingDirectory $Worktree -Arguments @('rev-parse', 'HEAD')).Trim()
        $evidence = @()
        foreach ($command in @($Commands)) {
            $result = & $InvokeProcess -FilePath 'cmd.exe' -Arguments @('/d', '/s', '/c', $command) -WorkingDirectory $Worktree -TimeoutSeconds 0
            $evidence += [pscustomobject]@{ command = [string]$command; result = $(if ($result.exitCode -eq 0) { 'pass' } else { 'fail' }); headSha = $head; at = [datetimeoffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
        }
        return ,$evidence
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty UpdateBranch ({
        param($Repository, $Number, $Base)
        & $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('fetch', 'origin', $Base) | Out-Null
        $pr = & $invokeGhJson -Arguments @('pr', 'view', [string]$Number, '--repo', $Repository, '--json', 'headRefName')
        $headBranch = [string](& $getProp -Object $pr -Name 'headRefName')
        $porcelain = & $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('worktree', 'list', '--porcelain')
        $worktreePath = $null
        $currentPath = $null
        foreach ($line in @($porcelain -split "`r?`n")) {
            if ($line -match '^worktree (?<path>.+)$') { $currentPath = $Matches['path']; continue }
            if ($line -match '^branch refs/heads/(?<name>.+)$' -and $Matches['name'] -eq $headBranch) { $worktreePath = $currentPath }
        }
        if ([string]::IsNullOrWhiteSpace([string]$worktreePath)) {
            return [pscustomobject]@{ updated = $false; conflict = $false; reason = 'worktree_ausente' }
        }
        $result = & $InvokeProcess -FilePath 'git' -Arguments @('merge', "origin/$Base", '--no-edit') -WorkingDirectory $worktreePath -TimeoutSeconds 0
        return [pscustomobject]@{ updated = ($result.exitCode -eq 0); conflict = ($result.exitCode -ne 0) }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty MergePr ({
        param($Repository, $Number, $Method, $HeadSha, $AllowAdmin)
        $arguments = @('pr', 'merge', [string]$Number, '--repo', $Repository, "--$Method", '--match-head-commit', $HeadSha)
        if ($AllowAdmin) { $arguments += '--admin' }
        $result = & $InvokeProcess -FilePath 'gh' -Arguments $arguments -TimeoutSeconds 300
        if ($result.exitCode -ne 0) { throw "gh pr merge falhou: $($result.output)" }
        $view = & $invokeGhJson -Arguments @('pr', 'view', [string]$Number, '--repo', $Repository, '--json', 'state,mergeCommit,mergedAt')
        return [pscustomobject]@{
            state = [string](& $getProp -Object $view -Name 'state')
            mergeCommit = [string](& $getProp -Object (& $getProp -Object $view -Name 'mergeCommit') -Name 'oid')
            mergedAt = [string](& $getProp -Object $view -Name 'mergedAt')
        }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty VerifyPostMerge ({
        param($Repository, $Branch, $Commands)
        & $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('fetch', 'origin', $Branch) | Out-Null
        $baseSha = (& $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('rev-parse', "origin/$Branch")).Trim()
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("dq-verify-" + [Guid]::NewGuid().ToString('N'))
        & $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('worktree', 'add', '--detach', $temp, "origin/$Branch") | Out-Null
        $result = 'pass'
        try {
            foreach ($command in @($Commands)) {
                $run = & $InvokeProcess -FilePath 'cmd.exe' -Arguments @('/d', '/s', '/c', $command) -WorkingDirectory $temp -TimeoutSeconds 0
                if ($run.exitCode -ne 0) { $result = 'fail'; break }
            }
        }
        finally {
            & $invokeGitIn -WorkingDirectory (Get-Location).Path -Arguments @('worktree', 'remove', '--force', $temp) | Out-Null
        }
        return [pscustomobject]@{ baseSha = $baseSha; result = $result; at = [datetimeoffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }.GetNewClosure())

    $adapter | Add-Member NoteProperty WriteSummary ({ param($Text) [Console]::Out.WriteLine($Text) }.GetNewClosure())

    return $adapter
}
