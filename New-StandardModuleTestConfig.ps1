#requires -Version 5.1
<#
.SYNOPSIS
    Generates a StandardModuleTestConfig.psd1 in the target module root.

.DESCRIPTION
    Creates a StandardModuleTestConfig.psd1 configuration file that controls
    which community standard checks Invoke-StandardModuleTests.ps1 enforces.

    Start with a preset and override individual checks as needed:

      Preset Default  -- all checks enabled
      Preset Lenient  -- disables the most contentious checks:
                         OTBS brace style and the error handling preference
      Preset Strict   -- identical to Default today; reserved for future
                         stricter rules that will be off by default

    Individual -Enable* and -Disable* switches override the preset for that
    specific check.

.PARAMETER ModuleRoot
    Absolute path to the module root directory (where the .psd1 manifest lives).
    The config file is written to this directory.

.PARAMETER Preset
    Starting point for the configuration. Defaults to 'Default'.

.PARAMETER DisableOutputTypeCheck
    Disable the [OutputType()] requirement for this module.

.PARAMETER DisableOTBSCheck
    Disable the OTBS brace-style check for this module.

.PARAMETER DisableErrorHandlingCheck
    Disable the Write-Error / throw preference check for this module.

.PARAMETER DisablePreferenceVarCheck
    Disable the preference variable assignment check for this module.

.PARAMETER DisableTestCoverageCheck
    Disable the per-function test file coverage check for this module.

.PARAMETER Force
    Overwrite an existing StandardModuleTestConfig.psd1 without prompting.

.PARAMETER ReportFormat
    Default human-readable reports: Html, Markdown, Terminal, All, or None.
    Combine concrete formats. All and None must each be used alone.
    No human-readable reports are selected by default. XML remains enabled.

.EXAMPLE
    .\New-StandardModuleTestConfig.ps1 -ModuleRoot 'C:\Code\MyModule'

    Generates a Default config (all checks on).

.EXAMPLE
    .\New-StandardModuleTestConfig.ps1 -ModuleRoot 'C:\Code\MyModule' -Preset Lenient

    Generates a Lenient config with OTBS and error handling checks disabled.

.EXAMPLE
    .\New-StandardModuleTestConfig.ps1 -ModuleRoot 'C:\Code\MyModule' -DisableOTBSCheck

    Generates a Default config with only the OTBS check disabled.

.OUTPUTS
    [System.IO.FileInfo] The generated config file.

.NOTES
    The generated file can be edited by hand at any time.
    Invoke-StandardModuleTests.ps1 reads it automatically from the module root.
    Explicit parameters passed to Invoke-StandardModuleTests.ps1 always override
    the config file.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([System.IO.FileInfo])]
param(
    [Parameter(Mandatory)]
    [string]$ModuleRoot,

    [Parameter()]
    [ValidateSet('Default', 'Lenient', 'Strict')]
    [string]$Preset = 'Default',

    [Parameter()]
    [switch]$DisableOutputTypeCheck,

    [Parameter()]
    [switch]$DisableOTBSCheck,

    [Parameter()]
    [switch]$DisableErrorHandlingCheck,

    [Parameter()]
    [switch]$DisablePreferenceVarCheck,

    [Parameter()]
    [switch]$DisableTestCoverageCheck,

    [Parameter()]
    [ValidateSet('Html', 'Markdown', 'Terminal', 'All', 'None')]
    [string[]]$ReportFormat = @(),

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Private\Reporting.ps1')
$null = Resolve-StandardReportFormat -Selection $ReportFormat
$reportFormatLiteral = ($ReportFormat | ForEach-Object { "'$_'" }) -join ', '

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

if (-not (Get-ChildItem -Path $ModuleRoot -Filter '*.psd1' -File)) {
    $PSCmdlet.ThrowTerminatingError(
        [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new("No .psd1 manifest found in '$ModuleRoot'. Is this a module root?"),
            'NoManifestFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $ModuleRoot
        )
    )
}

$outputPath = Join-Path $ModuleRoot 'StandardModuleTestConfig.psd1'

if ((Test-Path $outputPath) -and -not $Force) {
    $PSCmdlet.ThrowTerminatingError(
        [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new("'$outputPath' already exists. Use -Force to overwrite."),
            'ConfigAlreadyExists',
            [System.Management.Automation.ErrorCategory]::ResourceExists,
            $outputPath
        )
    )
}

# Apply preset defaults
$settings = switch ($Preset) {
    'Lenient' {
        @{
            EnableOutputTypeCheck    = $true
            EnableOTBSCheck          = $false   # disabled: team may use Allman style
            EnableErrorHandlingCheck = $false   # disabled: catch/re-throw is common
            EnablePreferenceVarCheck = $true
            EnableTestCoverageCheck  = $true
        }
    }
    default {
        # Default and Strict are identical today
        @{
            EnableOutputTypeCheck    = $true
            EnableOTBSCheck          = $true
            EnableErrorHandlingCheck = $true
            EnablePreferenceVarCheck = $true
            EnableTestCoverageCheck  = $true
        }
    }
}

# Apply per-check overrides
if ($DisableOutputTypeCheck)    { $settings.EnableOutputTypeCheck    = $false }
if ($DisableOTBSCheck)          { $settings.EnableOTBSCheck          = $false }
if ($DisableErrorHandlingCheck) { $settings.EnableErrorHandlingCheck = $false }
if ($DisablePreferenceVarCheck) { $settings.EnablePreferenceVarCheck = $false }
if ($DisableTestCoverageCheck)  { $settings.EnableTestCoverageCheck  = $false }

$boolStr = { if ($args[0]) { '$true' } else { '$false' } }

$content = @"
# StandardModuleTestConfig.psd1
# Generated by New-StandardModuleTestConfig.ps1 on $(Get-Date -Format 'yyyy-MM-dd') using preset '$Preset'.
# Edit this file to adjust which community standard checks are enforced.
# Invoke-StandardModuleTests.ps1 reads it automatically from the module root.
# Explicit parameters passed to that script always override these values.

@{
    # Optional Html, Markdown, Terminal, All, or None. XML is always enabled.
    ReportFormat = @($reportFormatLiteral)

    # -------------------------------------------------------------------------
    # Module.FunctionConventions.Tests.ps1
    # -------------------------------------------------------------------------
    EnableOutputTypeCheck  = $(&$boolStr $settings.EnableOutputTypeCheck)
    ExcludeOutputTypeCheck = @()   # function names to exempt, e.g. @('Get-Foo')

    # -------------------------------------------------------------------------
    # Module.Formatting.Tests.ps1
    # -------------------------------------------------------------------------
    EnableOTBSCheck  = $(&$boolStr $settings.EnableOTBSCheck)
    ExcludeOTBSFiles = @()   # file basenames to exempt, e.g. @('Get-Foo.ps1')

    # -------------------------------------------------------------------------
    # Module.AdvancedFunction.Tests.ps1
    # -------------------------------------------------------------------------
    EnableErrorHandlingCheck  = $(&$boolStr $settings.EnableErrorHandlingCheck)
    ExcludeErrorHandlingCheck = @()   # function names to exempt

    EnablePreferenceVarCheck  = $(&$boolStr $settings.EnablePreferenceVarCheck)
    ExcludePreferenceVarCheck = @()   # function names to exempt

    # -------------------------------------------------------------------------
    # Module.Structure.Tests.ps1
    # -------------------------------------------------------------------------
    EnableTestCoverageCheck  = $(&$boolStr $settings.EnableTestCoverageCheck)
    ExcludeTestCoverageCheck = @()   # function names to exempt
}
"@

if ($PSCmdlet.ShouldProcess($outputPath, 'Write StandardModuleTestConfig.psd1')) {
    Set-Content -Path $outputPath -Value $content -Encoding UTF8
    Get-Item -Path $outputPath
}
