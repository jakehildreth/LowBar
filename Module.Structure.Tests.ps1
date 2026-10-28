#requires -Version 5.1
# Reusable file structure tests for any PowerShell module.
# Verifies conventions around public function file layout and manifest alignment.
#
# Checks per public .ps1 file:
#   [+] Each file contains exactly one function definition
#   [+] The file name matches the function name it contains
#
# Checks for manifest alignment:
#   [+] Every discovered public function is listed in FunctionsToExport
#   [+] Every name in FunctionsToExport has a corresponding public .ps1 file
#
# Checks for test coverage:
#   [+] Every public function has a corresponding *.Tests.ps1 file (opt-out: $ExcludeTestCoverageCheck)
#
# Opt-out for test coverage check
# --------------------------------
# Add function names to skip in $ExcludeTestCoverageCheck:
#   -Data @{
#       ModuleRoot               = 'C:\path\to\MyModule'
#       ExcludeTestCoverageCheck = @('Get-Foo', 'Set-Bar')
#   }
#
# Usage via New-PesterContainer:
#   $container = New-PesterContainer -Path './Module.Structure.Tests.ps1' `
#       -Data @{ ModuleRoot = 'C:\path\to\MyModule' }
#   Invoke-Pester -Container $container

param(
    # Absolute path to the module root directory (where the .psd1 lives).
    [Parameter(Mandatory)]
    [string]$ModuleRoot,

    # Subdirectory/ies under ModuleRoot containing public function scripts.
    # Defaults to 'Public'. Can be overridden for flat module layouts.
    [Parameter()]
    [string[]]$PublicFunctionPaths = @('Public'),

    # Disable the test-file coverage check for all functions in this module.
    [Parameter()]
    [bool]$SkipTestCoverageCheck = $false,

    # Function names to skip the test-file coverage check.
    # Example: @('Get-Foo', 'Set-Bar')
    [Parameter()]
    [string[]]$ExcludeTestCoverageCheck = @(),

    # Directory to search for *.Tests.ps1 files. Defaults to <ModuleRoot>/Tests.
    [Parameter()]
    [string]$TestsPath
)

BeforeDiscovery {
    $manifestFile = Get-ChildItem -Path $ModuleRoot -Filter '*.psd1' -File |
        Select-Object -First 1

    if (-not $manifestFile) {
        throw "No .psd1 manifest found in '$ModuleRoot'."
    }

    $manifestPath = $manifestFile.FullName
    $moduleName   = $manifestFile.BaseName

    # Collect public .ps1 files
    $publicPaths = $PublicFunctionPaths |
        ForEach-Object { Join-Path $ModuleRoot $_ } |
        Where-Object { Test-Path $_ }

    $publicFiles = if ($publicPaths) {
        @(Get-ChildItem -Path $publicPaths -Filter '*.ps1' -Recurse -File)
    } else {
        @()
    }

    # Parse each file with the AST to count and name function definitions
    $fileCases = foreach ($file in $publicFiles) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$null,
            [ref]$null
        )

        $functionDefs = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $false))

        @{
            FileName      = $file.Name
            FilePath      = $file.FullName
            SourcePath    = $file.FullName
            FunctionCount = $functionDefs.Count
            FunctionNames = @($functionDefs | ForEach-Object { $_.Name })
            ExpectedName  = $file.BaseName
        }
    }

    # Load manifest FunctionsToExport
    $manifest      = Test-ModuleManifest -Path $manifestPath -ErrorAction SilentlyContinue
    $exportedNames = @($manifest.ExportedFunctions.Keys)

    # Discovered function names from files that contain exactly one function
    $discoveredNames = @(
        $fileCases |
            Where-Object { $_.FunctionCount -eq 1 } |
            ForEach-Object { $_.FunctionNames[0] }
    )

    # Per-discovered-function: is it in the manifest?
    $discoveryCases = foreach ($name in $discoveredNames) {
        @{
            FunctionName = $name
            InManifest   = ($exportedNames -contains $name)
            SourcePath   = ($fileCases | Where-Object { $_.FunctionNames -contains $name } | Select-Object -First 1).SourcePath
            SourceFunction = $name
        }
    }

    # Per-manifest-export: does a matching .ps1 file exist?
    $manifestCases = foreach ($name in $exportedNames) {
        $matchingFile = $publicFiles | Where-Object { $_.BaseName -eq $name }
        @{
            FunctionName = $name
            HasFile      = ($null -ne $matchingFile)
            SourcePath   = $manifestPath
            SourceFunction = $name
        }
    }

    # Test-file coverage: look for <FunctionName>.Tests.ps1 in the tests directory.
    $testsRoot         = if ($TestsPath) { $TestsPath } else { Join-Path $ModuleRoot 'Tests' }
    $testCoverageCases = foreach ($name in $discoveredNames) {
        $skip = $SkipTestCoverageCheck -or $ExcludeTestCoverageCheck -contains $name
        $testFile = if (-not $skip -and (Test-Path $testsRoot)) {
            Get-ChildItem -Path $testsRoot -Filter "$name.Tests.ps1" -Recurse -File -ErrorAction SilentlyContinue
        } else { $null }
        @{
            FunctionName = $name
            HasTestFile  = $skip -or ($null -ne $testFile -and @($testFile).Count -gt 0)
            SkipCheck    = $skip
            TestsRoot    = $testsRoot
            SourcePath   = ($fileCases | Where-Object { $_.FunctionNames -contains $name } | Select-Object -First 1).SourcePath
            SourceFunction = $name
        }
    }

    $script:fileCases         = @($fileCases)
    $script:discoveryCases    = @($discoveryCases)
    $script:manifestCases     = @($manifestCases)
    $script:testCoverageCases = @($testCoverageCases)
    $script:moduleName        = $moduleName
}

Describe 'Module Structure - <moduleName>' -Tag 'Unit', 'Structure' {
    Context 'File layout - <FileName>' -ForEach $script:fileCases {
        It 'should contain exactly one function definition' {
            $FunctionCount | Should -Be 1 -Because "'$FileName' must define exactly one function. Recommendation: Put each function in its own .ps1 file."
        }

        It 'file name should match the function name' {
            $FunctionNames[0] | Should -Be $ExpectedName `
                -Because "the function in '$FileName' must be named '$ExpectedName'. Recommendation: Rename the file to match the function name, or rename the function and update its callers."
        }
    }

    Context 'Manifest coverage - <FunctionName> (discovered in files)' -ForEach $script:discoveryCases {
        It '<FunctionName> should be listed in FunctionsToExport' {
            $InManifest | Should -BeTrue `
                -Because "'$FunctionName' is a public function and must appear in FunctionsToExport. Recommendation: Add '$FunctionName' to FunctionsToExport and ensure the root module exports it."
        }
    }

    Context 'Manifest coverage - <FunctionName> (listed in manifest)' -ForEach $script:manifestCases {
        It '<FunctionName> should have a matching public .ps1 file' {
            $HasFile | Should -BeTrue `
                -Because "'$FunctionName' is in FunctionsToExport but no matching .ps1 file was found. Recommendation: Create '$FunctionName.ps1' in a configured public function directory, or remove the stale export."
        }
    }

    Context 'Test coverage - <FunctionName>' -ForEach $script:testCoverageCases {
        It '<FunctionName> should have a corresponding *.Tests.ps1 file' -Skip:$SkipCheck {
            $HasTestFile | Should -BeTrue `
                -Because "every public function should have a test file. Expected '$FunctionName.Tests.ps1' under '$TestsRoot'. Recommendation: Create a $FunctionName.Tests.ps1 file under the configured tests directory. To opt out: add '$FunctionName' to ExcludeTestCoverageCheck."
        }
    }
}
