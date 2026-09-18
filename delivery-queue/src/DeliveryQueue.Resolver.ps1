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
