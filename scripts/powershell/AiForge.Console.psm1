#Requires -Version 5.1

<#
.SYNOPSIS
    Console primitives shared by the ai-forge PowerShell installer.

.DESCRIPTION
    Mirrors the info/ok/warn/err/dry helpers of install.sh. Colour is applied
    through Write-Host rather than raw ANSI escapes: Windows PowerShell 5.1 on
    an older console host does not always have virtual-terminal processing
    enabled, and Write-Host works everywhere.

    Glyphs degrade to ASCII automatically when the console cannot render UTF-8,
    which is the common case for cmd.exe running with a legacy code page.
#>

Set-StrictMode -Version Latest

# Note for the other modules: sibling modules are imported WITHOUT -Force.
# -Force unloads the module first, which also strips the copies the entry
# script imported into the global session -- the calling script would then
# lose functions it had already imported.

# Filled in by Initialize-AiForgeConsole.
$script:Glyphs = @{}
$script:ColorEnabled = $true

$script:UnicodeGlyphs = @{
    Check     = [char]0x2713   # check mark
    Cross     = [char]0x2717   # ballot X
    Cursor    = [char]0x276F   # heavy right-pointing angle quotation mark
    Up        = [char]0x25B2   # black up-pointing triangle
    Down      = [char]0x25BC   # black down-pointing triangle
    Bullet    = [char]0x2022   # bullet
    Circle    = [char]0x25CF   # black circle
    Dash      = [char]0x2014   # em dash
    Ellipsis  = [char]0x2026   # horizontal ellipsis
    Rule      = [char]0x2550   # box drawings double horizontal
    Arrow     = [char]0x2192   # rightwards arrow
}

$script:AsciiGlyphs = @{
    Check     = '+'
    Cross     = 'x'
    Cursor    = '>'
    Up        = '^'
    Down      = 'v'
    Bullet    = '*'
    Circle    = 'o'
    Dash      = '-'
    Ellipsis  = '...'
    Rule      = '='
    Arrow     = '->'
}

function Initialize-AiForgeConsole {
    <#
    .SYNOPSIS
        Prepares console encoding and picks the glyph set to use.

    .PARAMETER NoColor
        Disables coloured output (useful for CI logs and redirected output).
    #>
    [CmdletBinding()]
    param(
        [switch] $NoColor
    )

    $unicodeOk = $false
    try {
        # Only meaningful for a real console; harmless when output is redirected.
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
        $unicodeOk = $true
    } catch {
        $unicodeOk = $false
    }

    $script:Glyphs = if ($unicodeOk) { $script:UnicodeGlyphs } else { $script:AsciiGlyphs }
    $script:ColorEnabled = -not $NoColor -and -not $env:NO_COLOR
}

function Get-AiForgeGlyph {
    <#
    .SYNOPSIS
        Returns a single glyph by logical name (Check, Cross, Cursor, ...).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($script:Glyphs.Count -eq 0) { Initialize-AiForgeConsole }
    if (-not $script:Glyphs.ContainsKey($Name)) {
        throw "Unknown glyph '$Name'."
    }
    [string] $script:Glyphs[$Name]
}

function Write-AiForgeText {
    <#
    .SYNOPSIS
        Writes text with an optional foreground colour, honouring -NoColor.

    .PARAMETER NoNewline
        Keeps the cursor on the same line so callers can compose coloured
        segments (used by the menu renderer).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string] $Text = '',

        [System.ConsoleColor] $Color,

        [switch] $NoNewline
    )

    $params = @{ Object = $Text; NoNewline = [bool]$NoNewline }
    if ($script:ColorEnabled -and $PSBoundParameters.ContainsKey('Color')) {
        $params['ForegroundColor'] = $Color
    }
    Write-Host @params
}

function Write-AiForgeInfo {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string] $Message)

    Write-AiForgeText '==> ' -Color Blue -NoNewline
    Write-AiForgeText $Message
}

function Write-AiForgeOk {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string] $Message)

    Write-AiForgeText ("{0} " -f (Get-AiForgeGlyph Check)) -Color Green -NoNewline
    Write-AiForgeText $Message
}

function Write-AiForgeDry {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string] $Message)

    Write-AiForgeText '[dry-run] ' -Color Cyan -NoNewline
    Write-AiForgeText $Message
}

function Write-AiForgeWarning {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string] $Message)

    Write-AiForgeText ("! {0}" -f $Message) -Color Yellow
}

function Write-AiForgeError {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string] $Message)

    Write-AiForgeText ("{0} {1}" -f (Get-AiForgeGlyph Cross), $Message) -Color Red
}

function Write-AiForgeHeading {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string] $Message)

    Write-AiForgeText ''
    Write-AiForgeText $Message -Color White
}

function Set-AiForgeFileContent {
    <#
    .SYNOPSIS
        Writes a text file as UTF-8 without a BOM.

    .DESCRIPTION
        Set-Content -Encoding UTF8 emits a BOM on Windows PowerShell 5.1 but
        not on PowerShell 7, which would make the same install produce
        different bytes on different hosts (and upset strict JSON readers).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Content
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'write file')) { return }
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Test-AiForgeInteractive {
    <#
    .SYNOPSIS
        True when a real, interactive console is attached.

    .DESCRIPTION
        The equivalent of bash's `[ -t 0 ]`. [Console]::IsInputRedirected throws
        on some hosts (for example the ISE), hence the guarded fallback.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        return -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
    } catch {
        return $false
    }
}

Export-ModuleMember -Function @(
    'Initialize-AiForgeConsole'
    'Get-AiForgeGlyph'
    'Write-AiForgeText'
    'Write-AiForgeInfo'
    'Write-AiForgeOk'
    'Write-AiForgeDry'
    'Write-AiForgeWarning'
    'Write-AiForgeError'
    'Write-AiForgeHeading'
    'Set-AiForgeFileContent'
    'Test-AiForgeInteractive'
)
