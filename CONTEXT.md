# Context — LowBar

Domain vocabulary for LowBar, the community-standard hygiene suite for PowerShell modules.

## Terms

### Baseline suite
The set of hygiene tests every module must pass. Checks structure, conventions, formatting, comment-based help, manifest integrity, ScriptAnalyzer rules, and advanced function quality. Explicitly does NOT check behavior. Behavioral correctness is the module's own responsibility.

### Publish-readiness suite
A separate, opt-in test suite for modules heading to the PowerShell Gallery. Checks gallery metadata (CompanyName, Copyright, Tags, ProjectUri, LicenseUri) and README quality. Not part of the baseline.

### Public function
A function defined in a file under the module's public path (default: Public/). Must be listed in FunctionsToExport in the manifest. Held to the full baseline standard.

### Private function
A function defined in a file under the module's private path (default: Private/). Not exported. Held to the SAME baseline standard as public functions: CBH, one-function-per-file, naming conventions, CmdletBinding, typed parameters. Private is not a hiding place for sloppy code.

### Test file coverage
The baseline requires each public function to have a matching <FunctionName>.Tests.ps1 file containing at least one It block. Existence only — the baseline does not judge whether the tests are meaningful. Test quality is the module owner's responsibility.

### Security floor
The set of PSScriptAnalyzer rules that a module's local PSScriptAnalyzerSettings.psd1 CANNOT disable. Includes PSAvoidUsingPlainTextForPassword, PSAvoidUsingConvertToSecureStringWithPlainText, and PSAvoidUsingInvokeExpression. Local settings may add rules or relax style rules, but may not weaken the security floor.

### Root module cleanliness
The rule that a module's root .psm1 should contain only dot-sourcing of Classes/, Private/, Public/ (in that order) and Export-ModuleMember. Any other logic in the root module is a smell.

### Opt-out
Every contentious check supports per-function or per-file exemptions via config (StandardModuleTestConfig.psd1) or explicit parameters to Invoke-StandardModuleTests.ps1. Explicit parameters always override the config file.
