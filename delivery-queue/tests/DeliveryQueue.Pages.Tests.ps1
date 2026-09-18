Set-StrictMode -Version Latest
BeforeAll {
    . "$PSScriptRoot/../src/DeliveryQueue.Resolver.ps1"
    . "$PSScriptRoot/../src/DeliveryQueue.Pages.ps1"
}

Describe 'Get-PagedItems' {
    It 'junta multiplas paginas' {
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue([pscustomobject]@{ items = @(1, 2); hasNextPage = $true; endCursor = 'c1' })
        $queue.Enqueue([pscustomobject]@{ items = @(3); hasNextPage = $false; endCursor = $null })
        $fetch = { param($cursor) return $queue.Dequeue() }

        $items = Get-PagedItems -FetchPage $fetch
        $items.Count | Should -Be 3
        $items | Should -Be @(1, 2, 3)
    }

    It 'devolve lista vazia quando a unica pagina e vazia' {
        $fetch = { param($cursor) return [pscustomobject]@{ items = @(); hasNextPage = $false; endCursor = $null } }
        (Get-PagedItems -FetchPage $fetch).Count | Should -Be 0
    }

    It 'lanca quando uma pagina falha, sem devolver parcial' {
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue([pscustomobject]@{ items = @(1); hasNextPage = $true; endCursor = 'c1' })
        $fetch = {
            param($cursor)
            if ($queue.Count -gt 0) { return $queue.Dequeue() }
            throw 'falha de rede'
        }
        { Get-PagedItems -FetchPage $fetch } | Should -Throw
    }

    It 'lanca quando hasNextPage e verdadeiro sem cursor' {
        $fetch = { param($cursor) return [pscustomobject]@{ items = @(1); hasNextPage = $true; endCursor = $null } }
        { Get-PagedItems -FetchPage $fetch } | Should -Throw
    }

    It 'lanca ao exceder o teto de paginas' {
        $fetch = { param($cursor) return [pscustomobject]@{ items = @(1); hasNextPage = $true; endCursor = 'x' } }
        { Get-PagedItems -FetchPage $fetch -MaxPages 3 } | Should -Throw
    }
}
