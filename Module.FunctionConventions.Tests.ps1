#requires -Version 5.1
# Reusable function convention tests for any PowerShell module.
# AST-based checks applied to every public function.
#
# Checks per public function:
#   [+] Function name uses an approved PowerShell verb
#   [+] Function name follows PascalCase Verb-Noun format
#   [+] Function declares [CmdletBinding()]
#   [+] Function declares [OutputType()] (opt-out: $ExcludeOutputTypeCheck)
#   [+] No parameters typed as [bool] -- use [switch] instead
#   [+] All parameters have an explicit type declaration
#   [+] Destructive-verb functions declare SupportsShouldProcess = $true
#   [+] Functions accepting pipeline input declare a process {} block
#
# Opt-out for [OutputType()] check
# --------------------------------
# Add function names to skip in $ExcludeOutputTypeCheck:
#   -Data @{
#       ModuleRoot             = 'C:\path\to\MyModule'
#       ExcludeOutputTypeCheck = @('Get-Foo', 'Set-Bar')
#   }
#
# Usage via New-PesterContainer:
#   $container = New-PesterContainer -Path './Module.FunctionConventions.Tests.ps1' `
#       -Data @{ ModuleRoot = 'C:\path\to\MyModule' }
#   Invoke-Pester -Container $container

param(
    # Absolute path to the module root directory (where the .psd1 lives).
    [Parameter(Mandatory)]
    [string]$ModuleRoot,

    # Subdirectory/ies under ModuleRoot containing public function scripts.
    [Parameter()]
    [string[]]$PublicFunctionPaths = @('Public'),

    # Disable the [OutputType()] check for all functions in this module.
    [Parameter()]
    [bool]$SkipOutputTypeCheck = $false,

    # Function names to skip the [OutputType()] check.
    # Example: @('Get-Foo', 'Set-Bar')
    [Parameter()]
    [string[]]$ExcludeOutputTypeCheck = @()
)

BeforeDiscovery {
    $destructiveVerbs = @('Remove', 'Set', 'Update', 'Clear', 'Restart', 'Stop')
    $approvedVerbs    = (Get-Verb).Verb

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
            $parts    = $funcName -split '-', 2
            $verb     = if ($parts.Count -ge 1) { $parts[0] } else { '' }

            $paramBlockAttrs = if ($funcDef.Body.ParamBlock) {
                @($funcDef.Body.ParamBlock.Attributes)
            } else { @() }

            $cmdletBindingAttr = $paramBlockAttrs |
                Where-Object { $_.TypeName.Name -eq 'CmdletBinding' } |
                Select-Object -First 1

            $hasShouldProcess = if ($cmdletBindingAttr) {
                $cmdletBindingAttr.Extent.Text -match 'SupportsShouldProcess\s*=\s*\$true'
            } else { $false }

            $params = if ($funcDef.Body.ParamBlock) {
                @($funcDef.Body.ParamBlock.Parameters)
            } else { @() }

            $boolParams = @(
                $params | Where-Object {
                    $_.Attributes | Where-Object {
                        $_ -is [System.Management.Automation.Language.TypeConstraintAst] -and
                        $_.TypeName.Name -in 'bool', 'System.Boolean'
                    }
                } | ForEach-Object { $_.Name.VariablePath.UserPath }
            )

            $untypedParams = @(
                $params | Where-Object {
                    -not ($_.Attributes | Where-Object {
                        $_ -is [System.Management.Automation.Language.TypeConstraintAst]
                    })
                } | ForEach-Object { $_.Name.VariablePath.UserPath }
            )

            $hasPipelineParam = [bool](
                $params | Where-Object {
                    $_.Attributes | Where-Object {
                        $_ -is [System.Management.Automation.Language.AttributeAst] -and
                        $_.TypeName.Name -eq 'Parameter' -and
                        $_.Extent.Text -match 'ValueFromPipeline'
                    }
                }
            )

            @{
                FunctionName        = $funcName
                FileName            = $file.Name
                ModuleName          = $script:moduleName
                Verb                = $verb
                IsApprovedVerb      = ($approvedVerbs -contains $verb)
                IsPascalCase        = ($funcName -match '^[A-Z][a-zA-Z]+-[A-Z][a-zA-Z0-9]+$')
                HasCmdletBinding    = ($null -ne $cmdletBindingAttr)
                HasOutputType       = [bool]($paramBlockAttrs |
                    Where-Object { $_.TypeName.Name -eq 'OutputType' })
                SkipOutputTypeCheck = ($SkipOutputTypeCheck -or $ExcludeOutputTypeCheck -contains $funcName)
                BoolParams          = $boolParams
                UntypedParams       = $untypedParams
                IsDestructive       = ($destructiveVerbs -contains $verb)
                HasShouldProcess    = $hasShouldProcess
                HasPipelineParam    = $hasPipelineParam
                HasProcessBlock     = ($null -ne $funcDef.Body.ProcessBlock)
            }
        }
    }

    $script:functionCases = @($functionCases)
}

Describe 'Function Conventions - <ModuleName>' -Tag 'Unit', 'FunctionConventions' {
    Context '<FunctionName> in <FileName>' -ForEach $script:functionCases {
        It 'should use an approved PowerShell verb' {
            $IsApprovedVerb | Should -BeTrue `
                -Because "'$Verb' is not an approved PowerShell verb. Run Get-Verb to see all approved verbs."
        }

        It 'function name should follow PascalCase Verb-Noun format' {
            $IsPascalCase | Should -BeTrue `
                -Because "'$FunctionName' must be Verb-Noun with both parts starting with an uppercase letter (e.g. Get-UserProfile, not get-UserProfile or Get-userProfile)"
        }

        It 'should declare [CmdletBinding()]' {
            $HasCmdletBinding | Should -BeTrue `
                -Because "'$FunctionName' must be an advanced function. Add [CmdletBinding()] before the param() block."
        }

        It 'should declare [OutputType()]' -Skip:$SkipOutputTypeCheck {
            $HasOutputType | Should -BeTrue `
                -Because "'$FunctionName' must document its return type. Add [OutputType([TypeName])] before param(). To opt out: add '$FunctionName' to the ExcludeOutputTypeCheck parameter."
        }

        It 'should not use [bool] parameters -- use [switch] instead' {
            $BoolParams | Should -BeNullOrEmpty `
                -Because "parameter(s) '$($BoolParams -join "', '")' in '$FunctionName' should use [switch] not [bool]"
        }

        It 'all parameters should have explicit type declarations' {
            $UntypedParams | Should -BeNullOrEmpty `
                -Because "parameter(s) '$($UntypedParams -join "', '")' in '$FunctionName' have no type constraint. Add [TypeName] before each parameter variable."
        }

        It 'should declare [CmdletBinding(SupportsShouldProcess = $true)] for destructive verb' -Skip:(-not $IsDestructive) {
            $HasShouldProcess | Should -BeTrue `
                -Because "'$FunctionName' uses the destructive verb '$Verb'. Add SupportsShouldProcess = `$true to the [CmdletBinding()] attribute."
        }

        It 'should have a process {} block when accepting pipeline input' -Skip:(-not $HasPipelineParam) {
            $HasProcessBlock | Should -BeTrue `
                -Because "'$FunctionName' accepts pipeline input but has no process {} block. Without it, only the last piped object is processed."
        }
    }
}

