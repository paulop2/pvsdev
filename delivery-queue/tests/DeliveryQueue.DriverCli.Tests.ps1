Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Pages.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Attempt.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Common.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Collector.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.DriverCore.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Driver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Gh.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Io.ps1"
    . "$PSScriptRoot/TestHelpers.ps1"

    function Write-PolicyFile {
        param([object]$Policy)
        $path = Join-Path $TestDrive 'policy.json'
        ($Policy | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $path -Encoding UTF8
        return $path
    }
}

Describe 'ConvertTo-CommandLineArgument' {
    It 'nao cita argumento simples' {
        ConvertTo-CommandLineArgument -Value '--auto' | Should -Be '--auto'
    }
    It 'cita argumento com espaco' {
        ConvertTo-CommandLineArgument -Value 'a b' | Should -Be '"a b"'
    }
    It 'escapa aspas para preservar JSON no comando nativo' {
        ConvertTo-CommandLineArgument -Value '{"a":"b"}' | Should -Be '"{\"a\":\"b\"}"'
    }
}

Describe 'Deliver-Queue.ps1 (CLI)' {
    It 'retorna 4 quando a politica esta ausente' {
        & "$PSScriptRoot/../src/Deliver-Queue.ps1" 9 -Repository 'o/r' -PolicyPath (Join-Path $TestDrive 'nao-existe.json') | Out-Null
        $LASTEXITCODE | Should -Be 4
    }

    It 'retorna 0 sem trabalho quando a fila esta vazia' {
        $policyPath = Write-PolicyFile -Policy (New-TestPolicy)
        $empty = (New-SnapshotFromIssues -Policy (New-TestPolicy) -Issues @())
        $io = New-IoFake -Collect ({ param($Repository, $Epic, $Only) $empty }.GetNewClosure())
        & "$PSScriptRoot/../src/Deliver-Queue.ps1" 9 -Repository 'o/r' -PolicyPath $policyPath -Io $io | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'WhatIf nao adquire lock nem despacha' {
        $policy = New-TestPolicy
        $policyPath = Write-PolicyFile -Policy $policy
        $snapshot = (New-SnapshotFromIssues -Policy $policy -Issues @([pscustomobject]@{ number = 1; nodeId = 'n1'; title = 'A'; state = 'OPEN'; stateReason = $null; labels = @(); blockedBy = @() }))
        $lockCount = [ref]0; $dispatchCount = [ref]0
        $io = New-IoFake `
            -Collect ({ param($Repository, $Epic, $Only) $snapshot }.GetNewClosure()) `
            -AcquireLock ({ param($Repository) $lockCount.Value++; [pscustomobject]@{ Acquired = $true; Path = 'l'; Stream = $null; Repository = $Repository } }.GetNewClosure()) `
            -DispatchWorker ({ param($Issue, $Repository, $Base, $Worktree, $TimeoutMinutes) $dispatchCount.Value++; [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' } }.GetNewClosure())
        & "$PSScriptRoot/../src/Deliver-Queue.ps1" 9 -Repository 'o/r' -PolicyPath $policyPath -WhatIf -Io $io | Out-Null
        $LASTEXITCODE | Should -Be 0
        $lockCount.Value | Should -Be 0
        $dispatchCount.Value | Should -Be 0
    }
}
