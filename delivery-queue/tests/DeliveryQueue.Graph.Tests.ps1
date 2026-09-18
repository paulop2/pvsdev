Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"

    function New-TestNode {
        param(
            [int]$Number,
            [string[]]$BlockedBy = @(),
            [bool]$InScope = $true
        )
        [pscustomobject]@{
            id        = "o/r#$Number"
            number    = $Number
            state     = 'OPEN'
            inScope   = $InScope
            blockedBy = $BlockedBy
        }
    }

    function New-TestSnapshot {
        param([object[]]$Issues)
        [pscustomobject]@{ repository = 'o/r'; epic = [pscustomobject]@{ number = 9 }; issues = $Issues }
    }
}

Describe 'New-IssueId' {
    It 'compõe owner/repo#numero' {
        New-IssueId -Repository 'paulop2/pvsdev' -Number 42 | Should -Be 'paulop2/pvsdev#42'
    }
}

Describe 'Get-NodeIndex' {
    It 'indexa por id' {
        $snapshot = New-TestSnapshot -Issues @((New-TestNode -Number 1), (New-TestNode -Number 2))
        (Get-NodeIndex -Snapshot $snapshot).Count | Should -Be 2
    }

    It 'compõe id quando o nó não traz o campo id' {
        $node = [pscustomobject]@{ number = 7; inScope = $true; blockedBy = @() }
        $index = Get-NodeIndex -Snapshot (New-TestSnapshot -Issues @($node))
        $index.ContainsKey('o/r#7') | Should -BeTrue
    }
}

Describe 'Get-TopologicalOrder' {
    It 'ordena cadeia linear pela dependência' {
        $snapshot = New-TestSnapshot -Issues @(
            (New-TestNode -Number 3 -BlockedBy @('o/r#2')),
            (New-TestNode -Number 2 -BlockedBy @('o/r#1')),
            (New-TestNode -Number 1)
        )
        (Get-TopologicalOrder -Snapshot $snapshot).Order | Should -Be @('o/r#1', 'o/r#2', 'o/r#3')
    }

    It 'desempata por numero da issue' {
        $snapshot = New-TestSnapshot -Issues @((New-TestNode -Number 10), (New-TestNode -Number 2))
        (Get-TopologicalOrder -Snapshot $snapshot).Order | Should -Be @('o/r#2', 'o/r#10')
    }

    It 'ignora blocker fora do escopo na ordenação' {
        $snapshot = New-TestSnapshot -Issues @(
            (New-TestNode -Number 4 -BlockedBy @('o/r#99')),
            (New-TestNode -Number 99 -InScope $false)
        )
        (Get-TopologicalOrder -Snapshot $snapshot).Order | Should -Be @('o/r#4')
    }

    It 'ignora blocker ausente do índice sem quebrar' {
        $snapshot = New-TestSnapshot -Issues @((New-TestNode -Number 5 -BlockedBy @('o/r#404')))
        (Get-TopologicalOrder -Snapshot $snapshot).Order | Should -Be @('o/r#5')
    }

    It 'detecta ciclo e não o emite na ordem' {
        $snapshot = New-TestSnapshot -Issues @(
            (New-TestNode -Number 6 -BlockedBy @('o/r#7')),
            (New-TestNode -Number 7 -BlockedBy @('o/r#6')),
            (New-TestNode -Number 8)
        )
        $result = Get-TopologicalOrder -Snapshot $snapshot
        $result.Order | Should -Be @('o/r#8')
        $result.Cycle | Should -Contain 'o/r#6'
        $result.Cycle | Should -Contain 'o/r#7'
    }

    It 'resolve diamante (dois pais independentes, um filho)' {
        $snapshot = New-TestSnapshot -Issues @(
            (New-TestNode -Number 1),
            (New-TestNode -Number 2),
            (New-TestNode -Number 3 -BlockedBy @('o/r#1', 'o/r#2'))
        )
        (Get-TopologicalOrder -Snapshot $snapshot).Order | Should -Be @('o/r#1', 'o/r#2', 'o/r#3')
    }
}
