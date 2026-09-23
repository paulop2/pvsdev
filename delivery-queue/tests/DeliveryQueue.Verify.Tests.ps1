Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Common.ps1"
}

Describe 'Invoke-VerifyCommands' {
    It 'executa setup antes dos comandos e retorna pass' {
        $calls = [System.Collections.Generic.List[string]]::new()
        $proc = {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            $calls.Add([string]$Arguments[3])
            [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' }
        }.GetNewClosure()

        $result = Invoke-VerifyCommands -Commands @('build') -SetupCommands @('install') -WorkingDirectory 'x' -InvokeProcess $proc

        $result | Should -Be 'pass'
        ($calls -join ',') | Should -Be 'install,build'
    }

    It 'nao roda setup quando nao configurado' {
        $calls = [System.Collections.Generic.List[string]]::new()
        $proc = {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            $calls.Add([string]$Arguments[3])
            [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' }
        }.GetNewClosure()

        $null = Invoke-VerifyCommands -Commands @('typecheck') -WorkingDirectory 'x' -InvokeProcess $proc

        ($calls -join ',') | Should -Be 'typecheck'
    }

    It 'repete comando falho e passa quando o retry funciona' {
        $state = @{ attempts = 0 }
        $proc = {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            $state.attempts++
            if ($state.attempts -lt 2) { return [pscustomobject]@{ exitCode = 1; timedOut = $false; output = 'boom' } }
            [pscustomobject]@{ exitCode = 0; timedOut = $false; output = '' }
        }.GetNewClosure()

        $result = Invoke-VerifyCommands -Commands @('build') -WorkingDirectory 'x' -Retries 2 -InvokeProcess $proc -Sleep { param($Seconds) }

        $result | Should -Be 'pass'
        $state.attempts | Should -Be 2
    }

    It 'falha apos esgotar as tentativas' {
        $state = @{ attempts = 0 }
        $proc = {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            $state.attempts++
            [pscustomobject]@{ exitCode = 1; timedOut = $false; output = 'boom' }
        }.GetNewClosure()

        $result = Invoke-VerifyCommands -Commands @('build') -WorkingDirectory 'x' -Retries 2 -InvokeProcess $proc -Sleep { param($Seconds) }

        $result | Should -Be 'fail'
        $state.attempts | Should -Be 3
    }

    It 'com Retries 0 executa uma unica vez' {
        $state = @{ attempts = 0 }
        $proc = {
            param($FilePath, $Arguments, $WorkingDirectory, $TimeoutSeconds)
            $state.attempts++
            [pscustomobject]@{ exitCode = 1; timedOut = $false; output = 'boom' }
        }.GetNewClosure()

        $result = Invoke-VerifyCommands -Commands @('build') -WorkingDirectory 'x' -InvokeProcess $proc -Sleep { param($Seconds) }

        $result | Should -Be 'fail'
        $state.attempts | Should -Be 1
    }
}
