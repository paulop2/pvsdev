Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Attempt.ps1"
}

Describe 'ConvertTo-AttemptComment' {
    It 'envolve o registro no marcador v1' {
        $record = [pscustomobject]@{ attemptId = 'a1'; issue = 42; status = 'started' }
        $body = ConvertTo-AttemptComment -Record $record
        $body | Should -Match 'delivery-queue-attempt:v1'
        $body | Should -Match 'a1'
    }
}

Describe 'ConvertFrom-AttemptComment' {
    It 'faz roundtrip do registro' {
        $record = [pscustomobject]@{ attemptId = 'a1'; issue = 42; status = 'delivered'; updatedAt = '2026-09-18T10:00:00Z' }
        $parsed = ConvertFrom-AttemptComment -Body (ConvertTo-AttemptComment -Record $record)
        $parsed.attemptId | Should -Be 'a1'
        $parsed.issue | Should -Be 42
        $parsed.status | Should -Be 'delivered'
    }

    It 'ignora texto humano ao redor' {
        $record = [pscustomobject]@{ attemptId = 'a2'; updatedAt = '2026-09-18T10:00:00Z' }
        $body = "comentario humano`n$(ConvertTo-AttemptComment -Record $record)`nfim"
        (ConvertFrom-AttemptComment -Body $body).attemptId | Should -Be 'a2'
    }

    It 'devolve nulo sem marcador' {
        ConvertFrom-AttemptComment -Body 'apenas texto' | Should -BeNullOrEmpty
    }

    It 'devolve nulo para corpo nulo' {
        ConvertFrom-AttemptComment -Body $null | Should -BeNullOrEmpty
    }
}

Describe 'Select-LatestAttempt' {
    It 'escolhe o registro com updatedAt maior' {
        $old = ConvertTo-AttemptComment -Record ([pscustomobject]@{ attemptId = 'old'; updatedAt = '2026-09-18T09:00:00Z' })
        $new = ConvertTo-AttemptComment -Record ([pscustomobject]@{ attemptId = 'new'; updatedAt = '2026-09-18T11:00:00Z' })
        (Select-LatestAttempt -Comments @($old, $new)).attemptId | Should -Be 'new'
    }

    It 'devolve nulo sem comentario de tentativa' {
        Select-LatestAttempt -Comments @('humano') | Should -BeNullOrEmpty
    }
}

Describe 'New-AttemptRecord' {
    It 'monta o registro inicial started' {
        $r = New-AttemptRecord -AttemptId '20260918T1000Z-a1b2' -Repository 'o/r' -Epic 9 -Issue 42 `
            -Branch 'feat/42-x' -Base 'master' -BaseSha 'abc' -Now '2026-09-18T10:00:00Z'
        $r.attemptId | Should -Be '20260918T1000Z-a1b2'
        $r.status | Should -Be 'started'
        $r.reason | Should -BeNullOrEmpty
        $r.pr | Should -BeNullOrEmpty
        $r.review | Should -BeNullOrEmpty
        $r.merge | Should -BeNullOrEmpty
        $r.postMerge | Should -BeNullOrEmpty
        $r.checks.Count | Should -Be 0
        $r.updatedAt | Should -Be '2026-09-18T10:00:00Z'
    }
}
