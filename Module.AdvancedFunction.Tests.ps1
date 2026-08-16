#requires -Version 5.1
# Reusable advanced function quality tests for any PowerShell module.
# Checks applied only to advanced functions (those declaring [CmdletBinding()]).
#
# Checks per advanced function:
#   [!] Prefers $PSCmdlet.WriteError() and $PSCmdlet.ThrowTerminatingError()
#       over Write-Error and throw. This is an informational check -- catch/re-throw
#       scenarios are legitimate false positives; use the opt-out when needed.
#   [+] Does not assign to PowerShell preference variables inside function scope
#       (e.g. $ErrorActionPreference = 'Stop'), which surprises callers.
#
# Opt-out for error handling check
# ---------------------------------
# To skip the Write-Error / throw check for all functions:
#   -Data @{ ModuleRoot = '...'; SkipErrorHandlingCheck = $true }
#
# To exclude specific functions (e.g. known catch/re-throw wrappers):
#   -Data @{ ModuleRoot = '...'; ExcludeErrorHandlingCheck = @('Invoke-Foo') }
#
# Opt-out for preference variable check
# --------------------------------------
# To skip the preference variable assignment check for all functions:
#   -Data @{ ModuleRoot = '...'; SkipPreferenceVarCheck = $true }
#
# To exclude specific functions:
#   -Data @{ ModuleRoot = '...'; ExcludePreferenceVarCheck = @('Invoke-Foo') }
#
# Usage via New-PesterContainer:
#   $container = New-PesterContainer -Path './Module.AdvancedFunction.Tests.ps1' `
#       -Data @{ ModuleRoot = 'C:\path\to\MyModule' }
#   Invoke-Pester -Container $container

param(
    # Absolute path to the module root directory (where the .psd1 lives).
    [Parameter(Mandatory)]
    [string]$ModuleRoot,

    # Subdirectory/ies under ModuleRoot containing public function scripts.
    [Parameter()]
    [string[]]$PublicFunctionPaths = @('Public'),

    # Disable the Write-Error / throw check for all functions.
    [Parameter()]
    [bool]$SkipErrorHandlingCheck = $false,

    # Function names to exclude from the Write-Error / throw check.
    [Parameter()]
    [string[]]$ExcludeErrorHandlingCheck = @(),

    # Disable the preference variable assignment check for all functions.
    [Parameter()]
    [bool]$SkipPreferenceVarCheck = $false,

    # Function names to exclude from the preference variable assignment check.
    [Parameter()]
    [string[]]$ExcludePreferenceVarCheck = @()
)

BeforeDiscovery {
    $preferenceVars = @(
        'ErrorActionPreference', 'VerbosePreference', 'DebugPreference',
        'WarningPreference', 'InformationPreference', 'ConfirmPreference',
        'WhatIfPreference', 'ProgressPreference'
    )

    $manifestFile = Get-ChildItem -Path $ModuleRoot -Filter '*.psd1' -File |
        Select-Object -First 1
    if (-not $manifestFile) { throw "No .psd1 manifest found in '$ModuleRoot'." }
    $script:moduleName = $manifestFile.BaseName

    $publicPaths = $PublicFunctionPaths |
        ForEach-Object { Join-Path $ModuleRoot $_ } |
        Where-Object { Test-Path $_ }

    $publicFiles = if ($publicPaths) {
        @(Get-ChildItem -Path $publicPaths -Filter '*.ps1' -Recurse -File)
    } else { @() }

    $functionCases = foreach ($file in $publicFiles) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName, [ref]$null, [ref]$null
        )

        $funcDefs = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $false))

        foreach ($funcDef in $funcDefs) {
            $funcName = $funcDef.Name

            $hasCmdletBinding = if ($funcDef.Body.ParamBlock) {
                [bool]($funcDef.Body.ParamBlock.Attributes |
                    Where-Object { $_.TypeName.Name -eq 'CmdletBinding' })
            } else { $false }

            # Only run these checks on advanced functions.
            if (-not $hasCmdletBinding) { continue }

            $writeErrorCalls = @(
                $funcDef.Body.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Write-Error'
                }, $true) | ForEach-Object {
                    "Write-Error at line $($_.Extent.StartLineNumber)"
                }
            )

            $throwStatements = @(
                $funcDef.Body.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.ThrowStatementAst]
                }, $true) | ForEach-Object {
                    "throw at line $($_.Extent.StartLineNumber)"
                }
            )

            $errorHandlingIssues = @($writeErrorCalls) + @($throwStatements)

            $prefVarAssignments = @(
                $funcDef.Body.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -in $preferenceVars
                }, $true) | ForEach-Object {
                    "$($_.Left.VariablePath.UserPath) at line $($_.Extent.StartLineNumber)"
                }
            )

            @{
                FunctionName        = $funcName
                FileName            = $file.Name
                ModuleName          = $script:moduleName
                ErrorHandlingIssues = $errorHandlingIssues
                SkipErrorHandling   = ($SkipErrorHandlingCheck -or
                                       $ExcludeErrorHandlingCheck -contains $funcName)
                PrefVarAssignments  = $prefVarAssignments
                SkipPrefVarCheck    = ($SkipPreferenceVarCheck -or
                                       $ExcludePreferenceVarCheck -contains $funcName)
            }
        }
    }

    $script:functionCases = @($functionCases)
}

Describe 'Advanced Function Quality - <ModuleName>' -Tag 'Unit', 'AdvancedFunction' {
    Context '<FunctionName> in <FileName>' -ForEach $script:functionCases {
        It 'should prefer $PSCmdlet error methods over Write-Error and throw' -Skip:$SkipErrorHandling {
            $ErrorHandlingIssues | Should -BeNullOrEmpty `
                -Because "'$FunctionName' is an advanced function. Use `$PSCmdlet.WriteError() instead of Write-Error and `$PSCmdlet.ThrowTerminatingError() instead of throw for correct error stream behavior. Found: $($ErrorHandlingIssues -join '; '). To opt out: add '$FunctionName' to ExcludeErrorHandlingCheck."
        }

        It 'should not assign to preference variables inside function scope' -Skip:$SkipPrefVarCheck {
            $PrefVarAssignments | Should -BeNullOrEmpty `
                -Because "'$FunctionName' modifies global preference variables, which overrides the caller's settings. Found: $($PrefVarAssignments -join '; '). To opt out: add '$FunctionName' to ExcludePreferenceVarCheck."
        }
    }
}
