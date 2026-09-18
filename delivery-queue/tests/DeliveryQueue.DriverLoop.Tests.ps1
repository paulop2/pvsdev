Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Pages.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Attempt.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Collector.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.DriverCore.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Driver.ps1"
    . "$PSScriptRoot/TestHelpers.ps1"

    function New-Options {
        param($Policy, [int]$MaxIssues = 0, [int[]]$Only = @(), [bool]$Retry = $false, [bool]$WhatIf = $false)
        [pscustomobject]@{
            Repository = 'o/r'; Epic = 9; MaxIssues = $(if ($MaxIssues -gt 0) { $MaxIssues } else { $null })
            HasLimit = ($MaxIssues -gt 0); Only = $Only; Retry = $Retry
            WorkerTimeoutMinutes = 60; WhatIf = $WhatIf
        }
    }
    function New-Snapshot {
        param($Policy, [object[]]$Issues)
        $gh = New-GhFake -GetSubIssues ({ param($Repository, $Epic) $Issues }.GetNewClosure())
        return (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $Policy -Gh $gh).Snapshot
    }
    function New-Issue {
        param([int]$Number, [string]$State = 'OPEN', [object[]]$BlockedBy = @(), [object]$Pr = $null)
        [pscustomobject]@{ number = $Number; nodeId = "n$Number"; title = "Issue $Number"; state = $State; stateReason = $(if ($State -eq 'CLOSED') { 'COMPLETED' } else { $null }); labels = @(); blockedBy = $BlockedBy }
    }
}

Describe 'Invoke-DeliveryLoop' {
    It 'despacha a primeira issue e registra a tentativa' {
        $policy = New-TestPolicy
        $snapshots = New-Object System.Collections.Queue
        $snapshots.Enqueue((New-Snapshot -Policy $policy -Issues @((New-Issue -Number 1), (New-Issue -Number 2 -BlockedBy @('o/r#1')))))
        $snapshots.Enqueue((New-Snapshot -Policy $policy -Issues @((New-Issue -Number 1 -State 'CLOSED'))))
        $dispatchCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $snapshots.Dequeue() }.GetNewClosure()) `
            -DispatchWorker ({ param($Issue, $Repository, $Base, $Worktree, $TimeoutMinutes) $dispatchCount.Value++; [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' } }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io

        $dispatchCount.Value | Should -Be 1
        $summary.Failed | Should -Be 0
    }

    It 'respeita o teto -MaxIssues' {
        $policy = New-TestPolicy
        $snapshots = New-Object System.Collections.Queue
        $snapshots.Enqueue((New-Snapshot -Policy $policy -Issues @((New-Issue -Number 1), (New-Issue -Number 2))))
        $snapshots.Enqueue((New-Snapshot -Policy $policy -Issues @((New-Issue -Number 1), (New-Issue -Number 2))))
        $io = New-IoFake -Collect ({ param($Repository, $Epic, $Only) $snapshots.Dequeue() }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy -MaxIssues 1) -Io $io
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 1
    }

    It 'nao mergeia em modo humano e aguarda merge' {
        $policy = New-TestPolicy
        $pr = [pscustomobject]@{ number = 7; url = 'u'; state = 'OPEN'; isDraft = $false; baseRefName = 'master'; headRefName = 'feat/1'; headSha = 'h1'; hasConflict = $false; checks = @(); checksKnown = $true }
        $gh = New-GhFake -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() }) } -GetIssuePrs ({ param($Repository, $Issue) @($pr) }.GetNewClosure())
        $snapshot = (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $policy -Gh $gh).Snapshot
        $snapshots = New-Object System.Collections.Queue
        $snapshots.Enqueue($snapshot)
        $mergeCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $snapshots.Dequeue() }.GetNewClosure()) `
            -MergePr ({ param($Repository, $Number, $Method, $HeadSha, $AllowAdmin) $mergeCount.Value++; [pscustomobject]@{ state = 'MERGED'; mergeCommit = 'm1'; mergedAt = 't' } }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io
        $mergeCount.Value | Should -Be 0
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 2
    }

    It 'mergeia em modo auto com gate verde e roda pos-merge' {
        $policy = New-TestPolicy -MergeMode 'auto' -Verify $true
        $pr = [pscustomobject]@{ number = 7; url = 'u'; state = 'OPEN'; isDraft = $false; baseRefName = 'master'; headRefName = 'feat/1'; headSha = 'h1'; hasConflict = $false; checks = @(); checksKnown = $true }
        $record = [pscustomobject]@{
            attemptId = 'a1'; repository = 'o/r'; epic = 9; issue = 1; branch = 'feat/1-x'; status = 'delivered'
            review = [pscustomobject]@{ iterations = 1; blocking = 0; headSha = 'h1' }
            checks = @([pscustomobject]@{ command = 'npm run build'; result = 'pass'; headSha = 'h1'; at = 't' })
            pr = 7; headSha = 'h1'
        }
        $open = (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $policy -Gh (New-GhFake -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() }) } -GetIssuePrs ({ param($Repository, $Issue) @($pr) }.GetNewClosure()))).Snapshot
        $done = (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $policy -Gh (New-GhFake -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'CLOSED'; stateReason = 'COMPLETED'; labels = @(); blockedBy = @() }) })).Snapshot
        $snapshots = New-Object System.Collections.Queue
        $snapshots.Enqueue($open); $snapshots.Enqueue($done)
        $mergeCount = [ref]0; $verifyCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $snapshots.Dequeue() }.GetNewClosure()) `
            -ReadAttempt ({ param($Repository, $Issue) $record }.GetNewClosure()) `
            -MergePr ({ param($Repository, $Number, $Method, $HeadSha, $AllowAdmin) $mergeCount.Value++; [pscustomobject]@{ state = 'MERGED'; mergeCommit = 'm1'; mergedAt = 't' } }.GetNewClosure()) `
            -VerifyPostMerge ({ param($Repository, $Branch, $Commands) $verifyCount.Value++; [pscustomobject]@{ baseSha = 'base-sha'; result = 'pass'; at = 't' } }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io
        $mergeCount.Value | Should -Be 1
        $verifyCount.Value | Should -Be 1
        $summary.Failed | Should -Be 0
    }

    It 'lock ocupado encerra como infra sem coletar' {
        $policy = New-TestPolicy
        $collectCount = [ref]0
        $io = New-IoFake `
            -AcquireLock { param($Repository) [pscustomobject]@{ Acquired = $false; Path = 'lock'; Stream = $null; Repository = $Repository } } `
            -Collect ({ param($Repository, $Epic, $Only) $collectCount.Value++; throw 'nao deveria coletar' }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io
        $collectCount.Value | Should -Be 0
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 4
    }

    It 'cancelamento encerra sem despachar' {
        $policy = New-TestPolicy
        $snapshots = New-Object System.Collections.Queue
        $snapshots.Enqueue((New-Snapshot -Policy $policy -Issues @((New-Issue -Number 1))))
        $dispatchCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $snapshots.Dequeue() }.GetNewClosure()) `
            -IsCancelled { $true } `
            -DispatchWorker ({ param($Issue, $Repository, $Base, $Worktree, $TimeoutMinutes) $dispatchCount.Value++; [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' } }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io
        $dispatchCount.Value | Should -Be 0
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 130
    }

    It 'falha de coleta persistente encerra como infra em no maximo tres tentativas' {
        $policy = New-TestPolicy
        $collectCount = [ref]0
        $io = New-IoFake -Collect ({ param($Repository, $Epic, $Only) $collectCount.Value++; throw 'api fora' }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io
        $collectCount.Value | Should -Be 3
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 4
    }

    It 'encerra apos duas coletas quando acao nao-dispatch nao progridue' {
        $policy = New-TestPolicy -MergeMode 'auto'
        $pr = [pscustomobject]@{ number = 7; url = 'u'; state = 'OPEN'; isDraft = $false; baseRefName = 'master'; headRefName = 'feat/1'; headSha = 'h1'; hasConflict = $false; checks = @(); checksKnown = $true }
        $record = [pscustomobject]@{
            attemptId = 'a1'; repository = 'o/r'; epic = 9; issue = 1; branch = 'feat/1-x'
            status = 'delivered'; updatedAt = '2026-09-18T14:22:00Z'
            merge = [pscustomobject]@{ mergeCommit = 'deadbeef' }
        }
        $comment = ConvertTo-AttemptComment -Record $record
        $gh = New-GhFake `
            -GetSubIssues { param($Repository, $Epic) @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() }) } `
            -GetIssueComments ({ param($Repository, $Issue) @($comment) }.GetNewClosure()) `
            -GetIssuePrs ({ param($Repository, $Issue) @($pr) }.GetNewClosure())
        $snapshot = (New-QueueSnapshot -Repository 'o/r' -Epic 9 -Policy $policy -Gh $gh).Snapshot
        $collectCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $collectCount.Value++; $snapshot }.GetNewClosure()) `
            -ReadAttempt ({ param($Repository, $Issue) $record }.GetNewClosure())

        $summary = Invoke-DeliveryLoop -Policy $policy -Options (New-Options -Policy $policy) -Io $io

        $collectCount.Value | Should -Be 2
        (Get-DeliveryExitCode -Summary $summary) | Should -Be 2
    }
}
