Set-StrictMode -Version Latest
BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    . (Join-Path $repoRoot 'delivery-queue/src/DeliveryQueue.Resolver.ps1')

    function Get-Frontmatter {
        param([string]$Path)
        $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $match = [regex]::Match($text, '(?s)^---\s*(.*?)\s*---')
        if (-not $match.Success) { return $null }
        return $match.Groups[1].Value
    }
}

Describe 'schema/policy-v1.json' {
    It 'e JSON valido com schema draft e propriedades' {
        $path = Join-Path $repoRoot 'delivery-queue/schema/policy-v1.json'
        (Test-Path -LiteralPath $path) | Should -BeTrue
        $schema = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $schema.'$schema' | Should -Match 'json-schema.org'
        $schema.properties.version.type | Should -Be 'integer'
        $schema.properties.merge.properties.authorizedByLocalRules.type | Should -Be 'boolean'
    }
}

Describe 'agentes' {
    It 'declara modelo e descricao em cada agente' {
        foreach ($name in @('delivery-queue-worker', 'delivery-queue-reviewer', 'delivery-queue-fixer')) {
            $path = Join-Path $repoRoot ".opencode/agent/$name.md"
            (Test-Path -LiteralPath $path) | Should -BeTrue
            $front = Get-Frontmatter -Path $path
            $front | Should -Match 'description:'
            $front | Should -Match 'model:'
        }
    }

    It 'worker nega question e doom_loop' {
        $front = Get-Frontmatter -Path (Join-Path $repoRoot '.opencode/agent/delivery-queue-worker.md')
        $front | Should -Match '(?m)^\s*question:\s*deny'
        $front | Should -Match '(?m)^\s*doom_loop:\s*deny'
    }

    It 'reviewer e read-only' {
        $front = Get-Frontmatter -Path (Join-Path $repoRoot '.opencode/agent/delivery-queue-reviewer.md')
        $front | Should -Match '(?m)^\s*edit:\s*deny'
    }
}

Describe 'comando delivery-queue-deliver-issue' {
    It 'aponta para o worker e tem template com ARGUMENTS' {
        $path = Join-Path $repoRoot '.opencode/command/delivery-queue-deliver-issue.md'
        (Test-Path -LiteralPath $path) | Should -BeTrue
        $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        (Get-Frontmatter -Path $path) | Should -Match 'agent:\s*delivery-queue-worker'
        $text | Should -Match '\$ARGUMENTS'
    }
}

Describe 'politica local do pvsdev' {
    It 'usa mergeMode human e nao autoriza auto' {
        $path = Join-Path $repoRoot '.delivery-queue/policy.json'
        (Test-Path -LiteralPath $path) | Should -BeTrue
        $policy = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $policy.mergeMode | Should -Be 'human'
        $policy.merge.authorizedByLocalRules | Should -BeFalse
        $policy.defaultBranch | Should -Be 'master'
    }

    It 'configura setup de deps e retries na verificacao pos-merge' {
        $path = Join-Path $repoRoot '.delivery-queue/policy.json'
        $policy = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        @($policy.postMergeSetupCommands).Count | Should -BeGreaterThan 0
        $policy.postMergeRetries | Should -BeGreaterThan 0
    }

    It 'passa na validacao de politica' {
        $path = Join-Path $repoRoot '.delivery-queue/policy.json'
        $policy = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        (Test-DeliveryQueuePolicy -Policy $policy).Count | Should -Be 0
    }
}
