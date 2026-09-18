Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'DeliveryQueue.Resolver.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Pages.ps1')
. (Join-Path $PSScriptRoot 'DeliveryQueue.Collector.ps1')

function Invoke-GhJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]]$Arguments)

    $output = & gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh falhou ($LASTEXITCODE): $($output -join ' ')"
    }
    $text = (($output | ForEach-Object { [string]$_ }) -join "`n")
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json)
}

function New-DeliveryQueueGhAdapter {
    [CmdletBinding()]
    param([scriptblock]$InvokeGh)

    $getProp = Get-Command -Name Get-Prop -CommandType Function
    $getPagedItems = Get-Command -Name Get-PagedItems -CommandType Function
    $invokeGhJson = Get-Command -Name Invoke-GhJson -CommandType Function

    if (-not $InvokeGh) {
        $InvokeGh = { param([string[]]$Arguments) & $invokeGhJson -Arguments $Arguments }.GetNewClosure()
    }

    $getDefaultBranch = {
        param($Repository)
        $meta = & $InvokeGh -Arguments @('repo', 'view', $Repository, '--json', 'defaultBranchRef')
        $branch = [string]$meta.defaultBranchRef.name
        $head = & $InvokeGh -Arguments @('api', "repos/$Repository/commits/$branch")
        return [pscustomobject]@{ name = $branch; headSha = [string]$head.sha }
    }.GetNewClosure()

    $getSubIssues = {
        param($Repository, $Epic)
        $split = $Repository -split '/'
        $repoOwner = $split[0]
        $repoName = $split[1]
        $query = 'query($owner:String!,$name:String!,$number:Int!,$after:String){repository(owner:$owner,name:$name){issue(number:$number){subIssues(first:100,after:$after){pageInfo{hasNextPage endCursor}nodes{number id title state stateReason labels(first:100){nodes{name}} blockedBy(first:100){nodes{number}}}}}}}'
        $fetch = {
            param($cursor)
            $arguments = @('api', 'graphql', '-f', "query=$query", '-f', "owner=$repoOwner", '-f', "name=$repoName", '-F', "number=$Epic")
            if (-not [string]::IsNullOrWhiteSpace([string]$cursor)) {
                $arguments += @('-f', "after=$cursor")
            }
            $data = & $InvokeGh -Arguments $arguments
            $connection = $data.data.repository.issue.subIssues
            $items = @()
            foreach ($node in @($connection.nodes)) {
                $labels = @()
                foreach ($label in @($node.labels.nodes)) { $labels += [string]$label.name }
                $blocked = @()
                foreach ($blocker in @($node.blockedBy.nodes)) { $blocked += "$Repository#$([int]$blocker.number)" }
                $items += [pscustomobject]@{
                    number = [int]$node.number; nodeId = [string]$node.id
                    title = [string]$node.title; state = [string]$node.state
                    stateReason = [string]$node.stateReason; labels = $labels; blockedBy = $blocked
                }
            }
            return [pscustomobject]@{ items = $items; hasNextPage = [bool]$connection.pageInfo.hasNextPage; endCursor = $connection.pageInfo.endCursor }
        }.GetNewClosure()
        return (& $getPagedItems -FetchPage $fetch)
    }.GetNewClosure()

    $getProjectState = {
        param($Owner, $Number, $NodeId)
        $result = & $InvokeGh -Arguments @('project', 'item-list', [string]$Number, '--owner', $Owner, '--format', 'json', '--limit', '2000')
        foreach ($item in @($result.items)) {
            $content = & $getProp -Object $item -Name 'content'
            $contentId = [string](& $getProp -Object $content -Name 'id')
            if ($contentId -eq [string]$NodeId) {
                $state = [string](& $getProp -Object $item -Name 'status')
                if ([string]::IsNullOrWhiteSpace($state)) { $state = [string](& $getProp -Object $item -Name 'Status') }
                return [pscustomobject]@{ found = $true; state = $state }
            }
        }
        return [pscustomobject]@{ found = $false; state = $null }
    }.GetNewClosure()

    $getIssueComments = {
        param($Repository, $Issue)
        $data = & $InvokeGh -Arguments @('issue', 'view', [string]$Issue, '--repo', $Repository, '--json', 'comments')
        $bodies = @()
        foreach ($comment in @($data.comments)) { $bodies += [string]$comment.body }
        return $bodies
    }.GetNewClosure()

    $getIssuePrs = {
        param($Repository, $Issue)
        $json = 'number,state,isDraft,baseRefName,headRefName,headRefOid,url,mergeable,body,statusCheckRollup'
        $prs = & $InvokeGh -Arguments @('pr', 'list', '--repo', $Repository, '--state', 'all', '--search', "$Issue in:body", '--json', $json, '--limit', '500')
        $pattern = "(?im)\b(?:close[sd]?|fixe[sd]?|resolve[sd]?)\s+#$Issue\b"
        $result = @()
        foreach ($pr in @($prs)) {
            if ([string](& $getProp -Object $pr -Name 'body') -notmatch $pattern) { continue }
            $rollup = & $getProp -Object $pr -Name 'statusCheckRollup'
            $checks = @()
            $known = $null -ne $rollup
            foreach ($entry in @($rollup)) {
                $context = [string](& $getProp -Object $entry -Name 'name')
                if ([string]::IsNullOrWhiteSpace($context)) { $context = [string](& $getProp -Object $entry -Name 'context') }
                $conclusion = [string](& $getProp -Object $entry -Name 'conclusion')
                if ([string]::IsNullOrWhiteSpace($conclusion)) { $conclusion = [string](& $getProp -Object $entry -Name 'state') }
                $checks += [pscustomobject]@{ context = $context; conclusion = $conclusion}
            }
            $mergeable = [string](& $getProp -Object $pr -Name 'mergeable')
            $result += [pscustomobject]@{
                number = [int](& $getProp -Object $pr -Name 'number')
                state = [string](& $getProp -Object $pr -Name 'state')
                isDraft = [bool](& $getProp -Object $pr -Name 'isDraft' -Default $false)
                baseRefName = [string](& $getProp -Object $pr -Name 'baseRefName')
                headRefName = [string](& $getProp -Object $pr -Name 'headRefName')
                headSha = [string](& $getProp -Object $pr -Name 'headRefOid')
                url = [string](& $getProp -Object $pr -Name 'url')
                hasConflict = ($mergeable -eq 'CONFLICTING')
                checks = $checks
                checksKnown = $known
            }
        }
        return $result
    }.GetNewClosure()

    $getBlockerIssues = {
        param($Repository, $Ids)
        $map = @{}
        foreach ($id in @($Ids)) {
            if ($id -notmatch '#(?<n>\d+)$') { continue }
            $number = [int]$Matches['n']
            $data = & $InvokeGh -Arguments @('issue', 'view', [string]$number, '--repo', $Repository, '--json', 'state,stateReason')
            $map[[string]$id] = [pscustomobject]@{ state = [string](& $getProp -Object $data -Name 'state'); stateReason = [string](& $getProp -Object $data -Name 'stateReason') }
        }
        return $map
    }.GetNewClosure()

    $getRefSha = {
        param($Ref)
        $output = & git rev-parse --verify --quiet $Ref 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ([string]$output).Trim()
    }.GetNewClosure()

    return [pscustomobject]@{
        GetDefaultBranch = $getDefaultBranch
        GetSubIssues     = $getSubIssues
        GetProjectState  = $getProjectState
        GetIssueComments = $getIssueComments
        GetIssuePrs      = $getIssuePrs
        GetBlockerIssues = $getBlockerIssues
        GetRefSha        = $getRefSha
    }
}
