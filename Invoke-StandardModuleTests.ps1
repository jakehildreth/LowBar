#requires -Version 5.1
<#
.SYNOPSIS
    Runs the standard module test suite against a given PowerShell module.

.DESCRIPTION
    Invokes the full standard module test suite from this same directory:
      Module.Manifest.Tests.ps1
      Module.ScriptAnalyzer.Tests.ps1
      Module.CBH.Tests.ps1
      Module.Structure.Tests.ps1
      Module.FunctionConventions.Tests.ps1
      Module.Formatting.Tests.ps1
      Module.AdvancedFunction.Tests.ps1
    Each test file is wired up via New-PesterContainer so parameters are passed
    cleanly without modifying the test files.

    Results are written to the module's Tests/ directory (or $OutputPath if
    specified) in NUnitXml format.

    If a StandardModuleTestConfig.psd1 exists in $ModuleRoot, it is loaded
    automatically to set defaults for each check. Explicit parameters always
    override the config file.

.PARAMETER ModuleRoot
    Absolute path to the root of the module to test.

.PARAMETER PublicFunctionPaths
    Subdirectory names under ModuleRoot that contain public function scripts.
    Defaults to @('Public').

.PARAMETER ScanPaths
    Subdirectory names to pass to the ScriptAnalyzer test.
    Defaults to Classes, Private, Public (whichever exist).

.PARAMETER SettingsPath
    Path to a PSScriptAnalyzerSettings.psd1. Falls back to one at ModuleRoot.

.PARAMETER ConfigPath
    Path to a StandardModuleTestConfig.psd1. Falls back to one at ModuleRoot.
    Use this to share a single config across multiple modules.

.PARAMETER ExcludeOutputTypeCheck
    Function names to skip the [OutputType()] check.

.PARAMETER SourcePaths
    Subdirectory names for Module.Formatting.Tests.ps1.

.PARAMETER SkipOTBSCheck
    Disable the OTBS brace-style check.

.PARAMETER ExcludeOTBSFiles
    File basenames to exclude from the OTBS check.

.PARAMETER SkipErrorHandlingCheck
    Disable the Write-Error / throw check.

.PARAMETER ExcludeErrorHandlingCheck
    Function names to exclude from the Write-Error / throw check.

.PARAMETER SkipPreferenceVarCheck
    Disable the preference variable assignment check.

.PARAMETER ExcludePreferenceVarCheck
    Function names to exclude from the preference variable assignment check.

.PARAMETER SkipTestCoverageCheck
    Disable the test-file coverage check for all functions.

.PARAMETER ExcludeTestCoverageCheck
    Function names to skip the test-file coverage check.

.PARAMETER TestsPath
    Directory to search for *.Tests.ps1 files. Defaults to <ModuleRoot>/Tests.

.PARAMETER OutputPath
    Directory to write NUnitXml results. Defaults to <ModuleRoot>/Tests.

.PARAMETER Tag
    Pester tag filter. Defaults to @('Unit').

.PARAMETER ExcludeTag
    Pester exclude tag filter. Defaults to @('Integration').

.PARAMETER Passthru
    Return the Pester result object instead of writing to host.

.EXAMPLE
    .\Invoke-StandardModuleTests.ps1 -ModuleRoot 'C:\Code\MyModule'

    Runs the suite, reading StandardModuleTestConfig.psd1 from the module root
    if present.

.EXAMPLE
    .\Invoke-StandardModuleTests.ps1 -ModuleRoot 'C:\Code\MyModule' -SkipOTBSCheck

    Overrides the config file and disables the OTBS check for this run.

.OUTPUTS
    [Pester.Run] when -Passthru is specified; nothing otherwise.

.NOTES
    Requires Pester 5.2+ and PSScriptAnalyzer (for ScriptAnalyzer tests).
    Drop this script and all *.Tests.ps1 files into any shared location;
    point -ModuleRoot at any module to run the full standard suite.
    Generate a config file with: .\New-StandardModuleTestConfig.ps1 -ModuleRoot '...'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ModuleRoot,

    [Parameter()]
    [string[]]$PublicFunctionPaths = @('Public'),

    [Parameter()]
    [string[]]$ScanPaths,

    [Parameter()]
    [string]$SettingsPath,

    [Parameter()]
    [string]$ConfigPath,

    # Module.FunctionConventions.Tests.ps1 opt-outs
    [Parameter()]
    [string[]]$ExcludeOutputTypeCheck = @(),

    # Module.Formatting.Tests.ps1 opt-outs
    [Parameter()]
    [string[]]$SourcePaths,

    [Parameter()]
    [switch]$SkipOTBSCheck,

    [Parameter()]
    [string[]]$ExcludeOTBSFiles = @(),

    # Module.AdvancedFunction.Tests.ps1 opt-outs
    [Parameter()]
    [switch]$SkipErrorHandlingCheck,

    [Parameter()]
    [string[]]$ExcludeErrorHandlingCheck = @(),

    [Parameter()]
    [switch]$SkipPreferenceVarCheck,

    [Parameter()]
    [string[]]$ExcludePreferenceVarCheck = @(),

    # Module.Structure.Tests.ps1 opt-outs
    [Parameter()]
    [switch]$SkipTestCoverageCheck,

    [Parameter()]
    [string[]]$ExcludeTestCoverageCheck = @(),

    [Parameter()]
    [string]$TestsPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string[]]$Tag = @('Unit'),

    [Parameter()]
    [string[]]$ExcludeTag = @('Integration'),

    [Parameter()]
    [switch]$Passthru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testLibRoot = $PSScriptRoot

if (-not (Test-Path $ModuleRoot)) {
    $PSCmdlet.ThrowTerminatingError(
        [System.Management.Automation.ErrorRecord]::new(
            [System.IO.DirectoryNotFoundException]::new("ModuleRoot '$ModuleRoot' does not exist."),
            'ModuleRootNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $ModuleRoot
        )
    )
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $ModuleRoot 'Tests'
    if (-not (Test-Path $OutputPath)) {
        $null = New-Item -ItemType Directory -Path $OutputPath -Force
    }
}

# --- Load config file (StandardModuleTestConfig.psd1) ---

$cfg = $null
$resolvedConfigPath = if ($ConfigPath -and (Test-Path $ConfigPath)) {
    $ConfigPath
} else {
    $rootConfig = Join-Path $ModuleRoot 'StandardModuleTestConfig.psd1'
    if (Test-Path $rootConfig) { $rootConfig } else { $null }
}
if ($resolvedConfigPath) {
    $cfg = Import-PowerShellDataFile -Path $resolvedConfigPath
}

# Resolve each effective setting: explicit param > config file > built-in default.
# $PSBoundParameters tells us which params the caller explicitly provided.
$bp = $PSBoundParameters

$effectiveSkipOutputType    = if ($bp.ContainsKey('ExcludeOutputTypeCheck')) {
    $ExcludeOutputTypeCheck
} elseif ($cfg -and $cfg.ContainsKey('ExcludeOutputTypeCheck')) {
    $cfg.ExcludeOutputTypeCheck
} else { @() }

# EnableOutputTypeCheck = $false means skip all; combine with per-function excludes
if (-not $bp.ContainsKey('ExcludeOutputTypeCheck') -and
    $cfg -and $cfg.ContainsKey('EnableOutputTypeCheck') -and
    -not $cfg.EnableOutputTypeCheck) {
    # Signal "skip all" by using a sentinel; the test handles this via SkipOutputTypeCheck
    # which isn't a param -- instead we pass all discovered names. For simplicity we
    # use a well-known magic value that Module.FunctionConventions accepts: pass '*'.
    # Actually we handle this at the container level below via $effectiveSkipOutputType.
    $effectiveSkipAllOutputType = $true
} else {
    $effectiveSkipAllOutputType = $false
}

$effectiveSkipOTBS = if ($bp.ContainsKey('SkipOTBSCheck')) {
    $SkipOTBSCheck.IsPresent
} elseif ($cfg -and $cfg.ContainsKey('EnableOTBSCheck')) {
    -not $cfg.EnableOTBSCheck
} else { $false }

$effectiveExcludeOTBSFiles = if ($bp.ContainsKey('ExcludeOTBSFiles')) {
    $ExcludeOTBSFiles
} elseif ($cfg -and $cfg.ContainsKey('ExcludeOTBSFiles')) {
    $cfg.ExcludeOTBSFiles
} else { @() }

$effectiveSkipErrorHandling = if ($bp.ContainsKey('SkipErrorHandlingCheck')) {
    $SkipErrorHandlingCheck.IsPresent
} elseif ($cfg -and $cfg.ContainsKey('EnableErrorHandlingCheck')) {
    -not $cfg.EnableErrorHandlingCheck
} else { $false }

$effectiveExcludeErrorHandling = if ($bp.ContainsKey('ExcludeErrorHandlingCheck')) {
    $ExcludeErrorHandlingCheck
} elseif ($cfg -and $cfg.ContainsKey('ExcludeErrorHandlingCheck')) {
    $cfg.ExcludeErrorHandlingCheck
} else { @() }

$effectiveSkipPrefVar = if ($bp.ContainsKey('SkipPreferenceVarCheck')) {
    $SkipPreferenceVarCheck.IsPresent
} elseif ($cfg -and $cfg.ContainsKey('EnablePreferenceVarCheck')) {
    -not $cfg.EnablePreferenceVarCheck
} else { $false }

$effectiveExcludePrefVar = if ($bp.ContainsKey('ExcludePreferenceVarCheck')) {
    $ExcludePreferenceVarCheck
} elseif ($cfg -and $cfg.ContainsKey('ExcludePreferenceVarCheck')) {
    $cfg.ExcludePreferenceVarCheck
} else { @() }

$effectiveSkipTestCoverage = if ($bp.ContainsKey('SkipTestCoverageCheck')) {
    $SkipTestCoverageCheck.IsPresent
} elseif ($cfg -and $cfg.ContainsKey('EnableTestCoverageCheck')) {
    -not $cfg.EnableTestCoverageCheck
} else { $false }

$effectiveExcludeTestCoverage = if ($bp.ContainsKey('ExcludeTestCoverageCheck')) {
    $ExcludeTestCoverageCheck
} elseif ($cfg -and $cfg.ContainsKey('ExcludeTestCoverageCheck')) {
    $cfg.ExcludeTestCoverageCheck
} else { @() }

# --- Build containers ---

$manifestData = @{ ModuleRoot = $ModuleRoot }

$psaData = @{ ModuleRoot = $ModuleRoot }
if ($ScanPaths)    { $psaData['ScanPaths']    = $ScanPaths }
if ($SettingsPath) { $psaData['SettingsPath'] = $SettingsPath }

$cbhData = @{
    ModuleRoot          = $ModuleRoot
    PublicFunctionPaths = $PublicFunctionPaths
}

$structureData = @{
    ModuleRoot               = $ModuleRoot
    PublicFunctionPaths      = $PublicFunctionPaths
    SkipTestCoverageCheck    = $effectiveSkipTestCoverage
    ExcludeTestCoverageCheck = $effectiveExcludeTestCoverage
}
if ($TestsPath) { $structureData['TestsPath'] = $TestsPath }

$conventionsData = @{
    ModuleRoot             = $ModuleRoot
    PublicFunctionPaths    = $PublicFunctionPaths
    SkipOutputTypeCheck    = $effectiveSkipAllOutputType
    ExcludeOutputTypeCheck = $effectiveSkipOutputType
}

$formattingData = @{
    ModuleRoot       = $ModuleRoot
    SkipOTBSCheck    = $effectiveSkipOTBS
    ExcludeOTBSFiles = $effectiveExcludeOTBSFiles
}
if ($SourcePaths) { $formattingData['SourcePaths'] = $SourcePaths }

$advancedData = @{
    ModuleRoot                = $ModuleRoot
    PublicFunctionPaths       = $PublicFunctionPaths
    SkipErrorHandlingCheck    = $effectiveSkipErrorHandling
    ExcludeErrorHandlingCheck = $effectiveExcludeErrorHandling
    SkipPreferenceVarCheck    = $effectiveSkipPrefVar
    ExcludePreferenceVarCheck = $effectiveExcludePrefVar
}

$containers = @(
    New-PesterContainer -Path (Join-Path $testLibRoot 'Module.Manifest.Tests.ps1')            -Data $manifestData
    New-PesterContainer -Path (Join-Path $testLibRoot 'Module.ScriptAnalyzer.Tests.ps1')      -Data $psaData
    New-PesterContainer -Path (Join-Path $testLibRoot 'Module.CBH.Tests.ps1')                 -Data $cbhData
    New-PesterContainer -Path (Join-Path $testLibRoot 'Module.Structure.Tests.ps1')           -Data $structureData
    New-PesterContainer -Path (Join-Path $testLibRoot 'Module.FunctionConventions.Tests.ps1') -Data $conventionsData
    New-PesterContainer -Path (Join-Path $testLibRoot 'Module.Formatting.Tests.ps1')          -Data $formattingData
    New-PesterContainer -Path (Join-Path $testLibRoot 'Module.AdvancedFunction.Tests.ps1')    -Data $advancedData
)

# --- Configure and run ---

$moduleName = (Get-ChildItem -Path $ModuleRoot -Filter '*.psd1' -File | Select-Object -First 1).BaseName
$resultFile = Join-Path $OutputPath "$moduleName.StandardTests.xml"

$config = New-PesterConfiguration
$config.Run.Container              = $containers
$config.Run.Exit                   = $false
$config.Output.Verbosity           = 'Detailed'
$config.Output.StackTraceVerbosity = 'Filtered'
$config.Filter.Tag                 = $Tag
$config.Filter.ExcludeTag          = $ExcludeTag
$config.TestResult.Enabled         = $true
$config.TestResult.OutputFormat    = 'NUnitXml'
$config.TestResult.OutputPath      = $resultFile
$config.Should.ErrorAction         = 'Continue'

$result = Invoke-Pester -Configuration $config

if ($Passthru.IsPresent) {
    return $result
}

