Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
}

Describe 'Get-Prop' {
    It 'retorna o valor quando a propriedade existe' {
        Get-Prop -Object ([pscustomobject]@{ a = 1 }) -Name 'a' | Should -Be 1
    }

    It 'retorna default quando a propriedade nao existe (sem lancar sob StrictMode)' {
        Get-Prop -Object ([pscustomobject]@{ a = 1 }) -Name 'b' -Default 'x' | Should -Be 'x'
    }

    It 'retorna default quando o objeto e nulo' {
        Get-Prop -Object $null -Name 'a' | Should -BeNullOrEmpty
    }
}

Describe 'Get-Array' {
    It 'normaliza nulo para array vazio' {
        (Get-Array -Value $null).Count | Should -Be 0
    }

    It 'preserva um item unico como array de um' {
        (Get-Array -Value 'x').Count | Should -Be 1
    }

    It 'preserva array existente' {
        (Get-Array -Value @(1, 2)).Count | Should -Be 2
    }
}

Describe 'Test-DeliveryQueuePolicy' {
    BeforeAll {
        $base = [pscustomobject]@{
            version               = 1
            defaultBranch         = 'master'
            mergeMode             = 'human'
            project               = [pscustomobject]@{ owner = 'o'; number = 5; eligibleStates = @('Ready'); resumableStates = @('In Progress') }
            fallbackEligibility   = $null
            requiredChecks        = @('npm run build')
            requiredRemoteChecks  = @()
            merge                 = [pscustomobject]@{ method = 'merge'; requireChecksOnPr = $true; verifyDefaultBranchAfterMerge = $true; authorizedByLocalRules = $false; allowAdminBypass = $false }
            completionWithoutCode = 'requires-evidence'
        }
    }

    It 'aceita politica valida' {
        (Test-DeliveryQueuePolicy -Policy $base).Count | Should -Be 0
    }

    It 'rejeita politica ausente' {
        Test-DeliveryQueuePolicy -Policy $null | Should -Contain 'policy ausente'
    }

    It 'rejeita version diferente de 1' {
        $p = $base.PSObject.Copy(); $p.version = 2
        (Test-DeliveryQueuePolicy -Policy $p) | Should -Match 'version'
    }

    It 'rejeita mergeMode invalido' {
        $p = $base.PSObject.Copy(); $p.mergeMode = 'sometimes'
        (Test-DeliveryQueuePolicy -Policy $p) | Should -Match 'mergeMode'
    }

    It 'rejeita auto sem atestacao de regra local' {
        $p = $base.PSObject.Copy(); $p.mergeMode = 'auto'; $p.merge = $base.merge.PSObject.Copy(); $p.merge.authorizedByLocalRules = $false
        (Test-DeliveryQueuePolicy -Policy $p) | Should -Match 'authorizedByLocalRules'
    }

    It 'aceita auto com atestacao' {
        $p = $base.PSObject.Copy(); $p.mergeMode = 'auto'; $p.merge = $base.merge.PSObject.Copy(); $p.merge.authorizedByLocalRules = $true
        (Test-DeliveryQueuePolicy -Policy $p).Count | Should -Be 0
    }

    It 'exige projeto ou fallback de elegibilidade' {
        $p = $base.PSObject.Copy(); $p.project = $null; $p.fallbackEligibility = $null
        (Test-DeliveryQueuePolicy -Policy $p) | Should -Match 'fallbackEligibility'
    }

    It 'aceita fallback no lugar do projeto' {
        $p = $base.PSObject.Copy(); $p.project = $null; $p.fallbackEligibility = 'label:agent-ready'
        (Test-DeliveryQueuePolicy -Policy $p).Count | Should -Be 0
    }

    It 'rejeita postMergeRetries negativo' {
        $p = $base.PSObject.Copy(); $p | Add-Member -NotePropertyName postMergeRetries -NotePropertyValue -1 -Force
        (Test-DeliveryQueuePolicy -Policy $p) | Should -Match 'postMergeRetries'
    }

    It 'aceita postMergeRetries e setup validos' {
        $p = $base.PSObject.Copy()
        $p | Add-Member -NotePropertyName postMergeRetries -NotePropertyValue 2 -Force
        $p | Add-Member -NotePropertyName postMergeSetupCommands -NotePropertyValue @('npm ci') -Force
        (Test-DeliveryQueuePolicy -Policy $p).Count | Should -Be 0
    }

    It 'rejeita postMergeSetupCommands que nao e array' {
        $p = $base.PSObject.Copy()
        $p | Add-Member -NotePropertyName postMergeSetupCommands -NotePropertyValue ([pscustomobject]@{ a = 1 }) -Force
        (Test-DeliveryQueuePolicy -Policy $p) | Should -Match 'postMergeSetupCommands'
    }
}
