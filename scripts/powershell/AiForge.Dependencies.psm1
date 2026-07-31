#Requires -Version 5.1

<#
.SYNOPSIS
    External command and MCP server dependency reporting.

.DESCRIPTION
    Ports sections 5, 5b and 5c of install.sh. Nothing here installs anything:
    the tables are informational so the user knows which CLIs to install and
    which MCP servers to configure before using the selected skills.

    Keep the two lookup tables below in sync with cmd_deps_for / mcp_deps_for
    in install.sh -- the CI parity job compares the rendered tables.
#>

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'AiForge.Console.psm1') -DisableNameChecking

# Key format: skills and readme skills use "<subfolder>/<name>", agents use
# "agent/<name>". A token may list interchangeable alternatives separated by
# "|" (satisfied when any one of them is on the PATH).
$script:CommandDependencies = @{
    'common/context7-cli'                             = 'ctx7'
    'common/gh'                                       = 'gh'
    'common/glab'                                     = 'glab'
    'common/git-workflow'                             = 'git'
    'common/create-mr-pr'                             = 'git gh|glab'
    'python/pytest'                                   = 'python3|python pytest'
    'hexagonal-architecture/create-alembic-migration' = 'python3|python alembic|poetry|uv|pdm'
    'hexagonal-architecture/hexagonal-architecture-testing' = 'python3|python pytest|poetry|uv'
    'playwright/playwright-cli'                       = 'playwright-cli|playwright'
    'agent/mr-pr-reviewer'                            = 'git gh|glab'
}

# A token may carry a "(fallback)" suffix marking non-critical use.
$script:McpDependencies = @{
    'chrome/chrome-devtools'         = 'chrome-devtools'
    'astro/astro'                    = 'astro-docs'
    'common/context7-cli'            = 'context7(fallback)'
    'playwright/webapp-testing'      = 'playwright(fallback)'
    'playwright/e2e-testing'         = 'playwright(fallback)'
    'playwright/web-design-reviewer' = 'playwright(fallback)'
}

function Get-AiForgeCommandDependency {
    <#
    .SYNOPSIS
        Returns the CLI tokens an item expects on the PATH.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string] $Key)

    if (-not $script:CommandDependencies.ContainsKey($Key)) { return @() }
    @($script:CommandDependencies[$Key] -split '\s+' | Where-Object { $_ })
}

function Get-AiForgeMcpDependency {
    <#
    .SYNOPSIS
        Returns the MCP server tokens an item relies on.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string] $Key)

    if (-not $script:McpDependencies.ContainsKey($Key)) { return @() }
    @($script:McpDependencies[$Key] -split '\s+' | Where-Object { $_ })
}

function Get-AiForgeSkillDependency {
    <#
    .SYNOPSIS
        Returns the skills a skill depends on.

    .DESCRIPTION
        Mirrors deps_for in install.sh. No hard dependencies are declared yet;
        add them here (and there) as the catalog grows -- the resolution engine
        already enforces whatever this returns.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string] $Name)

    $dependencies = @{
        # 'example-skill' = @('git-workflow')
    }

    if ($dependencies.ContainsKey($Name)) { return @($dependencies[$Name]) }
    @()
}

function Get-AiForgeUnmetDependency {
    <#
    .SYNOPSIS
        Lists selected skills whose dependencies are neither selected nor
        already installed.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Selection,
        [Parameter(Mandatory)][scriptblock] $InstalledTest
    )

    $selectedNames = @($Selection.Skills | ForEach-Object { $_.Name })
    $unmet = [System.Collections.Generic.List[object]]::new()

    foreach ($skill in $Selection.Skills) {
        $missing = @(Get-AiForgeSkillDependency -Name $skill.Name | Where-Object {
            ($selectedNames -notcontains $_) -and -not (& $InstalledTest $_)
        })
        if ($missing.Count -gt 0) {
            $unmet.Add([pscustomobject]@{ Name = $skill.Name; Missing = $missing })
        }
    }

    , $unmet.ToArray()
}

function Test-AiForgeCommandAvailable {
    <#
    .SYNOPSIS
        The equivalent of `command -v <name>`.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string] $Name)

    [bool] (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Resolve-AiForgeDependencyToken {
    <#
    .SYNOPSIS
        Resolves one token (possibly "a|b|c") into a display string and status.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string] $Token)

    $alternatives = @($Token -split '\|' | Where-Object { $_ })
    $found = $null
    foreach ($alternative in $alternatives) {
        if (Test-AiForgeCommandAvailable -Name $alternative) { $found = $alternative; break }
    }

    [pscustomobject]@{
        Requirement = ($alternatives -join ' or ')
        Available   = [bool] $found
        Found       = if ($found) { $found } else { '' }
    }
}

function New-AiForgeDependencyTable {
    <#
    .SYNOPSIS
        Builds the external command dependency rows for the current selection.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][pscustomobject] $Selection)

    $rows = [System.Collections.Generic.List[object]]::new()

    $lookups = @()
    foreach ($skill in $Selection.Skills)  { $lookups += , @($skill.Name,  "$($skill.Sub)/$($skill.Name)") }
    foreach ($remote in $Selection.Remote) { $lookups += , @($remote.Name, "$($remote.Name)/$($remote.Name)") }
    foreach ($agent in $Selection.Agents)  { $lookups += , @($agent.Name,  "agent/$($agent.Name)") }

    foreach ($lookup in $lookups) {
        foreach ($token in (Get-AiForgeCommandDependency -Key $lookup[1])) {
            $resolved = Resolve-AiForgeDependencyToken -Token $token
            $rows.Add([pscustomobject]@{
                Item        = $lookup[0]
                Requirement = $resolved.Requirement
                Available   = $resolved.Available
                Found       = $resolved.Found
            })
        }
    }

    , $rows.ToArray()
}

function Get-AiForgeMcpConfigFile {
    <#
    .SYNOPSIS
        MCP config files that may declare servers in the target project.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string] $ProjectPath)

    @(
        (Join-Path $ProjectPath '.mcp.json')
        (Join-Path $ProjectPath '.cursor/mcp.json')
        (Join-Path $ProjectPath '.agents/mcp/mcp.json')
    )
}

function Test-AiForgeMcpConfigured {
    <#
    .SYNOPSIS
        Best-effort check that an MCP server is referenced by a project config.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $ServerName
    )

    foreach ($file in (Get-AiForgeMcpConfigFile -ProjectPath $ProjectPath)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $content = Get-Content -LiteralPath $file -Raw -ErrorAction SilentlyContinue
        if ($content -and $content.Contains("`"$ServerName`"")) { return $true }
    }
    $false
}

function New-AiForgeMcpTable {
    <#
    .SYNOPSIS
        Builds the MCP server dependency rows for the current selection.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Selection,
        [Parameter(Mandatory)][string] $ProjectPath
    )

    $rows = [System.Collections.Generic.List[object]]::new()

    $lookups = @()
    foreach ($skill in $Selection.Skills)  { $lookups += , @($skill.Name,  "$($skill.Sub)/$($skill.Name)") }
    foreach ($remote in $Selection.Remote) { $lookups += , @($remote.Name, "$($remote.Name)/$($remote.Name)") }
    foreach ($agent in $Selection.Agents)  { $lookups += , @($agent.Name,  "agent/$($agent.Name)") }

    foreach ($lookup in $lookups) {
        foreach ($token in (Get-AiForgeMcpDependency -Key $lookup[1])) {
            $note = ''
            $server = $token
            if ($token -match '^(?<name>[^(]+)\((?<note>[^)]+)\)$') {
                $server = $Matches['name']
                $note = $Matches['note']
            }
            $rows.Add([pscustomobject]@{
                Item       = $lookup[0]
                Server     = $server
                Note       = $note
                Configured = Test-AiForgeMcpConfigured -ProjectPath $ProjectPath -ServerName $server
            })
        }
    }

    , $rows.ToArray()
}

function Write-AiForgeDependencyTable {
    <#
    .SYNOPSIS
        Renders the external command dependency table.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Rows)

    if ($Rows.Count -eq 0) { return }

    $itemWidth = [Math]::Max(4, ($Rows | ForEach-Object { $_.Item.Length } | Measure-Object -Maximum).Maximum)
    $reqWidth = [Math]::Max(7, ($Rows | ForEach-Object { $_.Requirement.Length } | Measure-Object -Maximum).Maximum)

    Write-AiForgeHeading 'External command dependencies:'
    Write-AiForgeText '(not installed by this script -- install any missing tools yourself)' -Color DarkGray
    Write-AiForgeText ("  {0}  {1}  {2}" -f 'Item'.PadRight($itemWidth), 'Command'.PadRight($reqWidth), 'Status')
    Write-AiForgeText ("  {0}  {1}  {2}" -f ('-' * $itemWidth), ('-' * $reqWidth), '------')

    $missing = 0
    foreach ($row in $Rows) {
        Write-AiForgeText ("  {0}  {1}  " -f $row.Item.PadRight($itemWidth), $row.Requirement.PadRight($reqWidth)) -NoNewline
        if ($row.Available) {
            Write-AiForgeText ("{0} available ({1})" -f (Get-AiForgeGlyph Check), $row.Found) -Color Green
        } else {
            $missing++
            Write-AiForgeText ("{0} missing" -f (Get-AiForgeGlyph Cross)) -Color Red
        }
    }

    if ($missing -gt 0) {
        Write-AiForgeText "$missing command(s) missing. Install them before using the affected skills/agents." -Color Yellow
    }
}

function Write-AiForgeMcpTable {
    <#
    .SYNOPSIS
        Renders the MCP server dependency table.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Rows)

    if ($Rows.Count -eq 0) { return }

    $itemWidth = [Math]::Max(4, ($Rows | ForEach-Object { $_.Item.Length } | Measure-Object -Maximum).Maximum)
    $serverWidth = [Math]::Max(10, ($Rows | ForEach-Object { $_.Server.Length } | Measure-Object -Maximum).Maximum)

    Write-AiForgeHeading 'MCP server dependencies:'
    Write-AiForgeText '(not configured by this script -- see assets/MCPs/.mcp.json for a template)' -Color DarkGray
    Write-AiForgeText ("  {0}  {1}  {2}" -f 'Item'.PadRight($itemWidth), 'MCP server'.PadRight($serverWidth), 'Status')
    Write-AiForgeText ("  {0}  {1}  {2}" -f ('-' * $itemWidth), ('-' * $serverWidth), '------')

    $missing = 0
    foreach ($row in $Rows) {
        Write-AiForgeText ("  {0}  {1}  " -f $row.Item.PadRight($itemWidth), $row.Server.PadRight($serverWidth)) -NoNewline
        if ($row.Configured) {
            Write-AiForgeText ("{0} configured" -f (Get-AiForgeGlyph Check)) -Color Green -NoNewline
        } else {
            $missing++
            Write-AiForgeText ("{0} not configured" -f (Get-AiForgeGlyph Circle)) -Color Yellow -NoNewline
        }
        if ($row.Note) {
            Write-AiForgeText ("  ({0})" -f $row.Note) -Color DarkGray -NoNewline
        }
        Write-AiForgeText ''
    }

    if ($missing -gt 0) {
        Write-AiForgeText "$missing MCP server(s) not found in the project's MCP config. Add them to use the affected skills." -Color Yellow
    }
}

Export-ModuleMember -Function @(
    'Get-AiForgeCommandDependency'
    'Get-AiForgeMcpDependency'
    'Get-AiForgeSkillDependency'
    'Get-AiForgeUnmetDependency'
    'Test-AiForgeCommandAvailable'
    'Resolve-AiForgeDependencyToken'
    'New-AiForgeDependencyTable'
    'Get-AiForgeMcpConfigFile'
    'Test-AiForgeMcpConfigured'
    'New-AiForgeMcpTable'
    'Write-AiForgeDependencyTable'
    'Write-AiForgeMcpTable'
)
