#Requires -Version 5.1

<#
.SYNOPSIS
    Performs the installation: copying skills/agents, running helper commands
    and dropping AGENTS.md into the target project.

.DESCRIPTION
    Ports sections 4, 6, 7 and 8 of install.sh.

    One deliberate improvement over the bash version: merging MCP configs is
    done with the built-in JSON parser, so Windows users do not need jq for a
    complete `--extra` install.
#>

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'AiForge.Console.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AiForge.Catalog.psm1') -DisableNameChecking

function New-AiForgeInstallContext {
    <#
    .SYNOPSIS
        Creates the mutable state shared by the install steps and the summary.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][pscustomobject] $Config,
        [Parameter(Mandatory)][pscustomobject] $Selection,
        [bool] $DryRun = $false
    )

    [pscustomobject]@{
        ProjectPath     = $ProjectPath
        Config          = $Config
        Selection       = $Selection
        DryRun          = $DryRun
        InstalledSkills = [System.Collections.Generic.List[string]]::new()
        InstalledAgents = [System.Collections.Generic.List[string]]::new()
        RanCommands     = [System.Collections.Generic.List[string]]::new()
        SpecialNotes    = [System.Collections.Generic.List[string]]::new()
        DroppedItems    = [System.Collections.Generic.List[string]]::new()
        AgentsMdCopied  = $false
    }
}

function Get-AiForgeSelection {
    <#
    .SYNOPSIS
        Turns checked catalog rows into concrete install actions.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Collections.Generic.List[object]] $Items)

    $skills = [System.Collections.Generic.List[object]]::new()
    $agents = [System.Collections.Generic.List[object]]::new()
    $remote = [System.Collections.Generic.List[object]]::new()
    $commands = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $Items) {
        if (-not $item.Checked -or $item.Installed) { continue }
        switch ($item.Type) {
            'skill'  { $skills.Add([pscustomobject]@{ Name = $item.Name; Source = $item.Source; Sub = $item.Sub }) }
            'agent'  { $agents.Add([pscustomobject]@{ Name = $item.Name; Source = $item.Source; Sub = $item.Sub }) }
            'readme' { $remote.Add([pscustomobject]@{ Name = $item.Name; Source = $item.Source; Sub = $item.Sub }) }
            'cmd'    { $commands.Add($item.Name) }
        }
    }

    [pscustomobject]@{
        Skills   = @($skills)
        Agents   = @($agents)
        Remote   = @($remote)
        Commands = @($commands)
        Total    = $skills.Count + $agents.Count + $remote.Count + $commands.Count
    }
}

function Get-AiForgeCodeBlock {
    <#
    .SYNOPSIS
        Returns the first fenced code block of a given language in a markdown file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Language
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }

    $fence = '```' + $Language
    $inBlock = $false
    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if (-not $inBlock) {
            if ($line.TrimEnd() -eq $fence) { $inBlock = $true }
            continue
        }
        if ($line.TrimEnd() -eq '```') { break }
        $lines.Add($line)
    }

    $lines -join [System.Environment]::NewLine
}

function Install-AiForgeSkill {
    <#
    .SYNOPSIS
        Copies a whole skill directory into <project>/.agents/skills/<name>/.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][pscustomobject] $Context,
        [Parameter(Mandatory)][pscustomobject] $Skill
    )

    $destination = Join-Path (Get-AiForgeSkillsDestination $Context.ProjectPath) $Skill.Name

    if ($Context.DryRun) {
        Write-AiForgeDry "Would install skill: $($Skill.Name) -> $destination/"
    } elseif ($PSCmdlet.ShouldProcess($destination, 'install skill')) {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -Path (Join-Path $Skill.Source '*') -Destination $destination -Recurse -Force
        Write-AiForgeOk "Installed skill: $($Skill.Name)"
    }

    $Context.InstalledSkills.Add($Skill.Name)
}

function Install-AiForgeAgent {
    <#
    .SYNOPSIS
        Copies a single agent definition into <project>/.agents/agents/.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][pscustomobject] $Context,
        [Parameter(Mandatory)][pscustomobject] $Agent
    )

    $destinationDir = Get-AiForgeAgentsDestination $Context.ProjectPath
    $destination = Join-Path $destinationDir ("$($Agent.Name).md")

    if ($Context.DryRun) {
        Write-AiForgeDry "Would install agent: $($Agent.Name) -> $destination"
    } elseif ($PSCmdlet.ShouldProcess($destination, 'install agent')) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        Copy-Item -LiteralPath $Agent.Source -Destination $destination -Force
        Write-AiForgeOk "Installed agent: $($Agent.Name)"
    }

    $Context.InstalledAgents.Add($Agent.Name)
}

function Invoke-AiForgeReadmeSkill {
    <#
    .SYNOPSIS
        Runs the install command published in a remote skill bundle's README.md.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][pscustomobject] $Context,
        [Parameter(Mandatory)][pscustomobject] $Skill
    )

    $block = Get-AiForgeCodeBlock -Path (Join-Path $Skill.Source 'README.md') -Language 'bash'
    $command = ($block -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)

    if (-not $command) {
        Write-AiForgeWarning "No install command found in $($Skill.Source)/README.md for '$($Skill.Name)'. Skipping."
        return
    }

    if ($Context.DryRun) {
        Write-AiForgeDry "Would run README install for '$($Skill.Name)': $command"
        $binary = ($command -split '\s+')[0]
        if (-not (Get-Command -Name $binary -ErrorAction SilentlyContinue)) {
            Write-AiForgeWarning "'$binary' not found; this step would fail on a real run."
        }
        $Context.RanCommands.Add("$($Skill.Name): $command (skipped: dry-run)")
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Context.ProjectPath, "run: $command")) { return }

    Write-AiForgeInfo "Installing '$($Skill.Name)' via README command: $command"
    Push-Location -LiteralPath $Context.ProjectPath
    try {
        # The README publishes a shell command to run verbatim, so this has to
        # go through Invoke-Expression rather than a parsed argument list.
        Invoke-Expression $command
        # A pure-PowerShell command leaves $LASTEXITCODE untouched; treat the
        # absence of an exit code as success.
        $exitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    } catch {
        Write-AiForgeWarning "README install command failed for '$($Skill.Name)': $($_.Exception.Message)"
        return
    } finally {
        Pop-Location
    }

    if ($exitCode -eq 0) {
        Write-AiForgeOk "Ran README install for: $($Skill.Name)"
        $Context.RanCommands.Add("$($Skill.Name): $command")
    } else {
        Write-AiForgeWarning "README install command failed for '$($Skill.Name)' (exit $exitCode)."
    }
}

function Complete-AiForgeRecommendation {
    <#
    .SYNOPSIS
        Validates the output of a recommendation scan.

    .DESCRIPTION
        Some CLIs exit non-zero AND write their error into stdout, so a
        redirected file can look generated while holding an auth failure. On
        failure the raw output is kept as <file>.error.md and no "review this
        file" note is added.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][pscustomobject] $Context,
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][string] $FileName,
        [Parameter(Mandatory)][int] $ExitCode,
        [Parameter(Mandatory)][string] $Hint
    )

    $path = Join-Path $Context.ProjectPath $FileName
    $failed = $ExitCode -ne 0

    if (-not $failed) {
        $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $item -or $item.Length -eq 0) {
            $failed = $true
        } else {
            $content = Get-Content -LiteralPath $path -Raw
            if ($content -imatch 'failed to authenticate|invalid authentication|not authenticated|unauthorized|api error:? *40[0-9]') {
                $failed = $true
            }
        }
    }

    if ($failed) {
        $errorFile = ($FileName -replace '\.md$', '') + '.error.md'
        $errorPath = Join-Path $Context.ProjectPath $errorFile
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Move-Item -LiteralPath $path -Destination $errorPath -Force -ErrorAction SilentlyContinue
        }
        Write-AiForgeWarning "$Label failed (CLI exit $ExitCode). This is usually an authentication problem."
        Write-AiForgeWarning "  Fix: $Hint"
        if (Test-Path -LiteralPath $errorPath -PathType Leaf) {
            Write-AiForgeWarning "  Raw output kept at $errorPath"
        }
        $Context.RanCommands.Add("${Label}: FAILED -- see $errorFile")
        return $false
    }

    $Context.RanCommands.Add("${Label}: $FileName generated")
    $Context.SpecialNotes.Add("Review $path and re-run the installer for any suggested skills.")
    $true
}

function Test-AiForgeJsonObject {
    <#
    .SYNOPSIS
        True when a value is a JSON object (as opposed to a scalar or array).

    .DESCRIPTION
        Merging walks values that came from ConvertFrom-Json (PSCustomObject)
        as well as the ordered dictionaries this module produces, so both
        shapes have to be recognised.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] $Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [string] -or $Value -is [array] -or $Value -is [System.ValueType]) { return $false }
    ($Value -is [System.Collections.IDictionary]) -or ($Value -is [System.Management.Automation.PSCustomObject])
}

function Get-AiForgeJsonEntry {
    <#
    .SYNOPSIS
        Yields the name/value pairs of a JSON object, whatever its shape.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([AllowNull()] $Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IDictionary]) {
        return @(foreach ($key in @($Value.Keys)) { [pscustomobject]@{ Name = $key; Value = $Value[$key] } })
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        return @(foreach ($property in $Value.PSObject.Properties) { [pscustomobject]@{ Name = $property.Name; Value = $property.Value } })
    }
    @()
}

function Merge-AiForgeJsonObject {
    <#
    .SYNOPSIS
        Deep-merges two objects parsed from JSON; values from $Overlay win.

    .DESCRIPTION
        Reproduces jq's `*` operator, which install.sh uses to combine MCP
        server maps. Accepts $null on either side so callers can fold a list
        of sources starting from nothing.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [AllowNull()] $Base,
        [AllowNull()] $Overlay
    )

    $result = [ordered]@{}
    foreach ($entry in (Get-AiForgeJsonEntry -Value $Base)) {
        $result[$entry.Name] = $entry.Value
    }
    foreach ($entry in (Get-AiForgeJsonEntry -Value $Overlay)) {
        $existing = if ($result.Contains($entry.Name)) { $result[$entry.Name] } else { $null }
        if ((Test-AiForgeJsonObject $existing) -and (Test-AiForgeJsonObject $entry.Value)) {
            $result[$entry.Name] = Merge-AiForgeJsonObject -Base $existing -Overlay $entry.Value
        } else {
            $result[$entry.Name] = $entry.Value
        }
    }
    $result
}

function Get-AiForgeMcpSource {
    <#
    .SYNOPSIS
        Ordered MCP sources: this repo's base config first, then overlays.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][pscustomobject] $Config)

    $sources = [System.Collections.Generic.List[string]]::new()
    $base = Join-Path $Config.ScriptRoot 'assets/MCPs/mcp.json'
    if (Test-Path -LiteralPath $base -PathType Leaf) { $sources.Add($base) }
    foreach ($overlay in $Config.McpOverlay) {
        if (Test-Path -LiteralPath $overlay -PathType Leaf) { $sources.Add($overlay) }
    }
    , $sources.ToArray()
}

function Install-AiForgeMcpConfig {
    <#
    .SYNOPSIS
        Copies or merges the MCP server configuration into the project.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][pscustomobject] $Context)

    $sources = Get-AiForgeMcpSource -Config $Context.Config
    if ($sources.Count -eq 0) {
        Write-AiForgeWarning 'No MCP config found (base or overlay); skipping.'
        return
    }

    $destinationDir = Join-Path $Context.ProjectPath '.agents/mcp'
    $destination = Join-Path $destinationDir 'mcp.json'

    if ($Context.DryRun) {
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            Write-AiForgeDry 'Would back up existing .agents/mcp/mcp.json -> mcp.json.bak'
        }
        Write-AiForgeDry ("Would merge MCP servers from: {0} -> {1}" -f ($sources -join ' '), $destination)
        $Context.RanCommands.Add('install-mcp: mcp.json (skipped: dry-run)')
        return
    }

    if (-not $PSCmdlet.ShouldProcess($destination, 'install MCP config')) { return }

    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        Copy-Item -LiteralPath $destination -Destination "$destination.bak" -Force
        Write-AiForgeWarning 'Existing .agents/mcp/mcp.json backed up to mcp.json.bak'
    }

    if ($sources.Count -eq 1) {
        Copy-Item -LiteralPath $sources[0] -Destination $destination -Force
        Write-AiForgeOk 'Installed MCP config -> .agents/mcp/mcp.json'
        $Context.RanCommands.Add('install-mcp: .agents/mcp/mcp.json')
    } else {
        $merged = $null
        foreach ($source in $sources) {
            $json = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
            $servers = if ($json.PSObject.Properties.Name -contains 'mcpServers') { $json.mcpServers } else { $null }
            $merged = Merge-AiForgeJsonObject -Base $merged -Overlay $servers
        }
        $json = ([ordered]@{ mcpServers = $merged } | ConvertTo-Json -Depth 20) + [System.Environment]::NewLine
        Set-AiForgeFileContent -Path $destination -Content $json -Confirm:$false
        Write-AiForgeOk "Merged MCP servers ($($sources.Count) source(s)) -> .agents/mcp/mcp.json"
        $Context.RanCommands.Add('install-mcp: merged .agents/mcp/mcp.json')
    }

    $Context.SpecialNotes.Add("Review $destination and remove any MCP servers you don't need; wire it up with the sync-ai skill.")
}

function Invoke-AiForgeHelperCommand {
    <#
    .SYNOPSIS
        Runs one helper command row (autoskills, a scan, or the MCP config).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][pscustomobject] $Context,
        [Parameter(Mandatory)][string] $CommandId
    )

    switch ($CommandId) {
        'auto-skills' {
            if ($Context.DryRun) {
                Write-AiForgeDry "Would run in $($Context.ProjectPath): npx autoskills"
                if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
                    Write-AiForgeWarning 'npx not found; this step would be skipped on a real run.'
                }
                $Context.RanCommands.Add('auto-skills: npx autoskills (skipped: dry-run)')
                return
            }
            if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
                Write-AiForgeWarning 'npx not found; cannot run autoskills. Install Node.js >= 22.'
                return
            }
            if (-not $PSCmdlet.ShouldProcess($Context.ProjectPath, 'npx autoskills')) { return }

            Write-AiForgeInfo "Running autoskills in $($Context.ProjectPath) ..."
            Push-Location -LiteralPath $Context.ProjectPath
            try { & npx autoskills } finally { Pop-Location }
            $Context.RanCommands.Add('auto-skills: npx autoskills')
        }

        'scan-cursor-recommendations' {
            $outputFile = 'cursor-recommendations.md'
            if ($Context.DryRun) {
                Write-AiForgeDry "Would run in $($Context.ProjectPath): agent -p <claude-automation-recommender> > $outputFile"
                if (-not (Get-Command agent -ErrorAction SilentlyContinue)) {
                    Write-AiForgeWarning "'agent' CLI not found; this step would be skipped on a real run."
                }
                $Context.RanCommands.Add("scan-cursor: $outputFile (skipped: dry-run)")
                return
            }
            if (-not (Get-Command agent -ErrorAction SilentlyContinue)) {
                Write-AiForgeWarning "'agent' CLI not found; skipping Cursor recommendations scan."
                return
            }
            if (-not $PSCmdlet.ShouldProcess($Context.ProjectPath, 'scan Cursor recommendations')) { return }

            Write-AiForgeInfo "Scanning Cursor recommendations -> $outputFile"
            $skillPath = Join-Path $Context.Config.ScriptRoot '.agents/skills/claude-automation-recommender/SKILL.md'
            $prompt = if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
                Get-Content -LiteralPath $skillPath -Raw
            } else {
                '/claude-automation-recommender'
            }

            Push-Location -LiteralPath $Context.ProjectPath
            try {
                $output = (& agent -p $prompt --output-format text | Out-String)
                $exitCode = $LASTEXITCODE
                Set-AiForgeFileContent -Path (Join-Path $Context.ProjectPath $outputFile) -Content $output -Confirm:$false
            } finally {
                Pop-Location
            }
            Complete-AiForgeRecommendation -Context $Context -Label 'scan-cursor' -FileName $outputFile -ExitCode $exitCode `
                -Hint "authenticate the Cursor agent CLI (run 'agent login'), then re-run." | Out-Null
        }

        'scan-claude-recommendations' {
            $outputFile = 'claude-recommendations.md'
            if ($Context.DryRun) {
                Write-AiForgeDry "Would run in $($Context.ProjectPath): claude -p `"/claude-automation-recommender`" > $outputFile"
                if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
                    Write-AiForgeWarning "'claude' CLI not found; this step would be skipped on a real run."
                }
                $Context.RanCommands.Add("scan-claude: $outputFile (skipped: dry-run)")
                return
            }
            if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
                Write-AiForgeWarning "'claude' CLI not found; skipping Claude recommendations scan."
                return
            }
            if (-not $PSCmdlet.ShouldProcess($Context.ProjectPath, 'scan Claude recommendations')) { return }

            Write-AiForgeInfo "Scanning Claude recommendations -> $outputFile"
            Push-Location -LiteralPath $Context.ProjectPath
            try {
                $output = (& claude -p '/claude-automation-recommender' --output-format text | Out-String)
                $exitCode = $LASTEXITCODE
                Set-AiForgeFileContent -Path (Join-Path $Context.ProjectPath $outputFile) -Content $output -Confirm:$false
            } finally {
                Pop-Location
            }
            Complete-AiForgeRecommendation -Context $Context -Label 'scan-claude' -FileName $outputFile -ExitCode $exitCode `
                -Hint "authenticate the Claude CLI (run 'claude login', or set a valid ANTHROPIC_API_KEY), then re-run." | Out-Null
        }

        'install-mcp' {
            Install-AiForgeMcpConfig -Context $Context -Confirm:$false
        }
    }
}

function Add-AiForgePostInstallNote {
    <#
    .SYNOPSIS
        Collects the post-install prompts published by skills/<sub>/README.md.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Context)

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($skill in $Context.Selection.Skills) {
        if (-not $skill.Sub -or -not $seen.Add($skill.Sub)) { continue }

        $readme = Join-Path $Context.Config.ScriptRoot (Join-Path 'skills' (Join-Path $skill.Sub 'README.md'))
        $prompt = Get-AiForgeCodeBlock -Path $readme -Language 'markdown'
        if ($prompt) {
            $Context.SpecialNotes.Add("Post-install prompt for '$($skill.Sub)' (from skills/$($skill.Sub)/README.md):" +
                [System.Environment]::NewLine + $prompt)
        }
    }
}

function Copy-AiForgeAgentsTemplate {
    <#
    .SYNOPSIS
        Copies AGENTS.template.md to <project>/AGENTS.md, backing up any existing file.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][pscustomobject] $Context)

    $template = $Context.Config.AgentsTemplate
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
        Write-AiForgeWarning "AGENTS template not found ($template); skipped AGENTS.md creation."
        return
    }

    $destination = Join-Path $Context.ProjectPath 'AGENTS.md'

    if ($Context.DryRun) {
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            Write-AiForgeDry 'Would back up existing AGENTS.md -> AGENTS.md.bak'
        }
        Write-AiForgeDry "Would copy $template -> $destination"
        $Context.AgentsMdCopied = $true
        return
    }

    if (-not $PSCmdlet.ShouldProcess($destination, 'copy AGENTS template')) { return }

    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        Copy-Item -LiteralPath $destination -Destination "$destination.bak" -Force
        Write-AiForgeWarning 'Existing AGENTS.md backed up to AGENTS.md.bak'
    }
    Copy-Item -LiteralPath $template -Destination $destination -Force
    Write-AiForgeOk ("Copied {0} -> AGENTS.md" -f (Split-Path -Leaf $template))
    $Context.AgentsMdCopied = $true
}

function Invoke-AiForgeInstall {
    <#
    .SYNOPSIS
        Runs the whole install phase in the same order as install.sh.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][pscustomobject] $Context)

    if (-not $PSCmdlet.ShouldProcess($Context.ProjectPath, 'install ai-forge items')) { return }

    if ($Context.DryRun) {
        Write-AiForgeDry 'Previewing installation (no changes will be made) ...'
    } else {
        Write-AiForgeInfo 'Starting installation ...'
    }

    foreach ($agent in $Context.Selection.Agents) {
        Install-AiForgeAgent -Context $Context -Agent $agent -Confirm:$false
    }
    foreach ($skill in $Context.Selection.Skills) {
        Install-AiForgeSkill -Context $Context -Skill $skill -Confirm:$false
    }
    foreach ($remote in $Context.Selection.Remote) {
        Invoke-AiForgeReadmeSkill -Context $Context -Skill $remote -Confirm:$false
    }
    foreach ($command in $Context.Selection.Commands) {
        Invoke-AiForgeHelperCommand -Context $Context -CommandId $command -Confirm:$false
    }

    Add-AiForgePostInstallNote -Context $Context
    Copy-AiForgeAgentsTemplate -Context $Context -Confirm:$false
}

Export-ModuleMember -Function @(
    'New-AiForgeInstallContext'
    'Get-AiForgeSelection'
    'Get-AiForgeCodeBlock'
    'Install-AiForgeSkill'
    'Install-AiForgeAgent'
    'Invoke-AiForgeReadmeSkill'
    'Complete-AiForgeRecommendation'
    'Test-AiForgeJsonObject'
    'Get-AiForgeJsonEntry'
    'Merge-AiForgeJsonObject'
    'Get-AiForgeMcpSource'
    'Install-AiForgeMcpConfig'
    'Invoke-AiForgeHelperCommand'
    'Add-AiForgePostInstallNote'
    'Copy-AiForgeAgentsTemplate'
    'Invoke-AiForgeInstall'
)
