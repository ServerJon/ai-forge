#Requires -Version 5.1

<#
.SYNOPSIS
    Writes <project>/.agents/manifest.json.

.DESCRIPTION
    Ports section 8b of install.sh. The manifest records what was installed,
    from which source, and at which upstream commit, so a later run can update
    or uninstall deliberately instead of guessing.

    The schema must stay identical to the bash implementation
    ("ai-forge/install-manifest@1"); the CI parity job compares both outputs.
#>

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'AiForge.Console.psm1') -DisableNameChecking

function Get-AiForgeSourceLabel {
    <#
    .SYNOPSIS
        Classifies a source path as "ai-forge", an extra root's name, or "unknown".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $SourcePath,
        [Parameter(Mandatory)][pscustomobject] $Config
    )

    if ($SourcePath -eq $Config.ScriptRoot -or $SourcePath.StartsWith($Config.ScriptRoot + [System.IO.Path]::DirectorySeparatorChar)) {
        return 'ai-forge'
    }
    foreach ($root in $Config.ExtraRoots) {
        if ($SourcePath -eq $root -or $SourcePath.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar)) {
            return (Split-Path -Leaf $root)
        }
    }
    'unknown'
}

function Get-AiForgeGitCommit {
    <#
    .SYNOPSIS
        HEAD commit of a repository root, or $null when it is not a git repo.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $Root)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $commit = & git -C $Root rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) { return $null }
    $commit.Trim()
}

function New-AiForgeManifest {
    <#
    .SYNOPSIS
        Builds the manifest object for the current install context.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)][pscustomobject] $Context)

    $config = $Context.Config
    $selection = $Context.Selection

    $sources = [System.Collections.Generic.List[object]]::new()
    $sources.Add([ordered]@{
        name   = 'ai-forge'
        root   = $config.ScriptRoot
        commit = Get-AiForgeGitCommit -Root $config.ScriptRoot
    })
    foreach ($root in $config.ExtraRoots) {
        $sources.Add([ordered]@{
            name   = (Split-Path -Leaf $root)
            root   = $root
            commit = Get-AiForgeGitCommit -Root $root
        })
    }

    $skills = @(foreach ($skill in $selection.Skills) {
        [ordered]@{
            name   = $skill.Name
            source = Get-AiForgeSourceLabel -SourcePath $skill.Source -Config $config
            path   = ".agents/skills/$($skill.Name)"
        }
    })

    $agents = @(foreach ($agent in $selection.Agents) {
        [ordered]@{
            name   = $agent.Name
            source = Get-AiForgeSourceLabel -SourcePath $agent.Source -Config $config
            path   = ".agents/agents/$($agent.Name).md"
        }
    })

    $remote = @(foreach ($item in $selection.Remote) {
        [ordered]@{
            name   = $item.Name
            source = Get-AiForgeSourceLabel -SourcePath $item.Source -Config $config
        }
    })

    [ordered]@{
        schema       = 'ai-forge/install-manifest@1'
        generatedAt  = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        target       = $Context.ProjectPath
        sources      = @($sources)
        skills       = $skills
        agents       = $agents
        remoteSkills = $remote
        commands     = @($selection.Commands)
    }
}

function Write-AiForgeManifest {
    <#
    .SYNOPSIS
        Writes the manifest to <project>/.agents/manifest.json.

    .DESCRIPTION
        Skipped when nothing meaningful was installed, matching install.sh.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][pscustomobject] $Context)

    $total = $Context.InstalledSkills.Count + $Context.InstalledAgents.Count + $Context.Selection.Remote.Count
    if ($total -le 0) { return }

    $manifestDir = Join-Path $Context.ProjectPath '.agents'
    $manifestPath = Join-Path $manifestDir 'manifest.json'

    if ($Context.DryRun) {
        Write-AiForgeDry "Would write install manifest -> $manifestPath"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($manifestPath, 'write install manifest')) { return }

    $manifest = New-AiForgeManifest -Context $Context
    New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
    $json = ($manifest | ConvertTo-Json -Depth 10) + [System.Environment]::NewLine
    Set-AiForgeFileContent -Path $manifestPath -Content $json -Confirm:$false
    Write-AiForgeOk 'Wrote install manifest -> .agents/manifest.json'
}

Export-ModuleMember -Function @(
    'Get-AiForgeSourceLabel'
    'Get-AiForgeGitCommit'
    'New-AiForgeManifest'
    'Write-AiForgeManifest'
)
