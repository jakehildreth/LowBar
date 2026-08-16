# StandardModuleTestConfig.psd1
# Drop this file into your module root so Invoke-StandardModuleTests.ps1
# picks it up automatically. Parameters passed explicitly to that script
# always override the values here.
#
# Generate this file with:
#   .\New-StandardModuleTestConfig.ps1 -ModuleRoot 'C:\path\to\MyModule'
#
# Available presets:
#   Default  -- all checks enabled (same as leaving every key at $true)
#   Lenient  -- disables the most contentious checks (OTBS, error handling)
#   Strict   -- identical to Default today; reserved for future stricter rules

@{
    # -------------------------------------------------------------------------
    # Module.FunctionConventions.Tests.ps1
    # -------------------------------------------------------------------------

    # Require [OutputType()] on every public function.
    # Disable if your module returns loosely-typed [PSCustomObject] results
    # and the shape cannot be predicted at author time.
    EnableOutputTypeCheck  = $true
    ExcludeOutputTypeCheck = @()   # function names to exempt, e.g. @('Get-Foo')

    # -------------------------------------------------------------------------
    # Module.Formatting.Tests.ps1
    # -------------------------------------------------------------------------

    # Require opening braces on the same line as the preceding statement (OTBS).
    # Disable if your team uses Allman-style bracing.
    EnableOTBSCheck  = $true
    ExcludeOTBSFiles = @()   # file basenames to exempt, e.g. @('Get-Foo.ps1')

    # -------------------------------------------------------------------------
    # Module.AdvancedFunction.Tests.ps1
    # -------------------------------------------------------------------------

    # Prefer $PSCmdlet.WriteError() / ThrowTerminatingError() over
    # Write-Error and throw inside advanced functions.
    # Disable if the module uses catch/re-throw extensively.
    EnableErrorHandlingCheck  = $true
    ExcludeErrorHandlingCheck = @()   # function names to exempt

    # Disallow assigning to preference variables ($ErrorActionPreference, etc.)
    # inside function scope.
    EnablePreferenceVarCheck  = $true
    ExcludePreferenceVarCheck = @()   # function names to exempt

    # -------------------------------------------------------------------------
    # Module.Structure.Tests.ps1
    # -------------------------------------------------------------------------

    # Require a *.Tests.ps1 file for every public function.
    # Disable for modules still building out initial test coverage.
    EnableTestCoverageCheck  = $true
    ExcludeTestCoverageCheck = @()   # function names to exempt
}
