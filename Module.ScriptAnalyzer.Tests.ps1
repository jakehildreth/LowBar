#requires -Version 5.1
# Reusable PSScriptAnalyzer tests for any PowerShell module.
# Scans Classes/, Private/, and Public/ by default; override via $ScanPaths.
# Usage via New-PesterContainer:
#   $container = New-PesterContainer -Path './Module.ScriptAnalyzer.Tests.ps1' `
#       -Data @{ ModuleRoot = 'C:\path\to\MyModule' }
#   Invoke-Pester -Container $container

param(
    # Absolute path to the module root directory.
    [Parameter(Mandatory)]
    [string]$ModuleRoot,

    # Override which subdirectories are scanned. Defaults to Classes, Private, Public.
    [Parameter()]
    [string[]]$ScanPaths,

    # Path to a PSScriptAnalyzerSettings.psd1 file. Falls back to module root, then defaults.
    [Parameter()]
    [string]$SettingsPath
)

BeforeDiscovery {
    if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable -ErrorAction SilentlyContinue)) {
        Write-Warning 'PSScriptAnalyzer module not found - ScriptAnalyzer tests will be skipped.'
        $script:PSAAvailable = $false
        $script:fileCases    = @()
    } else {
        $script:PSAAvailable = $true

        # Resolve scan paths
        $resolvedPaths = if ($ScanPaths) {
            $ScanPaths | ForEach-Object { Join-Path $ModuleRoot $_ }
        } else {
            @('Classes', 'Private', 'Public') |
                ForEach-Object { Join-Path $ModuleRoot $_ } |
                Where-Object { Test-Path $_ }
        }

        # Resolve settings file
        $resolvedSettings = if ($SettingsPath -and (Test-Path $SettingsPath)) {
            $SettingsPath
        } else {
            $rootSettings = Join-Path $ModuleRoot 'PSScriptAnalyzerSettings.psd1'
            if (Test-Path $rootSettings) { $rootSettings } else { $null }
        }

        $script:fileCases = if ($resolvedPaths) {
            Get-ChildItem -Path $resolvedPaths -Recurse -Include '*.ps1', '*.psm1' |
                Sort-Object FullName |
                ForEach-Object {
                    @{
                        Name         = $_.Name
                        FullName     = $_.FullName
                        SourcePath   = $_.FullName
                        SettingsPath = $resolvedSettings
                    }
                }
        } else { @() }
    }
}

Describe 'PSScriptAnalyzer' -Tag 'Unit', 'ScriptAnalyzer' -ForEach @(@{ SourceScope = 'Module' }) {
    It 'PSScriptAnalyzer module should be available' {
        Get-Module -Name PSScriptAnalyzer -ListAvailable | Should -Not -BeNullOrEmpty -Because 'Recommendation: Install PSScriptAnalyzer 1.25.0 or later in a directory on PSModulePath.'
    }

    Context 'Per-file analysis' -Skip:(-not $script:PSAAvailable) {
        It 'should pass PSScriptAnalyzer for <Name>' -ForEach $script:fileCases {
            $invokeParams = @{
                Path     = $FullName
                Severity = 'Warning', 'Error'
            }
            if ($SettingsPath) {
                $invokeParams['Settings'] = $SettingsPath
            }

            $violations = Invoke-ScriptAnalyzer @invokeParams

            if ($violations) {
                $detail = ($violations | ForEach-Object {
                    "  [$($_.Severity)] $($_.RuleName) at line $($_.Line): $($_.Message)"
                }) -join "`n"
                $violations | Should -BeNullOrEmpty -Because "`n$detail`nRecommendation: Correct each reported ScriptAnalyzer rule violation at the listed source line."
            } else {
                $violations | Should -BeNullOrEmpty
            }
        }
    }
}
