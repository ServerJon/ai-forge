#Requires -Version 5.1

<#
.SYNOPSIS
    Builds the tree of installable agents, skills and helper commands.

.DESCRIPTION
    Ports section 2 of install.sh. The catalog is a flat, ordered list of rows
    where each row points at its parent by index -- the same data model the
    bash menu uses, which keeps the two renderers behaviourally identical.

    Row types:
      cat    category header ("Agents" / "Skills")
      sub    subfolder inside a category
      skill  a directory containing SKILL.md
      agent  a single .md file describing an agent
      readme a "remote" skill bundle installed by a command in its README.md
      cmd    a helper command (autoskills, recommendation scans, MCP config)
#>

Set-StrictMode -Version Latest

function New-AiForgeItem {
    <#
    .SYNOPSIS
        Creates one catalog row.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][ValidateSet('cat', 'sub', 'skill', 'agent', 'readme', 'cmd')][string] $Type,
        [string] $Note = '',
        [string] $Sub = '',
        [string] $Name = '',
        [string] $Source = '',
        [int]    $Parent = -1,
        [int]    $Depth = 0
    )

    [pscustomobject]@{
        Label     = $Label
        Note      = $Note
        Type      = $Type
        Sub       = $Sub
        Name      = $Name
        Source    = $Source
        Parent    = $Parent
        Depth     = $Depth
        Checked   = $false
        Installed = $false
        Disabled  = $false
    }
}

function Get-AiForgeSkillsDestination {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $ProjectPath)

    Join-Path $ProjectPath '.agents/skills'
}

function Get-AiForgeAgentsDestination {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $ProjectPath)

    Join-Path $ProjectPath '.agents/agents'
}

function Test-AiForgeSkillInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $Name
    )

    $marker = Join-Path (Get-AiForgeSkillsDestination $ProjectPath) (Join-Path $Name 'SKILL.md')
    Test-Path -LiteralPath $marker -PathType Leaf
}

function Test-AiForgeAgentInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $Name
    )

    $marker = Join-Path (Get-AiForgeAgentsDestination $ProjectPath) ("$Name.md")
    Test-Path -LiteralPath $marker -PathType Leaf
}

function Get-AiForgeOrdinalSort {
    <#
    .SYNOPSIS
        Ordinal (byte-order) sort, matching `sort` under the C locale.

    .NOTES
        Named Get-* because "Sort" is not an approved PowerShell verb --
        Sort-Object predates the verb list and is grandfathered in.

    .DESCRIPTION
        PowerShell's Sort-Object is culture-aware and would order items
        differently from install.sh on some machines; the installers must
        agree so their output can be diffed in CI.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowEmptyCollection()]
        [string[]] $InputObject
    )

    begin { $all = [System.Collections.Generic.List[string]]::new() }
    process { if ($InputObject) { $all.AddRange($InputObject) } }
    end {
        $array = $all.ToArray()
        [System.Array]::Sort($array, [System.StringComparer]::Ordinal)
        , $array
    }
}

function Get-AiForgeChildDirectory {
    <#
    .SYNOPSIS
        Immediate subdirectories of a path, ordinally sorted. Empty when absent.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }
    $dirs = @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName })
    Get-AiForgeOrdinalSort -InputObject $dirs
}

function Test-AiForgeHidden {
    <#
    .SYNOPSIS
        True when a name from THIS repo is superseded by a downstream layer.

    .DESCRIPTION
        Only ai-forge's own items can be hidden; items coming from an extra
        root are always shown (same rule as skill_is_hidden in install.sh).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Name,
        [Parameter(Mandatory)][bool] $IsSelf,
        [AllowNull()][string[]] $HiddenNames
    )

    if (-not $IsSelf) { return $false }
    if (-not $HiddenNames) { return $false }
    $HiddenNames -contains $Name
}

function Add-AiForgeAgentRow {
    <#
    .SYNOPSIS
        Appends every agent found under <Root>/agents to the catalog.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Items,
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][AllowEmptyString()][string] $LabelSuffix,
        [Parameter(Mandatory)][int] $CategoryIndex,
        [Parameter(Mandatory)][bool] $IsSelf,
        [Parameter(Mandatory)][string] $ProjectPath,
        [AllowNull()][string[]] $HiddenAgents
    )

    $agentsRoot = Join-Path $Root 'agents'
    foreach ($subdir in (Get-AiForgeChildDirectory $agentsRoot)) {
        $sub = Split-Path -Leaf $subdir

        $files = @(Get-ChildItem -LiteralPath $subdir -File -Filter '*.md' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName })
        $files = Get-AiForgeOrdinalSort -InputObject $files

        $visible = @($files | Where-Object {
            -not (Test-AiForgeHidden -Name ([System.IO.Path]::GetFileNameWithoutExtension($_)) -IsSelf $IsSelf -HiddenNames $HiddenAgents)
        })
        if ($visible.Count -eq 0) { continue }

        $Items.Add((New-AiForgeItem -Label "$sub$LabelSuffix" -Type 'sub' -Sub $sub -Source $subdir -Parent $CategoryIndex -Depth 1))
        $parentIndex = $Items.Count - 1

        foreach ($file in $visible) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($file)
            $item = New-AiForgeItem -Label $name -Type 'agent' -Sub $sub -Name $name -Source $file -Parent $parentIndex -Depth 2
            $item.Installed = Test-AiForgeAgentInstalled -ProjectPath $ProjectPath -Name $name
            $Items.Add($item)
        }
    }
}

function Add-AiForgeSkillRow {
    <#
    .SYNOPSIS
        Appends every skill found under <Root>/skills to the catalog.

    .DESCRIPTION
        A subfolder either holds one or more SKILL.md bundles (at any depth) or
        is a remote bundle with a reviewed install.args argument list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Items,
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][AllowEmptyString()][string] $LabelSuffix,
        [Parameter(Mandatory)][int] $CategoryIndex,
        [Parameter(Mandatory)][bool] $IsSelf,
        [Parameter(Mandatory)][string] $ProjectPath,
        [AllowNull()][string[]] $HiddenSkills
    )

    $skillsRoot = Join-Path $Root 'skills'
    foreach ($subdir in (Get-AiForgeChildDirectory $skillsRoot)) {
        $sub = Split-Path -Leaf $subdir

        $skillDirs = @(Get-ChildItem -LiteralPath $subdir -File -Filter 'SKILL.md' -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $_.DirectoryName } | Select-Object -Unique)
        $skillDirs = Get-AiForgeOrdinalSort -InputObject $skillDirs

        if ($skillDirs.Count -gt 0) {
            $Items.Add((New-AiForgeItem -Label "$sub$LabelSuffix" -Type 'sub' -Sub $sub -Source $subdir -Parent $CategoryIndex -Depth 1))
            $parentIndex = $Items.Count - 1

            foreach ($dir in $skillDirs) {
                $name = Split-Path -Leaf $dir
                if (Test-AiForgeHidden -Name $name -IsSelf $IsSelf -HiddenNames $HiddenSkills) { continue }
                $item = New-AiForgeItem -Label $name -Type 'skill' -Sub $sub -Name $name -Source $dir -Parent $parentIndex -Depth 2
                $item.Installed = Test-AiForgeSkillInstalled -ProjectPath $ProjectPath -Name $name
                $Items.Add($item)
            }
        } elseif (Test-Path -LiteralPath (Join-Path $subdir 'install.args') -PathType Leaf) {
            $Items.Add((New-AiForgeItem -Label "$sub$LabelSuffix" -Note '(runs an external command)' -Type 'readme' `
                        -Sub $sub -Name $sub -Source $subdir -Parent $CategoryIndex -Depth 1))
        }
    }
}

function Add-AiForgeCommandRow {
    <#
    .SYNOPSIS
        Appends the helper command rows.

    .DESCRIPTION
        `auto-skills` and the Cursor recommendation scan are known to misbehave,
        so they stay visible for discoverability but are marked disabled; the
        summary tells the user to run them by hand instead.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Items,
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][pscustomobject] $Config
    )

    $autoSkills = New-AiForgeItem -Label 'Run `auto-skills` on the project (npx autoskills)' -Type 'cmd' -Name 'auto-skills'
    $autoSkills.Disabled = $true
    $Items.Add($autoSkills)

    $hasCursor = (Test-Path -LiteralPath (Join-Path $ProjectPath '.cursor') -PathType Container) -or
                 (Test-Path -LiteralPath (Join-Path $ProjectPath 'CLAUDE.md') -PathType Leaf)
    if ($hasCursor) {
        $scanCursor = New-AiForgeItem -Label 'Scan Cursor recommendations (agent automation-recommender)' -Type 'cmd' -Name 'scan-cursor-recommendations'
        $scanCursor.Disabled = $true
        $Items.Add($scanCursor)
    }

    $hasClaude = (Test-Path -LiteralPath (Join-Path $ProjectPath '.claude') -PathType Container) -or
                 (Test-Path -LiteralPath (Join-Path $ProjectPath 'CLAUDE.md') -PathType Leaf)
    if ($hasClaude) {
        $Items.Add((New-AiForgeItem -Label 'Scan Claude recommendations (claude automation-recommender)' -Type 'cmd' -Name 'scan-claude-recommendations'))
    }

    $baseMcp = Join-Path $Config.ScriptRoot 'assets/MCPs/mcp.json'
    $hasBase = Test-Path -LiteralPath $baseMcp -PathType Leaf
    if ($hasBase -or $Config.McpOverlay.Count -gt 0) {
        $label = if ($Config.McpOverlay.Count -gt 0) {
            'MCP (merge base + overlay servers -> .agents/mcp/mcp.json)'
        } else {
            'MCP (copy assets/MCPs/mcp.json -> .agents/mcp/)'
        }
        $Items.Add((New-AiForgeItem -Label $label -Type 'cmd' -Name 'install-mcp'))
    }
}

function New-AiForgeCatalog {
    <#
    .SYNOPSIS
        Builds the full catalog for a target project.

    .OUTPUTS
        System.Collections.Generic.List[object] of catalog rows.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Config,
        [Parameter(Mandatory)][string] $ProjectPath
    )

    $items = [System.Collections.Generic.List[object]]::new()

    $items.Add((New-AiForgeItem -Label 'Agents' -Type 'cat'))
    $agentsCategory = $items.Count - 1
    foreach ($root in $Config.ExtraRoots) {
        Add-AiForgeAgentRow -Items $items -Root $root -LabelSuffix $Config.ExtraLabel -CategoryIndex $agentsCategory `
            -IsSelf $false -ProjectPath $ProjectPath -HiddenAgents $Config.HideAgents
    }
    Add-AiForgeAgentRow -Items $items -Root $Config.ScriptRoot -LabelSuffix $Config.SelfLabel -CategoryIndex $agentsCategory `
        -IsSelf $true -ProjectPath $ProjectPath -HiddenAgents $Config.HideAgents

    $items.Add((New-AiForgeItem -Label 'Skills' -Type 'cat'))
    $skillsCategory = $items.Count - 1
    foreach ($root in $Config.ExtraRoots) {
        Add-AiForgeSkillRow -Items $items -Root $root -LabelSuffix $Config.ExtraLabel -CategoryIndex $skillsCategory `
            -IsSelf $false -ProjectPath $ProjectPath -HiddenSkills $Config.HideSkills
    }
    Add-AiForgeSkillRow -Items $items -Root $Config.ScriptRoot -LabelSuffix $Config.SelfLabel -CategoryIndex $skillsCategory `
        -IsSelf $true -ProjectPath $ProjectPath -HiddenSkills $Config.HideSkills

    Add-AiForgeCommandRow -Items $items -ProjectPath $ProjectPath -Config $Config

    , $items
}

Export-ModuleMember -Function @(
    'New-AiForgeItem'
    'Get-AiForgeSkillsDestination'
    'Get-AiForgeAgentsDestination'
    'Test-AiForgeSkillInstalled'
    'Test-AiForgeAgentInstalled'
    'Get-AiForgeOrdinalSort'
    'Get-AiForgeChildDirectory'
    'Test-AiForgeHidden'
    'Add-AiForgeAgentRow'
    'Add-AiForgeSkillRow'
    'Add-AiForgeCommandRow'
    'New-AiForgeCatalog'
)
