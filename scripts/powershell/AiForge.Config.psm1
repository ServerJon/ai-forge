#Requires -Version 5.1

<#
.SYNOPSIS
    Path resolution and layered configuration for the ai-forge installer.

.DESCRIPTION
    Ports section 1/1b of install.sh: target path validation, `--extra` project
    resolution and the AIFORGE_* settings that a downstream project can supply
    through its .ai-forge.env file.

    The bash installer sources .ai-forge.env as a shell snippet. PowerShell
    cannot do that, so this module parses the documented subset instead: plain
    KEY=value assignments (optionally prefixed with `export`), with single or
    double quotes and $VAR / ${VAR} references to already-known settings.
    Anything else is reported and ignored rather than silently misread.
#>

Set-StrictMode -Version Latest

$script:ExtraConfigFileName = '.ai-forge.env'

# Settings a .ai-forge.env file (or the environment) may define.
$script:KnownSettings = @(
    'AIFORGE_EXTRA_ROOTS'
    'AIFORGE_EXTRA_LABEL'
    'AIFORGE_SELF_LABEL'
    'AIFORGE_HIDE_SKILLS'
    'AIFORGE_HIDE_AGENTS'
    'AIFORGE_MCP_OVERLAY'
    'AIFORGE_AGENTS_TEMPLATE'
)

function Get-AiForgeExtraConfigFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $script:ExtraConfigFileName
}

function ConvertTo-AiForgeNativePath {
    <#
    .SYNOPSIS
        Accepts the path spellings a user is likely to paste and returns a
        native one.

    .DESCRIPTION
        Handles `~`, MSYS/Git Bash paths (/c/Users/...) and WSL paths
        (/mnt/c/Users/...) so a Windows user can copy a path from any shell
        they happen to have open. Non-Windows hosts are left untouched apart
        from `~` expansion.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $result = $Path.Trim()

    if ($result -eq '~') {
        return $HOME
    }
    if ($result.StartsWith('~/') -or $result.StartsWith('~\')) {
        return Join-Path $HOME $result.Substring(2)
    }

    # Only rewrite POSIX-looking drive paths when we are actually on Windows.
    # Deliberately not named $isWindows: that is a read-only automatic variable
    # on PowerShell 6+, and variable names are case-insensitive.
    $onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    if ($onWindows) {
        if ($result -match '^/mnt/([a-zA-Z])/(.*)$') {
            $result = '{0}:\{1}' -f $Matches[1].ToUpperInvariant(), $Matches[2]
        } elseif ($result -match '^/([a-zA-Z])/(.*)$') {
            $result = '{0}:\{1}' -f $Matches[1].ToUpperInvariant(), $Matches[2]
        }
        $result = $result -replace '/', '\'
    }

    $result
}

function Resolve-AiForgeDirectory {
    <#
    .SYNOPSIS
        Normalises a user-supplied directory path and asserts that it exists.

    .PARAMETER Description
        Used in the error message, e.g. "Project path" or "Extra project".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Description
    )

    $native = ConvertTo-AiForgeNativePath -Path $Path
    if ([string]::IsNullOrWhiteSpace($native)) {
        throw "$Description is empty."
    }
    if (-not (Test-Path -LiteralPath $native -PathType Container)) {
        throw "$Description does not exist or is not a directory: $native"
    }

    (Resolve-Path -LiteralPath $native).ProviderPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
}

function ConvertFrom-AiForgeEnvFile {
    <#
    .SYNOPSIS
        Parses the supported subset of a .ai-forge.env shell snippet.

    .PARAMETER Path
        The .ai-forge.env file to read.

    .PARAMETER Seed
        Variables already known to the parser (for example AIFORGE_EXTRA_ROOT,
        which the bash installer exports before sourcing the file).

    .OUTPUTS
        Hashtable of variable name -> value.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [hashtable] $Seed = @{}
    )

    $values = @{}
    foreach ($key in $Seed.Keys) { $values[$key] = $Seed[$key] }

    $lineNumber = 0
    foreach ($rawLine in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $lineNumber++
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
        if ($line.StartsWith('export ')) { $line = $line.Substring(7).Trim() }

        $match = [regex]::Match($line, '^(?<name>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$')
        if (-not $match.Success) {
            Write-Warning "Ignored unsupported line $lineNumber in ${Path}: $rawLine"
            continue
        }

        $name = $match.Groups['name'].Value
        $value = $match.Groups['value'].Value.Trim()

        # Strip a trailing inline comment on unquoted values only.
        if (-not ($value.StartsWith('"') -or $value.StartsWith("'"))) {
            $value = ($value -replace '\s+#.*$', '').Trim()
        }

        $singleQuoted = $value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2
        if ($singleQuoted) {
            $value = $value.Substring(1, $value.Length - 2)
        } elseif ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        # Single quotes are literal in shell; everything else expands $VAR refs.
        if (-not $singleQuoted) {
            $value = [regex]::Replace($value, '\$\{?(?<ref>[A-Za-z_][A-Za-z0-9_]*)\}?', {
                param($m)
                $refName = $m.Groups['ref'].Value
                if ($values.ContainsKey($refName)) { [string]$values[$refName] } else { '' }
            })
        }

        $values[$name] = $value
    }

    $values
}

function Split-AiForgeList {
    <#
    .SYNOPSIS
        Splits a space-separated shell-style list into a string array.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Value
    )

    # Emitted unwrapped so the result enumerates naturally in foreach and
    # pipelines. Callers that need .Count wrap the call in @().
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    @($Value -split '\s+' | Where-Object { $_ -ne '' })
}

function Get-AiForgeSetting {
    <#
    .SYNOPSIS
        Reads a settings key, returning an empty string when it is absent.

    .DESCRIPTION
        Keeps call sites readable under Set-StrictMode, where the behaviour of
        indexing a missing hashtable key differs between PowerShell versions.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Settings,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($Settings.ContainsKey($Name)) { [string]$Settings[$Name] } else { '' }
}

function New-AiForgeConfig {
    <#
    .SYNOPSIS
        Builds the effective installer configuration.

    .DESCRIPTION
        Precedence matches install.sh: process environment first, then the
        extra project's .ai-forge.env, then the defaults implied by -Extra
        (its root joins the scan roots, its assets/MCPs/mcp.json becomes the
        MCP overlay when the config did not set one).

    .PARAMETER ScriptRoot
        Absolute path of the ai-forge repository.

    .PARAMETER ExtraProject
        Optional already-resolved path of the project to layer on top.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $ScriptRoot,

        [string] $ExtraProject
    )

    $settings = @{}
    foreach ($name in $script:KnownSettings) {
        $envValue = [System.Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($envValue)) { $settings[$name] = $envValue }
    }

    $configFile = $null
    if ($ExtraProject) {
        $configFile = Join-Path $ExtraProject $script:ExtraConfigFileName
        if (Test-Path -LiteralPath $configFile -PathType Leaf) {
            $seed = @{ AIFORGE_EXTRA_ROOT = $ExtraProject }
            foreach ($key in $settings.Keys) { $seed[$key] = $settings[$key] }
            $parsed = ConvertFrom-AiForgeEnvFile -Path $configFile -Seed $seed
            foreach ($name in $script:KnownSettings) {
                if ($parsed.ContainsKey($name)) { $settings[$name] = $parsed[$name] }
            }
        } else {
            $configFile = $null
        }
    }

    $extraRoots = [System.Collections.Generic.List[string]]::new()
    if ($ExtraProject) { $extraRoots.Add($ExtraProject) }
    foreach ($root in (Split-AiForgeList (Get-AiForgeSetting $settings 'AIFORGE_EXTRA_ROOTS'))) {
        if (-not $extraRoots.Contains($root)) { $extraRoots.Add($root) }
    }

    $mcpOverlay = @(Split-AiForgeList (Get-AiForgeSetting $settings 'AIFORGE_MCP_OVERLAY'))
    if ($mcpOverlay.Count -eq 0 -and $ExtraProject) {
        $candidate = Join-Path $ExtraProject 'assets/MCPs/mcp.json'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $mcpOverlay = @($candidate) }
    }

    $agentsTemplate = Get-AiForgeSetting $settings 'AIFORGE_AGENTS_TEMPLATE'
    if ([string]::IsNullOrWhiteSpace($agentsTemplate)) {
        $agentsTemplate = Join-Path $ScriptRoot 'AGENTS.template.md'
    }

    [pscustomobject]@{
        ScriptRoot     = $ScriptRoot
        ExtraProject   = $ExtraProject
        ConfigFile     = $configFile
        ExtraRoots     = @($extraRoots)
        ExtraLabel     = Get-AiForgeSetting $settings 'AIFORGE_EXTRA_LABEL'
        SelfLabel      = Get-AiForgeSetting $settings 'AIFORGE_SELF_LABEL'
        HideSkills     = @(Split-AiForgeList (Get-AiForgeSetting $settings 'AIFORGE_HIDE_SKILLS'))
        HideAgents     = @(Split-AiForgeList (Get-AiForgeSetting $settings 'AIFORGE_HIDE_AGENTS'))
        McpOverlay     = @($mcpOverlay)
        AgentsTemplate = $agentsTemplate
    }
}

Export-ModuleMember -Function @(
    'Get-AiForgeExtraConfigFileName'
    'ConvertTo-AiForgeNativePath'
    'Resolve-AiForgeDirectory'
    'ConvertFrom-AiForgeEnvFile'
    'Split-AiForgeList'
    'Get-AiForgeSetting'
    'New-AiForgeConfig'
)
