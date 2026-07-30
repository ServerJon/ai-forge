#Requires -Version 5.1

<#
.SYNOPSIS
    Pester suite for the ai-forge PowerShell installer.

.DESCRIPTION
    Covers the pure logic of the port -- configuration parsing, catalog
    building, menu selection, dependency resolution and the MCP merge. The
    interactive key loop is not covered here; the CI parity job exercises the
    end-to-end install instead.

.EXAMPLE
    Invoke-Pester ./tests/powershell -Output Detailed
#>

# Evaluated during discovery, so -Skip: can use it. $IsWindows does not exist
# in Windows PowerShell 5.1, which is one of the hosts this suite runs on.
$script:OnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:ModuleRoot = Join-Path $script:RepoRoot 'scripts/powershell'

    foreach ($name in @('Console', 'Config', 'Catalog', 'Menu', 'Dependencies', 'Install', 'Manifest', 'Summary')) {
        Import-Module (Join-Path $script:ModuleRoot "AiForge.$name.psm1") -Force -DisableNameChecking
    }
    Initialize-AiForgeConsole -NoColor

    # Scratch directory for fixtures; removed in AfterAll.
    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("aiforge-tests-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Scratch -Force | Out-Null
}

AfterAll {
    if ($script:Scratch -and (Test-Path -LiteralPath $script:Scratch)) {
        Remove-Item -LiteralPath $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'AiForge.Config' {
    Context 'Split-AiForgeList' {
        It 'returns an empty array for empty input' {
            (Split-AiForgeList '').Count | Should -Be 0
        }

        It 'splits on any run of whitespace' {
            (Split-AiForgeList 'a  b   c') | Should -Be @('a', 'b', 'c')
        }
    }

    Context 'ConvertTo-AiForgeNativePath' {
        It 'expands a bare tilde' {
            ConvertTo-AiForgeNativePath '~' | Should -Be $HOME
        }

        It 'expands a tilde-prefixed path' {
            ConvertTo-AiForgeNativePath '~/projects' | Should -Be (Join-Path $HOME 'projects')
        }

        It 'rewrites Git Bash and WSL drive paths on Windows' -Skip:(-not $script:OnWindows) {
            ConvertTo-AiForgeNativePath '/c/src/app' | Should -Be 'C:\src\app'
            ConvertTo-AiForgeNativePath '/mnt/d/src/app' | Should -Be 'D:\src\app'
        }
    }

    Context 'ConvertFrom-AiForgeEnvFile' {
        BeforeAll {
            $script:EnvFile = Join-Path $script:Scratch 'layer.env'
            @(
                '# a comment'
                'export AIFORGE_EXTRA_LABEL=" (extra)"'
                "AIFORGE_HIDE_SKILLS='gh glab'"
                'AIFORGE_AGENTS_TEMPLATE=${AIFORGE_EXTRA_ROOT}/tpl.md'
                'this line is not an assignment'
            ) | Set-Content -LiteralPath $script:EnvFile
            $script:Parsed = ConvertFrom-AiForgeEnvFile -Path $script:EnvFile `
                -Seed @{ AIFORGE_EXTRA_ROOT = '/opt/layer' } -WarningAction SilentlyContinue
        }

        It 'strips the export prefix and double quotes' {
            $script:Parsed['AIFORGE_EXTRA_LABEL'] | Should -Be ' (extra)'
        }

        It 'keeps single-quoted values literal' {
            $script:Parsed['AIFORGE_HIDE_SKILLS'] | Should -Be 'gh glab'
        }

        It 'expands ${VAR} references against the seed' {
            $script:Parsed['AIFORGE_AGENTS_TEMPLATE'] | Should -Be '/opt/layer/tpl.md'
        }

        It 'ignores unsupported lines instead of guessing' {
            $script:Parsed.Keys | Should -Not -Contain 'this line is not an assignment'
        }
    }

    Context 'Resolve-AiForgeDirectory' {
        It 'throws for a path that does not exist' {
            { Resolve-AiForgeDirectory -Path (Join-Path $script:Scratch 'nope') -Description 'Project path' } |
                Should -Throw '*does not exist*'
        }
    }
}

Describe 'AiForge.Catalog' {
    BeforeAll {
        $script:Target = Join-Path $script:Scratch 'target'
        New-Item -ItemType Directory -Path $script:Target -Force | Out-Null
        $script:Config = New-AiForgeConfig -ScriptRoot $script:RepoRoot
        $script:Items = New-AiForgeCatalog -Config $script:Config -ProjectPath $script:Target
    }

    It 'starts with the two category rows' {
        @($script:Items | Where-Object { $_.Type -eq 'cat' }).Count | Should -Be 2
    }

    It 'finds skills and agents in the repository' {
        @($script:Items | Where-Object { $_.Type -eq 'skill' }).Count | Should -BeGreaterThan 0
        @($script:Items | Where-Object { $_.Type -eq 'agent' }).Count | Should -BeGreaterThan 0
    }

    It 'marks auto-skills as disabled rather than hiding it' {
        $row = $script:Items | Where-Object { $_.Name -eq 'auto-skills' }
        $row | Should -Not -BeNullOrEmpty
        $row.Disabled | Should -BeTrue
    }

    It 'points every leaf at an existing source' {
        foreach ($item in ($script:Items | Where-Object { $_.Type -in @('skill', 'agent', 'readme') })) {
            Test-Path -LiteralPath $item.Source | Should -BeTrue -Because "$($item.Name) must exist"
        }
    }

    It 'hides an ai-forge skill that a downstream layer supersedes' {
        Test-AiForgeHidden -Name 'gh' -IsSelf $true -HiddenNames @('gh') | Should -BeTrue
    }

    It 'never hides items coming from an extra root' {
        Test-AiForgeHidden -Name 'gh' -IsSelf $false -HiddenNames @('gh') | Should -BeFalse
    }

    It 'detects an already-installed skill' {
        $installed = Join-Path $script:Target '.agents/skills/demo'
        New-Item -ItemType Directory -Path $installed -Force | Out-Null
        'demo' | Set-Content -LiteralPath (Join-Path $installed 'SKILL.md')
        Test-AiForgeSkillInstalled -ProjectPath $script:Target -Name 'demo' | Should -BeTrue
        Test-AiForgeSkillInstalled -ProjectPath $script:Target -Name 'absent' | Should -BeFalse
    }
}

Describe 'AiForge.Menu' {
    BeforeEach {
        $script:MenuTarget = Join-Path $script:Scratch 'menu-target'
        New-Item -ItemType Directory -Path $script:MenuTarget -Force | Out-Null
        $script:MenuConfig = New-AiForgeConfig -ScriptRoot $script:RepoRoot
        $script:MenuItems = New-AiForgeCatalog -Config $script:MenuConfig -ProjectPath $script:MenuTarget
        $script:SkillsCategory = 0
        for ($i = 0; $i -lt $script:MenuItems.Count; $i++) {
            if ($script:MenuItems[$i].Label -eq 'Skills') { $script:SkillsCategory = $i; break }
        }
    }

    It 'checks the whole subtree when a category is toggled' {
        Set-AiForgeSubtreeChecked -Items $script:MenuItems -Index $script:SkillsCategory -Value $true -Confirm:$false
        $checked = @($script:MenuItems | Where-Object { $_.Type -eq 'skill' -and $_.Checked }).Count
        $selectable = @($script:MenuItems | Where-Object { $_.Type -eq 'skill' -and -not $_.Installed }).Count
        $checked | Should -Be $selectable
    }

    It 'aggregates the parent checkbox from its children' {
        Set-AiForgeSubtreeChecked -Items $script:MenuItems -Index $script:SkillsCategory -Value $true -Confirm:$false
        Update-AiForgeParentChecks -Items $script:MenuItems
        $script:MenuItems[$script:SkillsCategory].Checked | Should -BeTrue
    }

    It 'never selects disabled helper commands with -ListAll' {
        Select-AiForgeAllItems -Items $script:MenuItems | Out-Null
        $selection = Get-AiForgeSelection -Items $script:MenuItems
        $selection.Commands.Count | Should -Be 0
    }
}

Describe 'AiForge.Dependencies' {
    It 'renders interchangeable alternatives as "a or b"' {
        $token = Resolve-AiForgeDependencyToken -Token 'aiforge-missing-a|aiforge-missing-b'
        $token.Requirement | Should -Be 'aiforge-missing-a or aiforge-missing-b'
        $token.Available | Should -BeFalse
    }

    It 'reports an available command with the binary that satisfied it' {
        $token = Resolve-AiForgeDependencyToken -Token 'pwsh|powershell'
        $token.Available | Should -BeTrue
        $token.Found | Should -Not -BeNullOrEmpty
    }

    It 'knows the documented command dependencies' {
        Get-AiForgeCommandDependency -Key 'common/create-mr-pr' | Should -Be @('git', 'gh|glab')
        Get-AiForgeCommandDependency -Key 'does/not-exist' | Should -BeNullOrEmpty
    }

    It 'parses the (fallback) marker on MCP tokens' {
        Get-AiForgeMcpDependency -Key 'common/context7-cli' | Should -Be @('context7(fallback)')
    }
}

Describe 'AiForge.Install' {
    Context 'Get-AiForgeCodeBlock' {
        BeforeAll {
            $script:Readme = Join-Path $script:Scratch 'README.md'
            @('# Title', '', '```bash', 'npx skills add demo', '```', '', '```markdown', 'prompt line', '```') |
                Set-Content -LiteralPath $script:Readme
        }

        It 'extracts the first block of the requested language' {
            Get-AiForgeCodeBlock -Path $script:Readme -Language 'bash' | Should -Be 'npx skills add demo'
            Get-AiForgeCodeBlock -Path $script:Readme -Language 'markdown' | Should -Be 'prompt line'
        }

        It 'returns an empty string for a missing file' {
            Get-AiForgeCodeBlock -Path (Join-Path $script:Scratch 'absent.md') -Language 'bash' | Should -Be ''
        }
    }

    Context 'Merge-AiForgeJsonObject' {
        BeforeAll {
            $base = '{"a":{"command":"x"},"shared":{"command":"base","env":{"K":"base","B":"only"}}}' | ConvertFrom-Json
            $overlay = '{"b":{"command":"y"},"shared":{"command":"over","env":{"K":"over"}}}' | ConvertFrom-Json
            $script:Merged = Merge-AiForgeJsonObject -Base $base -Overlay $overlay
        }

        It 'keeps entries that only the base declares' {
            $script:Merged.Contains('a') | Should -BeTrue
        }

        It 'adds entries that only the overlay declares' {
            $script:Merged.Contains('b') | Should -BeTrue
        }

        It 'lets the overlay win on a clash, matching the jq * operator' {
            $script:Merged['shared'].command | Should -Be 'over'
        }

        It 'deep-merges nested objects instead of replacing them' {
            $script:Merged['shared'].env.K | Should -Be 'over'
            $script:Merged['shared'].env.B | Should -Be 'only'
        }

        It 'folds a list of sources starting from $null' {
            $sources = @(
                ('{"a":{"command":"x"}}' | ConvertFrom-Json)
                ('{"b":{"command":"y"}}' | ConvertFrom-Json)
            )
            $accumulator = $null
            foreach ($source in $sources) {
                $accumulator = Merge-AiForgeJsonObject -Base $accumulator -Overlay $source
            }
            @($accumulator.Keys) | Should -Be @('a', 'b')
        }

        It 'does not leak dictionary members when re-merging its own output' {
            $first = Merge-AiForgeJsonObject -Base $null -Overlay ('{"a":{"command":"x"}}' | ConvertFrom-Json)
            $second = Merge-AiForgeJsonObject -Base $first -Overlay ('{"b":{"command":"y"}}' | ConvertFrom-Json)
            $second.Contains('Count') | Should -BeFalse
            $second.Contains('Keys') | Should -BeFalse
            $second.Count | Should -Be 2
        }
    }
}

Describe 'AiForge.Manifest' {
    BeforeAll {
        $script:ManifestTarget = Join-Path $script:Scratch 'manifest-target'
        New-Item -ItemType Directory -Path $script:ManifestTarget -Force | Out-Null
        $config = New-AiForgeConfig -ScriptRoot $script:RepoRoot
        $selection = [pscustomobject]@{
            Skills   = @([pscustomobject]@{ Name = 'demo'; Source = (Join-Path $script:RepoRoot 'skills/common/demo'); Sub = 'common' })
            Agents   = @()
            Remote   = @()
            Commands = @()
            Total    = 1
        }
        $context = New-AiForgeInstallContext -ProjectPath $script:ManifestTarget -Config $config -Selection $selection -DryRun $true
        $script:Manifest = New-AiForgeManifest -Context $context
    }

    It 'uses the shared schema identifier' {
        $script:Manifest['schema'] | Should -Be 'ai-forge/install-manifest@1'
    }

    It 'labels items that come from this repository' {
        $script:Manifest['skills'][0]['source'] | Should -Be 'ai-forge'
    }

    It 'records the install path of every skill' {
        $script:Manifest['skills'][0]['path'] | Should -Be '.agents/skills/demo'
    }

    It 'stamps an ISO-8601 UTC timestamp' {
        $script:Manifest['generatedAt'] | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
    }
}
