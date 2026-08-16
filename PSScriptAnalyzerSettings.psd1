# PSScriptAnalyzer settings for the standard module test suite.
#
# DROP THIS FILE into the module root (alongside the .psd1 manifest) so that
# Module.ScriptAnalyzer.Tests.ps1 picks it up automatically.
# Alternatively pass its path via the -SettingsPath parameter.
#
# Rules already covered by companion test files:
#   Aliases / positional params  ->  PSAvoidUsingCmdletAliases,
#                                    PSAvoidUsingPositionalParameters  (enabled below)
#   CmdletBinding / OutputType   ->  Module.FunctionConventions.Tests.ps1
#   Write-Error / throw          ->  Module.AdvancedFunction.Tests.ps1
#   bool vs switch               ->  Module.FunctionConventions.Tests.ps1
#   SupportsShouldProcess        ->  Module.FunctionConventions.Tests.ps1
#                                    (also PSUseShouldProcessForStateChangingFunctions, enabled below)
#
# To suppress a rule, add its name to ExcludeRules.
# To raise the bar, change Severity to @('Error') to ignore warnings.

@{
    Severity = @('Warning', 'Error')

    ExcludeRules = @(
        # Add rule names here to suppress them globally.
        # Example: 'PSAvoidUsingWriteHost'
    )

    Rules = @{
        # Portability / correctness
        PSAvoidUsingCmdletAliases                      = @{ Enable = $true }
        PSAvoidUsingPositionalParameters               = @{ Enable = $true }
        PSAvoidUsingWriteHost                          = @{ Enable = $true }
        PSAvoidUsingInvokeExpression                   = @{ Enable = $true }
        PSAvoidDefaultValueSwitchParameter             = @{ Enable = $true }
        PSAvoidGlobalVars                              = @{ Enable = $true }
        PSUseShouldProcessForStateChangingFunctions    = @{ Enable = $true }
        PSUseOutputTypeCorrectly                       = @{ Enable = $true }
        PSUseDeclaredVarsMoreThanAssignments           = @{ Enable = $true }

        # Security
        PSAvoidUsingPlainTextForPassword               = @{ Enable = $true }
        PSAvoidUsingConvertToSecureStringWithPlainText = @{ Enable = $true }
    }
}
