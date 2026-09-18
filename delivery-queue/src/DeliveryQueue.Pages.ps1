Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')

function Get-PagedItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock]$FetchPage,
        [int]$MaxPages = 100
    )

    $items = @()
    $cursor = $null
    $page = 0

    while ($true) {
        $page++
        if ($page -gt $MaxPages) {
            throw "paginacao excedeu $MaxPages paginas"
        }

        $result = & $FetchPage $cursor
        if ($null -eq $result) {
            throw 'pagina de coleta ausente'
        }

        $pageItems = Get-Array -Value (Get-Prop -Object $result -Name 'items')
        foreach ($item in $pageItems) { $items += $item }

        $hasNext = [bool](Get-Prop -Object $result -Name 'hasNextPage' -Default $false)
        if (-not $hasNext) { break }

        $cursor = Get-Prop -Object $result -Name 'endCursor'
        if ([string]::IsNullOrWhiteSpace([string]$cursor)) {
            throw 'paginacao com hasNextPage=true e sem endCursor'
        }
    }

    return ,$items
}
