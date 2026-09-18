Set-StrictMode -Version Latest

function Get-Prop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] [object]$Object,
        [Parameter(Mandatory)] [string]$Name,
        [AllowNull()] [object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    if ($null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-Array {
    [CmdletBinding()]
    param([AllowNull()] [object]$Value)

    if ($null -eq $Value) { return ,@() }
    return ,@($Value)
}

function Test-DeliveryQueuePolicy {
    [CmdletBinding()]
    param([AllowNull()] [object]$Policy)

    if ($null -eq $Policy) { return @('policy ausente') }

    $problems = @()

    if ((Get-Prop -Object $Policy -Name 'version') -ne 1) {
        $problems += "version deve ser 1, veio '$(Get-Prop -Object $Policy -Name 'version')'"
    }

    if ([string]::IsNullOrWhiteSpace([string](Get-Prop -Object $Policy -Name 'defaultBranch'))) {
        $problems += 'defaultBranch obrigatorio'
    }

    $mergeMode = [string](Get-Prop -Object $Policy -Name 'mergeMode')
    if ($mergeMode -notin @('human', 'auto')) {
        $problems += "mergeMode invalido: '$mergeMode'"
    }

    $merge = Get-Prop -Object $Policy -Name 'merge'
    if ($mergeMode -eq 'auto' -and -not [bool](Get-Prop -Object $merge -Name 'authorizedByLocalRules' -Default $false)) {
        $problems += 'policy_conflict: mergeMode auto exige merge.authorizedByLocalRules=true (regras locais prevalecem)'
    }

    if ($null -eq (Get-Prop -Object $Policy -Name 'project') -and
        [string]::IsNullOrWhiteSpace([string](Get-Prop -Object $Policy -Name 'fallbackEligibility'))) {
        $problems += 'sem project e sem fallbackEligibility: elegibilidade indefinida'
    }

    $completion = [string](Get-Prop -Object $Policy -Name 'completionWithoutCode')
    if ($completion -notin @('requires-evidence', 'allow-closed')) {
        $problems += "completionWithoutCode invalido: '$completion'"
    }

    return ,$problems
}

function New-IssueId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [int]$Number
    )

    return "$Repository#$Number"
}

function Get-NodeIndex {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Snapshot)

    $repository = [string](Get-Prop -Object $Snapshot -Name 'repository')
    $index = @{}

    foreach ($node in (Get-Array -Value (Get-Prop -Object $Snapshot -Name 'issues'))) {
        $id = [string](Get-Prop -Object $node -Name 'id')
        if ([string]::IsNullOrWhiteSpace($id)) {
            $id = New-IssueId -Repository $repository -Number ([int](Get-Prop -Object $node -Name 'number'))
        }
        $index[$id] = $node
    }

    return $index
}

function Get-TopologicalOrder {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Snapshot)

    $index = Get-NodeIndex -Snapshot $Snapshot

    $inScope = @()
    foreach ($key in $index.Keys) {
        if ([bool](Get-Prop -Object $index[$key] -Name 'inScope' -Default $true)) {
            $inScope += [string]$key
        }
    }

    $sortKey = @{}
    $inDegree = @{}
    $dependents = @{}
    foreach ($id in $inScope) {
        $sortKey[$id] = '{0:D10}|{1}' -f [int](Get-Prop -Object $index[$id] -Name 'number' -Default 0), $id
        $inDegree[$id] = 0
        $dependents[$id] = @()
    }

    foreach ($id in $inScope) {
        foreach ($blocker in (Get-Array -Value (Get-Prop -Object $index[$id] -Name 'blockedBy'))) {
            $blockerId = [string]$blocker
            if ($inDegree.ContainsKey($blockerId)) {
                $inDegree[$id] = $inDegree[$id] + 1
                $dependents[$blockerId] += $id
            }
        }
    }

    $ready = @($inScope | Where-Object { $inDegree[$_] -eq 0 })
    $order = @()

    while ($ready.Count -gt 0) {
        $ready = @($ready | Sort-Object { $sortKey[$_] })
        $current = $ready[0]
        $ready = @($ready | Where-Object { $_ -ne $current })
        $order += $current

        foreach ($dependent in (Get-Array -Value $dependents[$current])) {
            $inDegree[$dependent] = $inDegree[$dependent] - 1
            if ($inDegree[$dependent] -eq 0) { $ready += $dependent }
        }
    }

    $cycle = @($inScope | Where-Object { $order -notcontains $_ })

    return [pscustomobject]@{
        Order = $order
        Cycle = $cycle
        Index = $index
    }
}
