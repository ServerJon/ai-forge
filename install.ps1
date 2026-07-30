#Requires -Version 5.1

<#
.SYNOPSIS
    ai-forge installer for Windows PowerShell 5.1 and PowerShell 7+.

.DESCRIPTION
    Native port of install.sh for users who do not run WSL or Git Bash.
    It presents the same checkbox tree of agents, skills and helper commands,
    resolves dependencies, skips already-installed items, copies the selected
    SKILL.md / agent files into the project's .agents/ folder, drops a
    pre-filled AGENTS.md and prints a summary with next steps.

    Behaviour is kept in lockstep with install.sh; a CI parity job installs
    with both and diffs the result. When you change one, change the other.

.PARAMETER Path
    Target project path where skills/agents are installed. Accepts Windows
    (C:\src\app), Git Bash (/c/src/app) and WSL (/mnt/c/src/app) spellings.

.PARAMETER Extra
    Extra project to layer on top of ai-forge. Its skills/agents are listed
    alongside ai-forge's, its MCP config is merged, and its .ai-forge.env file
    (if present) is loaded for labels and superseded items.

.PARAMETER ListAll
    Non-interactive: select ALL available skills/agents (no console needed).
    Helper commands are not auto-run. Combine with -Yes for unattended installs
    and -DryRun for CI checks.

.PARAMETER Yes
    Assume "yes" for confirmation prompts.

.PARAMETER DryRun
    Preview the actions without writing anything or running commands.

.PARAMETER NoColor
    Disable coloured output.

.EXAMPLE
    .\install.ps1 -Path C:\src\my-project

.EXAMPLE
    .\install.ps1 -Path C:\src\my-project -ListAll -Yes

.EXAMPLE
    .\install.ps1 -Path C:\src\my-project -ListAll -DryRun
#>

[CmdletBinding()]
param(
    [Alias('p')]
    [string] $Path,

    [Alias('e')]
    [string] $Extra,

    [Alias('a')]
    [switch] $ListAll,

    [Alias('y')]
    [switch] $Yes,

    [Alias('n')]
    [switch] $DryRun,

    [switch] $NoColor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Join-Path $PSScriptRoot 'scripts/powershell'
foreach ($module in @('Console', 'Config', 'Catalog', 'Menu', 'Dependencies', 'Install', 'Manifest', 'Summary')) {
    Import-Module (Join-Path $moduleRoot "AiForge.$module.psm1") -Force -DisableNameChecking
}

function Read-AiForgeProjectPath {
    <#
    .SYNOPSIS
        Prompts for the target path when -Path was omitted.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-AiForgeInteractive)) { return '' }
    Read-Host 'Enter the target project path'
}

function Confirm-AiForgeDroppedItem {
    <#
    .SYNOPSIS
        Asks whether to continue after dropping items with unmet dependencies.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][bool] $AssumeYes)

    if ($AssumeYes) { return $true }
    $answer = Read-Host 'Continue and skip the items above? [y/N]'
    $answer -in @('y', 'Y', 'yes', 'YES')
}

function Invoke-AiForgeInstaller {
    <#
    .SYNOPSIS
        Orchestrates the install, mirroring the section order of install.sh.
    #>
    [CmdletBinding()]
    param()

    # --- 1. Resolve and validate the project path ---------------------------
    $targetPath = $Path
    if ([string]::IsNullOrWhiteSpace($targetPath)) { $targetPath = Read-AiForgeProjectPath }
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        throw 'No project path provided. Re-run with -Path <path>. Nothing to install.'
    }

    $projectPath = Resolve-AiForgeDirectory -Path $targetPath -Description 'Project path'
    $scriptRoot = (Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    if ($projectPath -eq $scriptRoot) {
        throw 'Target project must be different from the ai-forge repo itself.'
    }

    Write-AiForgeInfo "Target project: $projectPath"
    if ($DryRun) {
        Write-AiForgeDry 'DRY-RUN MODE -- no files will be written and no commands will be executed.'
    }

    # --- 1b. Resolve the extra project and load its config ------------------
    $extraProject = $null
    if (-not [string]::IsNullOrWhiteSpace($Extra)) {
        $extraProject = Resolve-AiForgeDirectory -Path $Extra -Description 'Extra project'
        if ($extraProject -eq $projectPath) {
            throw 'Extra project must differ from the target project.'
        }
    }

    $config = New-AiForgeConfig -ScriptRoot $scriptRoot -ExtraProject $extraProject
    if ($extraProject) {
        if ($config.ConfigFile) {
            Write-AiForgeInfo "Loaded extra config: $($config.ConfigFile)"
        } else {
            Write-AiForgeWarning ("No {0} found in {1}; using defaults for the extra layer." -f (Get-AiForgeExtraConfigFileName), $extraProject)
        }
        Write-AiForgeInfo "Layering extra project: $extraProject"
    }

    # --- 2. Build the installable item tree ---------------------------------
    $items = New-AiForgeCatalog -Config $config -ProjectPath $projectPath
    if ($items.Count -eq 0) {
        throw "No installable items found in $scriptRoot."
    }

    # --- 3. Selection (menu or -ListAll) ------------------------------------
    if ($ListAll) {
        $count = Select-AiForgeAllItems -Items $items
        Write-AiForgeInfo "-ListAll: selected $count skill/agent item(s) (helper commands not auto-run)."
        if ($count -eq 0) {
            throw 'Nothing to install -- every available skill/agent is already present in the target.'
        }
    } else {
        Show-AiForgeMenu -Items $items -ProjectPath $projectPath
    }

    # --- 4. Resolve selection -> concrete install actions -------------------
    $selection = Get-AiForgeSelection -Items $items
    if ($selection.Total -eq 0) {
        throw 'Nothing selected. Exiting.'
    }

    # --- 5. Skill dependency resolution -------------------------------------
    $installedTest = { param($name) Test-AiForgeSkillInstalled -ProjectPath $projectPath -Name $name }.GetNewClosure()
    $unmet = Get-AiForgeUnmetDependency -Selection $selection -InstalledTest $installedTest
    $dropped = @()
    if ($unmet.Count -gt 0) {
        foreach ($entry in $unmet) {
            Write-AiForgeWarning ("Skill '{0}' is missing dependencies: {1}" -f $entry.Name, ($entry.Missing -join ' '))
        }
        if (-not (Confirm-AiForgeDroppedItem -AssumeYes $Yes.IsPresent)) {
            throw 'Aborted due to unmet dependencies.'
        }
        $dropped = @($unmet | ForEach-Object { $_.Name })
        $selection.Skills = @($selection.Skills | Where-Object { $dropped -notcontains $_.Name })
    }

    # --- 5b/5c. Dependency reporting ----------------------------------------
    $dependencyRows = New-AiForgeDependencyTable -Selection $selection
    $mcpRows = New-AiForgeMcpTable -Selection $selection -ProjectPath $projectPath

    # --- 6-8. Install --------------------------------------------------------
    $context = New-AiForgeInstallContext -ProjectPath $projectPath -Config $config -Selection $selection -DryRun $DryRun.IsPresent
    foreach ($name in $dropped) { $context.DroppedItems.Add($name) }

    Invoke-AiForgeInstall -Context $context -Confirm:$false
    Write-AiForgeManifest -Context $context -Confirm:$false

    # --- 9. Summary ----------------------------------------------------------
    Write-AiForgeSummary -Context $context -DependencyRows $dependencyRows -McpRows $mcpRows
}

Initialize-AiForgeConsole -NoColor:$NoColor

try {
    Invoke-AiForgeInstaller
    exit 0
} catch {
    Write-AiForgeError $_.Exception.Message
    exit 1
}
