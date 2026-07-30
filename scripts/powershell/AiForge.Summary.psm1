#Requires -Version 5.1

<#
.SYNOPSIS
    Final summary printed after an install or dry run.

.DESCRIPTION
    Ports section 9 of install.sh: what was installed, which commands ran,
    the dependency tables, README post-install prompts and the next steps.
#>

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'AiForge.Console.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AiForge.Dependencies.psm1') -DisableNameChecking

function Write-AiForgeItemList {
    <#
    .SYNOPSIS
        Writes a bulleted list under a heading, skipping empty collections.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Heading,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Items,
        [System.ConsoleColor] $HeadingColor = [System.ConsoleColor]::White
    )

    if ($Items.Count -eq 0) { return }

    Write-AiForgeText ''
    Write-AiForgeText $Heading -Color $HeadingColor
    $bullet = Get-AiForgeGlyph Bullet
    foreach ($item in $Items) {
        Write-AiForgeText "  $bullet $item"
    }
}

function Write-AiForgeSummary {
    <#
    .SYNOPSIS
        Renders the closing summary for an install run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $DependencyRows,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $McpRows
    )

    $rule = (Get-AiForgeGlyph Rule).ToString()
    $verb = if ($Context.DryRun) { 'would be installed' } else { 'installed' }
    $title = if ($Context.DryRun) { ' Installation summary (dry-run) ' } else { ' Installation summary ' }

    Write-AiForgeText ''
    Write-AiForgeText (($rule * 17) + $title + ($rule * 17)) -Color White
    Write-AiForgeText 'Target project: ' -NoNewline
    Write-AiForgeText $Context.ProjectPath -Color Cyan

    Write-AiForgeItemList -Heading "Agents $verb (-> .agents/agents/):" -Items @($Context.InstalledAgents)
    Write-AiForgeItemList -Heading "Skills $verb (-> .agents/skills/):" -Items @($Context.InstalledSkills)
    Write-AiForgeItemList -Heading 'Commands run:' -Items @($Context.RanCommands)
    Write-AiForgeItemList -Heading 'Skipped (unmet dependencies):' -Items @($Context.DroppedItems) -HeadingColor Yellow

    Write-AiForgeDependencyTable -Rows $DependencyRows
    Write-AiForgeMcpTable -Rows $McpRows

    if ($Context.Selection.Skills | Where-Object { $_.Name -eq 'sync-ai' }) {
        Write-AiForgeText ''
        Write-AiForgeText 'Recommended: ' -Color Yellow -NoNewline
        Write-AiForgeText 'run the sync-ai skill now to sync AI context files across your tools.'
    }

    foreach ($note in $Context.SpecialNotes) {
        Write-AiForgeText ''
        Write-AiForgeText 'Note:' -Color White
        Write-AiForgeText $note
    }

    if ($Context.AgentsMdCopied) {
        Write-AiForgeText ''
        Write-AiForgeText 'Next step - adapt AGENTS.md' -Color White
        Write-AiForgeText 'From your Agent (Claude, Gemini, etc.), run the following prompt to adapt the `AGENTS.md` file:'
        Write-AiForgeText ''
        Write-AiForgeText '  > From the `AGENTS.md` file, review it and do the instruction on the `TODO` sections.' -Color Cyan
    }

    Write-AiForgeText ''
    Write-AiForgeText 'Remember: ' -Color Yellow -NoNewline
    Write-AiForgeText '`auto-skills` and the Cursor recommendations scan are temporarily disabled'
    Write-AiForgeText 'in the menu above. To pull in more recommended skills/agents and improve your AI config,'
    Write-AiForgeText 'run both commands yourself in the target project:'
    Write-AiForgeText ''
    Write-AiForgeText '  npx autoskills' -Color Cyan
    Write-AiForgeText '  agent -p "/claude-automation-recommender" --output-format text > cursor-recommendations.md' -Color Cyan

    Write-AiForgeText ''
    if ($Context.DryRun) {
        Write-AiForgeText 'Dry-run complete. Re-run without -DryRun to apply these changes.' -Color Cyan
    } else {
        Write-AiForgeText 'Done.' -Color Green
    }
}

Export-ModuleMember -Function @(
    'Write-AiForgeItemList'
    'Write-AiForgeSummary'
)
