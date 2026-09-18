Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.DriverCore.ps1"
    . "$PSScriptRoot/TestHelpers.ps1"

    function New-Evidence {
        param($Command, $Result = 'pass', $HeadSha = 'h1', $At = '2026-09-18T10:00:00Z')
        [pscustomobject]@{ command = $Command; result = $Result; headSha = $HeadSha; at = $At }
    }
    function New-Review {
        param($Iterations = 1, $Blocking = 0, $HeadSha = 'h1')
        [pscustomobject]@{ iterations = $Iterations; blocking = $Blocking; headSha = $HeadSha }
    }
    function New-Attempt {
        param($Status = 'delivered', $Review = $null, $Checks = @(), $HeadSha = 'h1')
        [pscustomobject]@{ attemptId = 'a1'; repository = 'o/r'; epic = 9; issue = 1; branch = 'feat/1-x'; status = $Status; review = $Review; checks = $Checks; headSha = $HeadSha; pr = 7; nextAction = 'merge' }
    }
}

Describe 'Test-LocalEvidenceContract' {
    It 'aceita evidencia completa no head atual' {
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'npm run build')) -Policy (New-TestPolicy) -HeadSha 'h1') | Should -BeTrue
    }
    It 'rejeita evidencia de head antigo' {
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'npm run build' -HeadSha 'velho')) -Policy (New-TestPolicy) -HeadSha 'h1') | Should -BeFalse
    }
    It 'rejeita evidencia sem at' {
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'npm run build' -At '')) -Policy (New-TestPolicy) -HeadSha 'h1') | Should -BeFalse
    }
    It 'rejeita comando fora de requiredChecks' {
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'echo oi')) -Policy (New-TestPolicy) -HeadSha 'h1') | Should -BeFalse
    }
    It 'rejeita resultado nao pass' {
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'npm run build' -Result 'fail')) -Policy (New-TestPolicy) -HeadSha 'h1') | Should -BeFalse
    }
    It 'exige todos os requiredChecks' {
        $policy = New-TestPolicy
        $policy.requiredChecks = @('npm run build', 'npm run typecheck')
        (Test-LocalEvidenceContract -Evidence @((New-Evidence -Command 'npm run build')) -Policy $policy -HeadSha 'h1') | Should -BeFalse
    }
}

Describe 'Test-ReviewContract' {
    It 'aceita review valido' { (Test-ReviewContract -Attempt (New-Attempt -Review (New-Review)) -HeadSha 'h1') | Should -BeTrue }
    It 'rejeita zero iteracoes' { (Test-ReviewContract -Attempt (New-Attempt -Review (New-Review -Iterations 0)) -HeadSha 'h1') | Should -BeFalse }
    It 'rejeita mais de tres iteracoes' { (Test-ReviewContract -Attempt (New-Attempt -Review (New-Review -Iterations 4)) -HeadSha 'h1') | Should -BeFalse }
    It 'rejeita achado bloqueante' { (Test-ReviewContract -Attempt (New-Attempt -Review (New-Review -Blocking 1)) -HeadSha 'h1') | Should -BeFalse }
    It 'rejeita review de head antigo' { (Test-ReviewContract -Attempt (New-Attempt -Review (New-Review -HeadSha 'velho')) -HeadSha 'h1') | Should -BeFalse }
    It 'rejeita sem review' { (Test-ReviewContract -Attempt (New-Attempt) -HeadSha 'h1') | Should -BeFalse }
}

Describe 'Test-HandoffContract' {
    It 'aceita handoff delivered com campos' { (Test-HandoffContract -Attempt (New-Attempt)) | Should -BeTrue }
    It 'aceita handoff merged' { (Test-HandoffContract -Attempt (New-Attempt -Status 'merged')) | Should -BeTrue }
    It 'rejeita status started' { (Test-HandoffContract -Attempt (New-Attempt -Status 'started')) | Should -BeFalse }
    It 'rejeita sem tentativa' { (Test-HandoffContract -Attempt $null) | Should -BeFalse }
}

Describe 'Test-MergeReadiness' {
    BeforeAll {
        function New-Pr {
            param($State = 'OPEN', $IsDraft = $false, $HasConflict = $false, $ChecksComplete = $true, $HeadSha = 'h1')
            [pscustomobject]@{ number = 7; state = $State; isDraft = $IsDraft; hasConflict = $HasConflict; checksComplete = $ChecksComplete; headSha = $HeadSha; url = 'u'; baseRefName = 'master'; headRefName = 'feat/1-x' }
        }
    }
    It 'pronta quando PR, review, handoff e evidencias conferem' {
        $attempt = New-Attempt -Review (New-Review) -Checks @((New-Evidence -Command 'npm run build'))
        $r = Test-MergeReadiness -Pr (New-Pr) -Attempt $attempt -Policy (New-TestPolicy) -HeadSha 'h1'
        $r.Ready | Should -BeTrue
        $r.Reasons.Count | Should -Be 0
    }
    It 'nao pronta com draft' {
        $attempt = New-Attempt -Review (New-Review) -Checks @((New-Evidence -Command 'npm run build'))
        $r = Test-MergeReadiness -Pr (New-Pr -IsDraft $true) -Attempt $attempt -Policy (New-TestPolicy) -HeadSha 'h1'
        $r.Ready | Should -BeFalse
        $r.Reasons | Should -Contain 'draft'
    }
    It 'nao pronta com conflito' {
        $attempt = New-Attempt -Review (New-Review) -Checks @((New-Evidence -Command 'npm run build'))
        (Test-MergeReadiness -Pr (New-Pr -HasConflict $true) -Attempt $attempt -Policy (New-TestPolicy) -HeadSha 'h1').Reasons | Should -Contain 'conflito'
    }
    It 'nao pronta com checks remotos incompletos' {
        $attempt = New-Attempt -Review (New-Review) -Checks @((New-Evidence -Command 'npm run build'))
        (Test-MergeReadiness -Pr (New-Pr -ChecksComplete $false) -Attempt $attempt -Policy (New-TestPolicy) -HeadSha 'h1').Reasons | Should -Contain 'checks_remotos'
    }
    It 'nao pronta com head divergente' {
        $attempt = New-Attempt -Review (New-Review) -Checks @((New-Evidence -Command 'npm run build'))
        (Test-MergeReadiness -Pr (New-Pr -HeadSha 'velho') -Attempt $attempt -Policy (New-TestPolicy) -HeadSha 'h1').Reasons | Should -Contain 'head_divergente'
    }
    It 'nao pronta sem PR' {
        (Test-MergeReadiness -Pr $null -Attempt (New-Attempt) -Policy (New-TestPolicy) -HeadSha 'h1').Reasons | Should -Contain 'sem_pr'
    }
}
