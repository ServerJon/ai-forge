#Requires -Version 5.1

<#
.SYNOPSIS
    Interactive checkbox menu for the ai-forge PowerShell installer.

.DESCRIPTION
    Ports section 3 of install.sh: the same key bindings (arrows or j/k to
    move, space to toggle a subtree, a/n to select all or none, enter to
    confirm, q to quit) and the same scrolling viewport.

    Keys are read with [Console]::ReadKey so the menu works in Windows
    PowerShell 5.1, PowerShell 7, Windows Terminal and conhost alike -- no
    virtual-terminal input support required.
#>

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'AiForge.Console.psm1') -DisableNameChecking

# Top row of the scrolling viewport; persists across renders.
$script:ViewportTop = 0

function Test-AiForgeDescendant {
    <#
    .SYNOPSIS
        True when row $Index is a descendant of row $Ancestor.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Items,
        [Parameter(Mandatory)][int] $Index,
        [Parameter(Mandatory)][int] $Ancestor
    )

    $current = $Items[$Index].Parent
    while ($current -ge 0) {
        if ($current -eq $Ancestor) { return $true }
        $current = $Items[$current].Parent
    }
    $false
}

function Set-AiForgeSubtreeChecked {
    <#
    .SYNOPSIS
        Sets a row and all its descendants to $Value, skipping rows that are
        already installed or disabled.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Items,
        [Parameter(Mandatory)][int] $Index,
        [Parameter(Mandatory)][bool] $Value
    )

    if (-not $PSCmdlet.ShouldProcess("row $Index", "set checked=$Value")) { return }

    if (-not $Items[$Index].Installed -and -not $Items[$Index].Disabled) {
        $Items[$Index].Checked = $Value
    }
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($Items[$i].Installed -or $Items[$i].Disabled) { continue }
        if (Test-AiForgeDescendant -Items $Items -Index $i -Ancestor $Index) {
            $Items[$i].Checked = $Value
        }
    }
}

function Update-AiForgeParentCheck {
    <#
    .SYNOPSIS
        Recomputes category/subfolder checkmarks from their children.

    .DESCRIPTION
        Purely cosmetic aggregation: a parent shows as checked when every
        selectable child is checked. Installed and disabled children count as
        satisfied so a fully installed subfolder still renders as complete.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Items
    )

    for ($i = $Items.Count - 1; $i -ge 0; $i--) {
        if ($Items[$i].Type -notin @('cat', 'sub')) { continue }

        $hasChild = $false
        $allChecked = $true
        for ($j = 0; $j -lt $Items.Count; $j++) {
            if ($Items[$j].Parent -ne $i) { continue }
            $hasChild = $true
            if ($Items[$j].Installed -or $Items[$j].Disabled) { continue }
            if (-not $Items[$j].Checked) { $allChecked = $false }
        }
        $Items[$i].Checked = ($hasChild -and $allChecked)
    }
}

function Get-AiForgeConsoleSize {
    <#
    .SYNOPSIS
        Console height/width with safe fallbacks for redirected or odd hosts.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $rows = 24
    $cols = 80
    try {
        if ([Console]::WindowHeight -gt 0) { $rows = [Console]::WindowHeight }
        if ([Console]::WindowWidth -gt 0) { $cols = [Console]::WindowWidth }
    } catch {
        # No console attached (redirected output, CI): keep the 24x80 defaults.
        Write-Debug "Console size unavailable: $($_.Exception.Message)"
    }
    [pscustomobject]@{ Rows = $rows; Cols = $cols }
}

function Write-AiForgeMenuRow {
    <#
    .SYNOPSIS
        Renders a single catalog row, including checkbox, indent and markers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $Item,
        [Parameter(Mandatory)][bool] $IsCursor
    )

    $cursorGlyph = Get-AiForgeGlyph Cursor
    if ($IsCursor) {
        Write-AiForgeText "$cursorGlyph " -Color Blue -NoNewline
    } else {
        Write-AiForgeText '  ' -NoNewline
    }

    if ($Item.Installed) {
        Write-AiForgeText '[x]' -Color Green -NoNewline
    } elseif ($Item.Disabled) {
        Write-AiForgeText '[-]' -Color DarkGray -NoNewline
    } elseif ($Item.Checked) {
        Write-AiForgeText '[x]' -Color Green -NoNewline
    } else {
        Write-AiForgeText '[ ]' -NoNewline
    }

    $indent = ' ' * (2 * $Item.Depth)
    $labelColor = if ($Item.Disabled) { [System.ConsoleColor]::DarkGray } else { [System.ConsoleColor]::Gray }
    Write-AiForgeText (" $indent" + $Item.Label) -Color $labelColor -NoNewline

    if ($Item.Note) {
        Write-AiForgeText (' ' + $Item.Note) -Color DarkGray -NoNewline
    }
    if ($Item.Installed) {
        Write-AiForgeText ' (installed)' -Color DarkGray -NoNewline
    } elseif ($Item.Disabled) {
        Write-AiForgeText ' (currently unavailable -- run manually, see summary)' -Color DarkGray -NoNewline
    }

    Write-AiForgeText ''
}

function Show-AiForgeMenuFrame {
    <#
    .SYNOPSIS
        Draws one full frame of the menu.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Items,
        [Parameter(Mandatory)][int] $Cursor,
        [Parameter(Mandatory)][string] $ProjectPath
    )

    $size = Get-AiForgeConsoleSize
    $total = $Items.Count

    # Reserve lines for the title, hint, position bar, bottom indicator and a
    # one-line safety margin so the final newline never forces a scroll.
    $visible = [Math]::Max(3, $size.Rows - 5)
    if ($visible -gt $total) { $visible = $total }

    if ($Cursor -lt $script:ViewportTop) { $script:ViewportTop = $Cursor }
    if ($Cursor -ge $script:ViewportTop + $visible) { $script:ViewportTop = $Cursor - $visible + 1 }
    $maxTop = [Math]::Max(0, $total - $visible)
    $script:ViewportTop = [Math]::Min([Math]::Max(0, $script:ViewportTop), $maxTop)
    $last = [Math]::Min($script:ViewportTop + $visible - 1, $total - 1)

    Clear-Host

    # Truncate the target path so the header never wraps and offsets the layout.
    $pathDisplay = $ProjectPath
    $maxPath = [Math]::Max(10, $size.Cols - 22)
    if ($pathDisplay.Length -gt $maxPath) {
        $ellipsis = Get-AiForgeGlyph Ellipsis
        $pathDisplay = $ellipsis + $pathDisplay.Substring($pathDisplay.Length - ($maxPath - $ellipsis.Length))
    }

    Write-AiForgeText 'ai-forge installer' -Color White -NoNewline
    Write-AiForgeText ' - ' -NoNewline
    Write-AiForgeText $pathDisplay -Color Cyan
    Write-AiForgeText 'up/down move . space toggle . a all . n none . enter confirm . q quit' -Color DarkGray

    $position = "  [$($Cursor + 1)/$total]"
    if ($script:ViewportTop -gt 0) {
        Write-AiForgeText ("$position  " + (Get-AiForgeGlyph Up) + ' more above') -Color DarkGray
    } else {
        Write-AiForgeText $position -Color DarkGray
    }

    for ($i = $script:ViewportTop; $i -le $last; $i++) {
        Write-AiForgeMenuRow -Item $Items[$i] -IsCursor ($i -eq $Cursor)
    }

    if ($last -lt $total - 1) {
        Write-AiForgeText ('  ' + (Get-AiForgeGlyph Down) + ' more below') -Color DarkGray
    } else {
        Write-AiForgeText ''
    }
}

function Show-AiForgeMenu {
    <#
    .SYNOPSIS
        Runs the interactive selection loop, mutating $Items in place.

    .DESCRIPTION
        Returns when the user confirms with Enter. Throws when the user quits
        with q, which the caller surfaces as "Installation cancelled".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Items,
        [Parameter(Mandatory)][string] $ProjectPath
    )

    if (-not (Test-AiForgeInteractive)) {
        throw 'Interactive menu requires a console. Run the script directly in a terminal, or pass -ListAll.'
    }

    $script:ViewportTop = 0
    $cursor = 0

    while ($true) {
        Update-AiForgeParentCheck -Items $Items
        Show-AiForgeMenuFrame -Items $Items -Cursor $cursor -ProjectPath $ProjectPath

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $cursor = if ($cursor -le 0) { $Items.Count - 1 } else { $cursor - 1 }; continue }
            'DownArrow' { $cursor = if ($cursor -ge $Items.Count - 1) { 0 } else { $cursor + 1 }; continue }
            'Enter'     { Clear-Host; return }
            'Spacebar'  {
                $item = $Items[$cursor]
                if (-not $item.Installed -and -not $item.Disabled) {
                    Set-AiForgeSubtreeChecked -Items $Items -Index $cursor -Value (-not $item.Checked) -Confirm:$false
                }
                continue
            }
        }

        switch ($key.KeyChar) {
            'k' { $cursor = if ($cursor -le 0) { $Items.Count - 1 } else { $cursor - 1 } }
            'j' { $cursor = if ($cursor -ge $Items.Count - 1) { 0 } else { $cursor + 1 } }
            ' ' {
                $item = $Items[$cursor]
                if (-not $item.Installed -and -not $item.Disabled) {
                    Set-AiForgeSubtreeChecked -Items $Items -Index $cursor -Value (-not $item.Checked) -Confirm:$false
                }
            }
            { $_ -in 'a', 'A' } {
                foreach ($item in $Items) {
                    if (-not $item.Installed -and -not $item.Disabled) { $item.Checked = $true }
                }
            }
            { $_ -in 'n', 'N' } {
                foreach ($item in $Items) { $item.Checked = $false }
            }
            { $_ -in 'q', 'Q' } {
                Clear-Host
                throw 'Installation cancelled.'
            }
        }
    }
}

function Select-AiForgeAllItem {
    <#
    .SYNOPSIS
        Non-interactive selection: checks every installable skill/agent leaf.

    .DESCRIPTION
        Helper command rows stay unselected so a bulk install never triggers
        side-effecting commands without an explicit menu choice.

    .OUTPUTS
        The number of rows selected.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Items
    )

    $count = 0
    foreach ($item in $Items) {
        if ($item.Type -notin @('skill', 'agent', 'readme')) { continue }
        if ($item.Installed) { continue }
        $item.Checked = $true
        $count++
    }
    $count
}

Export-ModuleMember -Function @(
    'Test-AiForgeDescendant'
    'Set-AiForgeSubtreeChecked'
    'Update-AiForgeParentCheck'
    'Get-AiForgeConsoleSize'
    'Show-AiForgeMenu'
    'Select-AiForgeAllItem'
)
