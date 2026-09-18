Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Lock.ps1"
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dq-lock-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
}
AfterAll {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Enter-QueueLock' {
    It 'adquire o lock livre' {
        $lock = Enter-QueueLock -Repository 'o/r' -Root $root
        try {
            $lock.Acquired | Should -BeTrue
            (Test-Path -LiteralPath $lock.Path) | Should -BeTrue
        }
        finally { Exit-QueueLock -Lock $lock }
    }

    It 'recusa a segunda instancia enquanto o lock esta retido' {
        $first = Enter-QueueLock -Repository 'o/r' -Root $root
        try {
            $second = Enter-QueueLock -Repository 'o/r' -Root $root
            $second.Acquired | Should -BeFalse
            $second.Stream | Should -BeNullOrEmpty
        }
        finally { Exit-QueueLock -Lock $first }
    }

    It 'libera e permite readquirir' {
        $first = Enter-QueueLock -Repository 'o/r' -Root $root
        Exit-QueueLock -Lock $first
        $second = Enter-QueueLock -Repository 'o/r' -Root $root
        try { $second.Acquired | Should -BeTrue }
        finally { Exit-QueueLock -Lock $second }
    }

    It 'isola repositorios diferentes' {
        $a = Enter-QueueLock -Repository 'o/a' -Root $root
        $b = Enter-QueueLock -Repository 'o/b' -Root $root
        try {
            $a.Acquired | Should -BeTrue
            $b.Acquired | Should -BeTrue
            $a.Path | Should -Not -Be $b.Path
        }
        finally { Exit-QueueLock -Lock $a; Exit-QueueLock -Lock $b }
    }
}
