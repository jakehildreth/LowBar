#requires -Version 5.1
# Reusable Comment-Based Help (CBH) tests for any PowerShell module.
# Verifies every public function in the module has required CBH sections.
#
# Checks per function:
#   [+] .SYNOPSIS     - present and non-empty
#   [+] .DESCRIPTION  - present and non-empty
#   [+] .EXAMPLE      - at least one present
#   [+] .OUTPUTS      - present and non-empty
#   [+] .PARAMETER    - each declared parameter has a corresponding .PARAMETER entry
#
# Usage via New-PesterContainer:
#   $container = New-PesterContainer -Path './Module.CBH.Tests.ps1' `
#       -Data @{ ModuleRoot = 'C:\path\to\MyModule' }
#   Invoke-Pester -Container $container
#
# To restrict which functions are checked, pass -PublicFunctionPaths with explicit paths:
#   -Data @{ ModuleRoot = '...'; PublicFunctionPaths = @('Public') }

param(
    # Absolute path to the module root directory.
    [Parameter(Mandatory)]
    [string]$ModuleRoot,

    # Subdirectory/ies under ModuleRoot containing public function scripts.
    # Defaults to 'Public'. Can be overridden for flat module layouts.
    [Parameter()]
    [string[]]$PublicFunctionPaths = @('Public')
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
        Get-ChildItem -Path $publicPaths -Filter '*.ps1' -Recurse -File
    } else { @() }

    # Parse each file with the AST to extract function names + parameter names.
    # Build a flat list of test-case hashtables for -ForEach.
    $functionCases = foreach ($file in $publicFiles) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$null,
            [ref]$null
        )

        $functionDefs = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $false)

        foreach ($funcDef in $functionDefs) {
            $paramNames = @()
            if ($funcDef.Body.ParamBlock) {
                $paramNames = @($funcDef.Body.ParamBlock.Parameters |
                    ForEach-Object { $_.Name.VariablePath.UserPath })
            }

            @{
                FunctionName = $funcDef.Name
                ModuleName   = $moduleName
                FileName     = $file.Name
                SourcePath   = $file.FullName
                SourceLine   = $funcDef.Extent.StartLineNumber
                SourceFunction = $funcDef.Name
                ParamNames   = $paramNames
            }
        }
    }

    $script:functionCases = @($functionCases)
    $script:moduleName    = $moduleName
    $script:manifestPath  = $manifestPath
}

Describe 'Comment-Based Help - <ModuleName>' -Tag 'Unit', 'CBH' -ForEach @(@{ ModuleName = $script:moduleName; ManifestPath = $script:manifestPath }) {
    BeforeAll {
        Import-Module $ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module $ModuleName -Force -ErrorAction SilentlyContinue
    }

    Context '<FunctionName> in <FileName>' -ForEach $script:functionCases {
        BeforeAll {
            # Get-Help returns different object types depending on help presence;
            # use -ErrorAction SilentlyContinue and check properties explicitly.
            $help = Get-Help -Name $FunctionName -Full -ErrorAction SilentlyContinue
        }

        It 'should have a .SYNOPSIS' {
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$FunctionName must have .SYNOPSIS. Recommendation: Add a .SYNOPSIS section with a short summary to the function comment-based help."
        }

        It 'should have a .DESCRIPTION' {
            # Description comes back as an object with a .Text property in full help.
            $descText = if ($help.Description) {
                ($help.Description | ForEach-Object { $_.Text }) -join ''
            } else { '' }
            $descText | Should -Not -BeNullOrEmpty -Because "$FunctionName must have .DESCRIPTION. Recommendation: Add a .DESCRIPTION section with text to the function comment-based help."
        }

        It 'should have at least one .EXAMPLE' {
            $exampleCount = if ($help.Examples) { @($help.Examples.Example).Count } else { 0 }
            $exampleCount | Should -BeGreaterThan 0 `
                -Because "$FunctionName must have at least one .EXAMPLE. Recommendation: Add a .EXAMPLE section with a working command to the function comment-based help."
        }

        It 'should have .OUTPUTS' {
            $outputText = if ($help.ReturnValues) {
                ($help.ReturnValues.ReturnValue |
                    ForEach-Object { $_.Type.Name }) -join ''
            } else { '' }
            $outputText | Should -Not -BeNullOrEmpty -Because "$FunctionName must have .OUTPUTS. Recommendation: Add a .OUTPUTS section describing the return type, or None if the function returns no output."
        }

        # One test per parameter - data-driven so failures name the missing parameter.
        if ($ParamNames.Count -gt 0) {
            It '.PARAMETER <_> should be documented' -ForEach $ParamNames {
                $parameterName = $_
                $paramHelp = $help.Parameters.Parameter |
                    Where-Object { $_.Name -eq $parameterName }
                $paramHelp | Should -Not -BeNullOrEmpty `
                    -Because "$FunctionName parameter '$_' must have a .PARAMETER entry. Recommendation: Add a .PARAMETER $_ section with description text to the function comment-based help."

                # Also verify the description text isn't empty.
                $paramDesc = if ($paramHelp -and $paramHelp.PSObject.Properties['Description'] -and $paramHelp.Description) {
                    ($paramHelp.Description | ForEach-Object { $_.Text }) -join ''
                } else { '' }
                $paramDesc | Should -Not -BeNullOrEmpty `
                    -Because "$FunctionName .PARAMETER $_ must have description text. Recommendation: Describe the parameter below its .PARAMETER $_ heading."
            }
        }
    }
}
