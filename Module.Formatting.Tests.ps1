#requires -Version 5.1
# Reusable file formatting tests for any PowerShell module.
# Checks applied to all .ps1, .psm1, and .psd1 source files.
#
# Checks per source file:
#   [+] Encoding is UTF-8 or UTF-8-BOM (not UTF-16 or UTF-32)
#   [+] No trailing whitespace on any line
#   [+] No tab characters
#   [+] File ends with a newline character
#   [+] No backtick line continuations (use splatting or natural line breaks)
#   [+] Opening braces are on the same line as the preceding statement (OTBS style)
#
# Opt-out for OTBS check
# ----------------------
# The OTBS check flags every opening brace ({) that is not on the same line
# as the preceding non-whitespace token. @{ } hashtable literals use the
# AtCurly token and are NOT checked.
#
# To skip the OTBS check for the entire suite:
#   -Data @{ ModuleRoot = '...'; SkipOTBSCheck = $true }
#
# To skip specific files by filename (basename):
#   -Data @{ ModuleRoot = '...'; ExcludeOTBSFiles = @('Get-Foo.ps1', 'Helpers.ps1') }
#
# Usage via New-PesterContainer:
#   $container = New-PesterContainer -Path './Module.Formatting.Tests.ps1' `
#       -Data @{ ModuleRoot = 'C:\path\to\MyModule' }
#   Invoke-Pester -Container $container

param(
    # Absolute path to the module root directory (where the .psd1 lives).
    [Parameter(Mandatory)]
    [string]$ModuleRoot,

    # Source subdirectories to scan. Defaults to Public, Private, Classes, Enums
    # plus the root .psm1. Pass explicit paths to override.
    [Parameter()]
    [string[]]$SourcePaths,

    # Disable the OTBS brace-style check for all files.
    [Parameter()]
    [bool]$SkipOTBSCheck = $false,

    # File basenames (e.g. 'Get-Foo.ps1') to exclude from the OTBS check only.
    [Parameter()]
    [string[]]$ExcludeOTBSFiles = @()
)

BeforeDiscovery {
    $manifestFile = Get-ChildItem -Path $ModuleRoot -Filter '*.psd1' -File |
        Select-Object -First 1
    if (-not $manifestFile) { throw "No .psd1 manifest found in '$ModuleRoot'." }
    $script:moduleName = $manifestFile.BaseName

    $resolvedPaths = if ($SourcePaths) {
        $SourcePaths | ForEach-Object { Join-Path $ModuleRoot $_ }
    } else {
        @('Public', 'Private', 'Classes', 'Enums') |
            ForEach-Object { Join-Path $ModuleRoot $_ } |
            Where-Object { Test-Path $_ }
    }

    $dirFiles = if ($resolvedPaths) {
        @(Get-ChildItem -Path $resolvedPaths -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File)
    } else { @() }

    $rootPsm1 = @(Get-ChildItem -Path $ModuleRoot -Filter '*.psm1' -File)
    $allFiles  = @($dirFiles) + @($rootPsm1) |
        Sort-Object FullName -Unique

    $fileCases = foreach ($file in $allFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)

        # Reject UTF-16 LE/BE and UTF-32 LE/BE BOMs; allow UTF-8 with or without BOM.
        $badEncoding = (
            ($bytes.Length -ge 4 -and
             $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and
             $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) -or  # UTF-32 LE
            ($bytes.Length -ge 4 -and
             $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and
             $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) -or  # UTF-32 BE
            ($bytes.Length -ge 2 -and
             $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and
             -not ($bytes.Length -ge 4 -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00)) -or  # UTF-16 LE
            ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF)             # UTF-16 BE
        )

        $lines = @(Get-Content -Path $file.FullName -Encoding UTF8)

        $trailingWsLines = @(
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '[ \t]+$') { $i + 1 }
            }
        )

        $tabLines = @(
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '\t') { $i + 1 }
            }
        )

        $hasEofNewline = $bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -eq 0x0A

        # Use AST tokens so backtick check is parse-aware and skips string contents.
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName, [ref]$tokens, [ref]$null
        ) | Out-Null

        $backtickLines = @(
            $tokens |
                Where-Object { $_.Kind -eq [System.Management.Automation.Language.TokenKind]::LineContinuation } |
                ForEach-Object { $_.Extent.StartLineNumber }
        )

        $otbsSkip       = $SkipOTBSCheck -or ($ExcludeOTBSFiles -contains $file.Name)
        $otbsViolations = if (-not $otbsSkip) {
            $lCurlyTokens = @(
                $tokens | Where-Object {
                    $_.Kind -eq [System.Management.Automation.Language.TokenKind]::LCurly
                }
            )
            @(foreach ($brace in $lCurlyTokens) {
                # Tokens are in source order; [-1] gives the nearest preceding token.
                $prevToken = @(
                    $tokens | Where-Object {
                        $_.Extent.EndOffset -lt $brace.Extent.StartOffset -and
                        $_.Kind -notin @(
                            [System.Management.Automation.Language.TokenKind]::NewLine,
                            [System.Management.Automation.Language.TokenKind]::LineContinuation,
                            [System.Management.Automation.Language.TokenKind]::Comment
                        )
                    }
                )[-1]

                if ($prevToken -and
                    $prevToken.Extent.EndLineNumber -lt $brace.Extent.StartLineNumber) {
                    "Line $($brace.Extent.StartLineNumber): '{' is not on the same line as the preceding statement"
                }
            })
        } else { @() }

        @{
            FileName        = $file.Name
            FilePath        = $file.FullName
            BadEncoding     = $badEncoding
            TrailingWsLines = $trailingWsLines
            TabLines        = $tabLines
            HasEofNewline   = $hasEofNewline
            BacktickLines   = $backtickLines
            OTBSViolations  = $otbsViolations
            SkipOTBS        = $otbsSkip
        }
    }

    $script:fileCases = @($fileCases)
}

Describe 'File Formatting - <ModuleName>' -Tag 'Unit', 'Formatting' {
    Context '<FileName>' -ForEach $script:fileCases {
        It 'should not use UTF-16 or UTF-32 encoding' {
            $BadEncoding | Should -BeFalse `
                -Because "'$FileName' must be UTF-8 or UTF-8 with BOM, not UTF-16 or UTF-32"
        }

        It 'should have no trailing whitespace' {
            $TrailingWsLines | Should -BeNullOrEmpty `
                -Because "'$FileName' has trailing whitespace on line(s): $($TrailingWsLines -join ', ')"
        }

        It 'should not use tab characters' {
            $TabLines | Should -BeNullOrEmpty `
                -Because "'$FileName' uses tab characters on line(s): $($TabLines -join ', '). Use spaces for indentation."
        }

        It 'should end with a newline' {
            $HasEofNewline | Should -BeTrue `
                -Because "'$FileName' does not end with a newline. Most editors add this automatically."
        }

        It 'should not use backtick line continuations' {
            $BacktickLines | Should -BeNullOrEmpty `
                -Because "'$FileName' uses backtick continuations on line(s): $($BacktickLines -join ', '). Use splatting (@params) or natural line breaks (e.g. after a pipe or opening brace) instead."
        }

        It 'opening braces should be on the same line as the preceding statement (OTBS)' -Skip:$SkipOTBS {
            $OTBSViolations | Should -BeNullOrEmpty `
                -Because "'$FileName' has OTBS violations: $($OTBSViolations -join '; '). To opt out: set SkipOTBSCheck = `$true or add the filename to ExcludeOTBSFiles."
        }
    }
}
