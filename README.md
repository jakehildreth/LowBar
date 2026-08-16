# LowBar

The bar is on the floor. Trip over it at your own risk.

LowBar is a community-standard hygiene suite for PowerShell modules. It checks structure, conventions, formatting, comment-based help, manifest integrity, and static analysis — everything except behavior. Behavior is your problem. Dust is LowBar's.

## Installation

Clone this repo and point `Invoke-StandardModuleTests.ps1` at any module root:

```powershell
git clone https://github.com/jakehildreth/LowBar.git
```

Requires Pester 5.2+ and PSScriptAnalyzer.

## Quick start

Run the full suite against your module:

```powershell
.\Invoke-StandardModuleTests.ps1 -ModuleRoot 'C:\Code\MyModule'
```

Generate a config file to tune which checks apply:

```powershell
.\New-StandardModuleTestConfig.ps1 -ModuleRoot 'C:\Code\MyModule'
```

Presets: `Default` (all checks), `Lenient` (drops the contentious ones), `Strict` (reserved for future stricter rules).

## What it checks

| Suite | Scope |
|---|---|
| Manifest | Valid .psd1, required fields, edition compatibility, clean import, no wildcard exports |
| ScriptAnalyzer | Warning+Error on all source, with a non-negotiable security floor |
| CBH | .SYNOPSIS, .DESCRIPTION, .EXAMPLE, .OUTPUTS, .PARAMETER on every function |
| Structure | One function per file, filename matches function, manifest alignment, test-file existence |
| FunctionConventions | Approved verbs, PascalCase, CmdletBinding, OutputType, [switch] not [bool], typed params, ShouldProcess for destructive verbs, process block for pipeline |
| Formatting | UTF-8, no tabs, no trailing whitespace, EOF newline, no backticks, OTBS braces |
| AdvancedFunction | $PSCmdlet error methods, no preference-variable assignment |

Every contentious check supports opt-outs via StandardModuleTestConfig.psd1 or explicit parameters.

## What it doesn't check

Behavior. LowBar verifies that each public function has a test file with at least one It block. Whether those tests are meaningful is between you and your code reviewer.

## License

MIT License w/Commons Clause - see [LICENSE](LICENSE) file for details.

---

Made with 💜 by [Jake Hildreth](https://jakehildreth.com)
