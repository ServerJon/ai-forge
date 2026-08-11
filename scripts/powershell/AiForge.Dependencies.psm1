#Requires -Version 5.1

<#
.SYNOPSIS
    External command and MCP server dependency reporting + optional installs.

.DESCRIPTION
    Ports sections 5, 5b, 5c and 5d of install.sh. Availability checks prefer
    the target project's pinned Node (nvm / .nvmrc / .node-version) and Python
    (pyenv / .python-version / .pyenv) toolchains when present. Missing CLIs can
    be installed via curated recipes (--InstallDeps or an end-of-run prompt);
    Node installs use the project's package manager (pnpm/yarn/bun/npm).

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
    'hexagonal-architecture/hexagonal-architecture-testing' = 'python3|python pytest poetry|uv'
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

# Curated install recipes: kind|payload (mirrors cmd_install_recipe in install.sh).
$script:CommandInstallRecipes = @{
    'ctx7'           = 'node-global|ctx7'
    'playwright-cli' = 'node-global|@playwright/cli'
    'playwright'     = 'node-global|@playwright/cli'
    'pytest'         = 'python-pip|pytest'
    'alembic'        = 'python-pip|alembic'
    'gh'             = 'brew|gh'
    'glab'           = 'brew|glab'
    'git'            = 'hint|Install Git from https://git-scm.com/downloads'
    'python3'        = 'hint|Install Python via pyenv (pyenv install <ver>) or https://python.org'
    'python'         = 'hint|Install Python via pyenv (pyenv install <ver>) or https://python.org'
    'poetry'         = 'hint|Install Poetry: https://python-poetry.org/docs/#installation'
    'uv'             = 'hint|Install uv: https://docs.astral.sh/uv/getting-started/installation/'
    'pdm'            = 'hint|Install PDM: https://pdm-project.org/en/latest/#installation'
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

function Get-AiForgeCommandInstallRecipe {
    <#
    .SYNOPSIS
        Returns kind|payload for a concrete binary, or empty when unknown.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $Command)

    if ($script:CommandInstallRecipes.ContainsKey($Command)) {
        return [string] $script:CommandInstallRecipes[$Command]
    }
    ''
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

function Read-AiForgeVersionPin {
    <#
    .SYNOPSIS
        Reads the first non-empty, non-comment line from a version pin file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#')) { continue }
        return $trimmed
    }
    ''
}

function Get-AiForgeNodePackageManager {
    <#
    .SYNOPSIS
        Detects pnpm/yarn/bun/npm for the target project.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $ProjectPath)

    if (Test-Path -LiteralPath (Join-Path $ProjectPath 'pnpm-lock.yaml') -PathType Leaf) { return 'pnpm' }
    if (Test-Path -LiteralPath (Join-Path $ProjectPath 'yarn.lock') -PathType Leaf) { return 'yarn' }
    if ((Test-Path -LiteralPath (Join-Path $ProjectPath 'bun.lockb') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $ProjectPath 'bun.lock') -PathType Leaf)) { return 'bun' }
    if (Test-Path -LiteralPath (Join-Path $ProjectPath 'package-lock.json') -PathType Leaf) { return 'npm' }

    $packageJson = Join-Path $ProjectPath 'package.json'
    if (Test-Path -LiteralPath $packageJson -PathType Leaf) {
        $raw = Get-Content -LiteralPath $packageJson -Raw -ErrorAction SilentlyContinue
        if ($raw -match '"packageManager"\s*:\s*"(?<pm>[^@"\s]+)') {
            $name = $Matches['pm'].ToLowerInvariant()
            if ($name -in @('pnpm', 'yarn', 'bun', 'npm')) { return $name }
        }
    }

    'npm'
}

function New-AiForgeProjectRuntime {
    <#
    .SYNOPSIS
        Resolves project-aware PATH prefix, Node PM, and version labels.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string] $ProjectPath)

    $pathPrefix = [System.Collections.Generic.List[string]]::new()
    $nodeLabel = ''
    $pythonLabel = ''
    $nodePm = Get-AiForgeNodePackageManager -ProjectPath $ProjectPath

    $nodePin = ''
    $nvmrc = Join-Path $ProjectPath '.nvmrc'
    $nodeVersion = Join-Path $ProjectPath '.node-version'
    if (Test-Path -LiteralPath $nvmrc -PathType Leaf) {
        $nodePin = Read-AiForgeVersionPin -Path $nvmrc
        if ($nodePin) { $nodeLabel = "$nodePin (.nvmrc)" }
    } elseif (Test-Path -LiteralPath $nodeVersion -PathType Leaf) {
        $nodePin = Read-AiForgeVersionPin -Path $nodeVersion
        if ($nodePin) { $nodeLabel = "$nodePin (.node-version)" }
    }

    if ($nodePin) {
        $activated = $false
        $nvmDir = if ($env:NVM_DIR) { $env:NVM_DIR } else { Join-Path $HOME '.nvm' }
        $nvmSh = Join-Path $nvmDir 'nvm.sh'
        # POSIX nvm via bash (Git Bash / WSL / macOS / Linux).
        if ((Test-Path -LiteralPath $nvmSh -PathType Leaf) -and (Get-Command bash -ErrorAction SilentlyContinue)) {
            $probe = & bash -lc "export NVM_DIR='$nvmDir'; . \"`$NVM_DIR/nvm.sh\"; nvm use '$nodePin' >/dev/null 2>&1 && command -v node && npm prefix -g" 2>$null
            $lines = @($probe | Where-Object { $_ })
            if ($lines.Count -ge 1 -and (Test-Path -LiteralPath $lines[0] -PathType Leaf)) {
                $pathPrefix.Add([System.IO.Path]::GetDirectoryName($lines[0]))
                if ($lines.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($lines[1])) {
                    $pathPrefix.Add((Join-Path $lines[1].Trim() 'bin'))
                }
                $activated = $true
                Write-AiForgeOk "Using Node $nodePin from nvm for dependency checks/installs."
            }
        }

        # nvm-windows: NVM_HOME\vX.Y.Z
        if (-not $activated -and $env:NVM_HOME) {
            $candidates = @(
                (Join-Path $env:NVM_HOME "v$nodePin")
                (Join-Path $env:NVM_HOME $nodePin)
            )
            foreach ($candidate in $candidates) {
                $nodeExe = Join-Path $candidate 'node.exe'
                if (Test-Path -LiteralPath $nodeExe -PathType Leaf) {
                    $pathPrefix.Add($candidate)
                    $activated = $true
                    Write-AiForgeOk "Using Node $nodePin from nvm-windows for dependency checks/installs."
                    break
                }
            }
        }

        if (-not $activated) {
            Write-AiForgeWarning "Project pins Node $nodePin but that version was not activated; using the current PATH."
        }
    }

    $pythonPin = ''
    $pythonVersion = Join-Path $ProjectPath '.python-version'
    $pyenvFile = Join-Path $ProjectPath '.pyenv'
    if (Test-Path -LiteralPath $pythonVersion -PathType Leaf) {
        $pythonPin = Read-AiForgeVersionPin -Path $pythonVersion
        if ($pythonPin) { $pythonLabel = "$pythonPin (.python-version)" }
    } elseif (Test-Path -LiteralPath $pyenvFile -PathType Leaf) {
        $pythonPin = Read-AiForgeVersionPin -Path $pyenvFile
        if ($pythonPin) { $pythonLabel = "$pythonPin (.pyenv)" }
    }

    if ($pythonPin -and (Get-Command pyenv -ErrorAction SilentlyContinue)) {
        $previous = $env:PYENV_VERSION
        $env:PYENV_VERSION = $pythonPin
        try {
            $py = & pyenv which python 2>$null
            if (-not $py) { $py = & pyenv which python3 2>$null }
            if ($py -and (Test-Path -LiteralPath "$py" -PathType Leaf)) {
                $pathPrefix.Add([System.IO.Path]::GetDirectoryName("$py"))
                Write-AiForgeOk "Using Python $pythonPin from pyenv for dependency checks/installs."
            } else {
                Write-AiForgeWarning "Project pins Python $pythonPin but that version is not installed in pyenv; using the current PATH."
            }
        } finally {
            if ($null -eq $previous) {
                Remove-Item Env:PYENV_VERSION -ErrorAction SilentlyContinue
            } else {
                $env:PYENV_VERSION = $previous
            }
        }
    } elseif ($pythonPin) {
        Write-AiForgeWarning "Project pins Python $pythonPin but pyenv was not found; using the current PATH."
    }

    $hasPackageJson = Test-Path -LiteralPath (Join-Path $ProjectPath 'package.json') -PathType Leaf
    if ($hasPackageJson -or $nodePm -ne 'npm') {
        Write-AiForgeInfo "Node package manager for this project: $nodePm"
    }

    [pscustomobject]@{
        ProjectPath        = $ProjectPath
        PathPrefix         = @($pathPrefix | Select-Object -Unique)
        NodePackageManager = $nodePm
        NodeVersionLabel   = $nodeLabel
        PythonVersionLabel = $pythonLabel
    }
}

function Get-AiForgeRuntimePath {
    <#
    .SYNOPSIS
        Builds a PATH string with the project runtime directories prepended.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][pscustomobject] $Runtime)

    $parts = @()
    if ($Runtime.PathPrefix) { $parts += @($Runtime.PathPrefix) }
    $parts += ($env:PATH -split [System.IO.Path]::PathSeparator)
    ($parts | Where-Object { $_ } | Select-Object -Unique) -join [System.IO.Path]::PathSeparator
}

function Test-AiForgeCommandAvailable {
    <#
    .SYNOPSIS
        The equivalent of `command -v <name>`, optionally project-PATH aware.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $Name,
        [pscustomobject] $Runtime
    )

    if ($Runtime) {
        $previous = $env:PATH
        $env:PATH = Get-AiForgeRuntimePath -Runtime $Runtime
        try {
            return [bool] (Get-Command -Name $Name -ErrorAction SilentlyContinue)
        } finally {
            $env:PATH = $previous
        }
    }

    [bool] (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Resolve-AiForgeDependencyToken {
    <#
    .SYNOPSIS
        Resolves one token (possibly "a|b|c") into a display string and status.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Token,
        [pscustomobject] $Runtime
    )

    $alternatives = @($Token -split '\|' | Where-Object { $_ })
    $found = $null
    foreach ($alternative in $alternatives) {
        if (Test-AiForgeCommandAvailable -Name $alternative -Runtime $Runtime) {
            $found = $alternative
            break
        }
    }

    [pscustomobject]@{
        Token       = $Token
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
    param(
        [Parameter(Mandatory)][pscustomobject] $Selection,
        [pscustomobject] $Runtime
    )

    $rows = [System.Collections.Generic.List[object]]::new()

    $lookups = @()
    foreach ($skill in $Selection.Skills)  { $lookups += , @($skill.Name,  "$($skill.Sub)/$($skill.Name)") }
    foreach ($remote in $Selection.Remote) { $lookups += , @($remote.Name, "$($remote.Name)/$($remote.Name)") }
    foreach ($agent in $Selection.Agents)  { $lookups += , @($agent.Name,  "agent/$($agent.Name)") }

    foreach ($lookup in $lookups) {
        foreach ($token in (Get-AiForgeCommandDependency -Key $lookup[1])) {
            $resolved = Resolve-AiForgeDependencyToken -Token $token -Runtime $Runtime
            $rows.Add([pscustomobject]@{
                Item        = $lookup[0]
                Token       = $resolved.Token
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
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Rows,
        [pscustomobject] $Runtime
    )

    if ($Rows.Count -eq 0) { return }

    $itemWidth = [Math]::Max(4, ($Rows | ForEach-Object { $_.Item.Length } | Measure-Object -Maximum).Maximum)
    $reqWidth = [Math]::Max(7, ($Rows | ForEach-Object { $_.Requirement.Length } | Measure-Object -Maximum).Maximum)

    Write-AiForgeHeading 'External command dependencies:'
    $runtimeNote = @()
    if ($Runtime -and $Runtime.NodeVersionLabel) { $runtimeNote += "Node $($Runtime.NodeVersionLabel)" }
    if ($Runtime -and $Runtime.PythonVersionLabel) { $runtimeNote += "Python $($Runtime.PythonVersionLabel)" }
    if ($runtimeNote.Count -gt 0) {
        Write-AiForgeText ("(checked against project runtime; {0})" -f ($runtimeNote -join '; ')) -Color DarkGray
    }
    Write-AiForgeText '(use -InstallDeps or confirm the prompt below to install curated missing tools)' -Color DarkGray
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

function Get-AiForgeNodeGlobalInstallArgument {
    <#
    .SYNOPSIS
        Builds argv for a global Node package install via the project PM.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string] $Package,
        [Parameter(Mandatory)][string] $PackageManager
    )

    switch ($PackageManager) {
        'pnpm' { return @('pnpm', 'add', '-g', $Package) }
        'yarn' { return @('yarn', 'global', 'add', $Package) }
        'bun'  { return @('bun', 'add', '-g', $Package) }
        default { return @('npm', 'install', '-g', $Package) }
    }
}

function Select-AiForgeInstallCandidate {
    <#
    .SYNOPSIS
        Picks which binary to install for a token (possibly a|b).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Token,
        [pscustomobject] $Runtime
    )

    $alternatives = @($Token -split '\|' | Where-Object { $_ })
    foreach ($alt in $alternatives) {
        if (Test-AiForgeCommandAvailable -Name $alt -Runtime $Runtime) { return '' }
    }
    foreach ($alt in $alternatives) {
        $recipe = Get-AiForgeCommandInstallRecipe -Command $alt
        if ($recipe -and -not $recipe.StartsWith('hint|')) { return $alt }
    }
    if ($alternatives.Count -gt 0) { return $alternatives[0] }
    ''
}

function Install-AiForgeDependency {
    <#
    .SYNOPSIS
        Installs one concrete CLI via its curated recipe.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $Command,
        [Parameter(Mandatory)][pscustomobject] $Context,
        [Parameter(Mandatory)][pscustomobject] $Runtime
    )

    $recipe = Get-AiForgeCommandInstallRecipe -Command $Command
    if ([string]::IsNullOrWhiteSpace($recipe)) {
        Write-AiForgeWarning "No install recipe for '$Command' -- install it manually."
        return $false
    }

    $parts = $recipe.Split('|', 2)
    $kind = $parts[0]
    $payload = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    $argv = @()
    $pm = $Runtime.NodePackageManager

    switch ($kind) {
        'hint' {
            Write-AiForgeInfo "Install hint for ${Command}: $payload"
            return $false
        }
        'node-global' {
            if (-not (Test-AiForgeCommandAvailable -Name node -Runtime $Runtime) -and
                -not (Test-AiForgeCommandAvailable -Name npm -Runtime $Runtime)) {
                Write-AiForgeWarning "Node.js is required to install '$Command' but was not found on PATH."
                return $false
            }
            if (-not (Test-AiForgeCommandAvailable -Name $pm -Runtime $Runtime)) {
                Write-AiForgeWarning "Package manager '$pm' not found; falling back to npm for '$Command'."
                $pm = 'npm'
            }
            $argv = @(Get-AiForgeNodeGlobalInstallArgument -Package $payload -PackageManager $pm)
        }
        'python-pip' {
            $py = $null
            if (Test-AiForgeCommandAvailable -Name python3 -Runtime $Runtime) { $py = 'python3' }
            elseif (Test-AiForgeCommandAvailable -Name python -Runtime $Runtime) { $py = 'python' }
            if (-not $py) {
                Write-AiForgeWarning "Python is required to install '$Command' but was not found on PATH."
                return $false
            }
            $argv = @($py, '-m', 'pip', 'install', '--user', $payload)
        }
        'brew' {
            if (-not (Get-Command brew -ErrorAction SilentlyContinue)) {
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    $id = if ($payload -eq 'gh') { 'GitHub.cli' } elseif ($payload -eq 'glab') { 'GLab.GLab' } else { $payload }
                    $argv = @('winget', 'install', '-e', '--id', $id)
                } else {
                    Write-AiForgeWarning "'brew' not found -- install '$Command' manually (e.g. from the vendor docs)."
                    return $false
                }
            } else {
                $argv = @('brew', 'install', $payload)
            }
        }
        default {
            Write-AiForgeWarning "Unknown install kind '$kind' for '$Command'."
            return $false
        }
    }

    $display = ($argv | ForEach-Object {
        if ($_ -match '\s') { "'$_'" } else { $_ }
    }) -join ' '

    if ($Context.DryRun) {
        Write-AiForgeDry "Would install dependency '$Command': $display"
        $Context.RanCommands.Add("dep:${Command}: $display (skipped: dry-run)")
        return $true
    }

    Write-AiForgeInfo "Install command for '${Command}': $display"
    if (-not $Context.AssumeYes) {
        $answer = Read-Host 'Run this install command? [y/N]'
        if ($answer -notin @('y', 'Y', 'yes', 'YES')) {
            Write-AiForgeWarning "Skipped install for '$Command'."
            $Context.RanCommands.Add("dep:${Command}: $display (skipped: not confirmed)")
            return $false
        }
    }

    $previous = $env:PATH
    $env:PATH = Get-AiForgeRuntimePath -Runtime $Runtime
    $exitCode = 0
    try {
        Push-Location -LiteralPath $Context.ProjectPath
        try {
            & $argv[0] @($argv | Select-Object -Skip 1)
            if ($null -ne $LASTEXITCODE) { $exitCode = $LASTEXITCODE }
        } finally {
            Pop-Location
        }
    } finally {
        $env:PATH = $previous
    }

    if ($exitCode -eq 0) {
        Write-AiForgeOk "Installed dependency: $Command"
        $Context.RanCommands.Add("dep:${Command}: $display")
        return $true
    }

    Write-AiForgeWarning "Install command failed for '$Command'."
    $false
}

function Install-AiForgeMissingDependency {
    <#
    .SYNOPSIS
        Offers / runs curated installs for missing dependency rows.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Rows,
        [Parameter(Mandatory)][pscustomobject] $Runtime,
        [Parameter(Mandatory)][pscustomobject] $Selection
    )

    $missing = @($Rows | Where-Object { -not $_.Available })
    if ($missing.Count -eq 0) { return , $Rows }

    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $missing) {
        $token = if ($row.PSObject.Properties['Token']) { $row.Token } else { ($row.Requirement -replace ' or ', '|') }
        if ($tokens -notcontains $token) { $tokens.Add($token) }
    }

    $doInstall = $false
    if ($Context.InstallDeps) {
        $doInstall = $true
    } elseif ($Context.DryRun) {
        return , $Rows
    } elseif ((Test-AiForgeInteractive) -and -not $Context.AssumeYes) {
        $answer = Read-Host 'Install missing dependencies now (curated recipes only)? [y/N]'
        $doInstall = $answer -in @('y', 'Y', 'yes', 'YES')
    } else {
        # Non-interactive / -Yes without -InstallDeps: report only (do not hang CI).
        if (-not $Context.AssumeYes) {
            Write-AiForgeInfo 'Missing dependencies detected. Re-run with -InstallDeps (and -Yes if unattended) to install curated tools.'
        } else {
            Write-AiForgeInfo 'Missing dependencies detected. Re-run with -InstallDeps to install curated tools (-Yes alone does not install them).'
        }
        return , $Rows
    }

    if (-not $doInstall) { return , $Rows }

    Write-AiForgeText ''
    Write-AiForgeHeading 'Installing missing dependencies...'
    $attempted = $false
    foreach ($token in $tokens) {
        $candidate = Select-AiForgeInstallCandidate -Token $token -Runtime $Runtime
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $attempted = $true
        [void] (Install-AiForgeDependency -Command $candidate -Context $Context -Runtime $Runtime)
    }

    if (-not $attempted) { return , $Rows }

    $updated = New-AiForgeDependencyTable -Selection $Selection -Runtime $Runtime
    Write-AiForgeText ''
    Write-AiForgeHeading 'Updated dependency status:'
    Write-AiForgeDependencyTable -Rows $updated -Runtime $Runtime
    , $updated
}

Export-ModuleMember -Function @(
    'Get-AiForgeCommandDependency'
    'Get-AiForgeMcpDependency'
    'Get-AiForgeSkillDependency'
    'Get-AiForgeCommandInstallRecipe'
    'Get-AiForgeUnmetDependency'
    'Read-AiForgeVersionPin'
    'Get-AiForgeNodePackageManager'
    'New-AiForgeProjectRuntime'
    'Get-AiForgeRuntimePath'
    'Test-AiForgeCommandAvailable'
    'Resolve-AiForgeDependencyToken'
    'New-AiForgeDependencyTable'
    'Get-AiForgeMcpConfigFile'
    'Test-AiForgeMcpConfigured'
    'New-AiForgeMcpTable'
    'Write-AiForgeDependencyTable'
    'Write-AiForgeMcpTable'
    'Get-AiForgeNodeGlobalInstallArgument'
    'Select-AiForgeInstallCandidate'
    'Install-AiForgeDependency'
    'Install-AiForgeMissingDependency'
)
