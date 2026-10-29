# LowBar

The bar is on the floor. Trip over it at your own risk.

LowBar is a community-standard hygiene suite for PowerShell modules. It checks structure, conventions, formatting, comment-based help, manifest integrity, and static analysis... everything except behavior. Behavior is your problem. Lint is LowBar's.

## Installation

Requires PowerShell 5.1+, Pester 5.2.0+, and PSScriptAnalyzer 1.25.0+.
The runner enforces these minimums with `#requires` before tests run.
PSScriptAnalyzer 1.25.0 supports PowerShell 5.1 and is the tested baseline.
Check your chosen Pester version's own PowerShell requirements too.

```powershell
Install-Module Pester -MinimumVersion 5.2.0 -Scope CurrentUser
Install-Module PSScriptAnalyzer -MinimumVersion 1.25.0 -Scope CurrentUser
```

Then clone this repo:

```powershell
git clone https://github.com/jakehildreth/LowBar.git
```

## Quick start

Run the full suite against your module:

```powershell
.\Invoke-StandardModuleTests.ps1 -ModuleRoot 'C:\Code\MyModule'
```

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

## Customize the checks

Generate a config file to tune which checks apply:

```powershell
.\New-StandardModuleTestConfig.ps1 -ModuleRoot 'C:\Code\MyModule'
```

Presets: `Default` (all checks), `Lenient` (drops the contentious ones), `Strict` (reserved for future stricter rules).

## Reporting

XML is always created. Human-readable reports are opt-in:

```powershell
.\Invoke-StandardModuleTests.ps1 -ModuleRoot 'C:\Code\MyModule' -ReportFormat All
.\Invoke-StandardModuleTests.ps1 -ModuleRoot 'C:\Code\MyModule' -ReportFormat Html,Markdown
```

Choose any combination of `Html`, `Markdown`, and `Terminal`. Use `All` or
`None` alone. `None` disables only the human-readable reports, not the XML. Detailed Pester output
stays on either way. LowBar never opens a browser.

Save a default selection in your module's config:

```powershell
.\New-StandardModuleTestConfig.ps1 -ModuleRoot 'C:\Code\MyModule' -ReportFormat Html,Markdown
```

Or edit `ReportFormat = @('Html', 'Markdown')` in
[StandardModuleTestConfig.psd1](StandardModuleTestConfig.psd1).
Explicit parameters override config. `-ReportFormat None` overrides a configured
opt-in. An empty config selection enables no human-readable reports.

File reports go to the module's `Tests` directory, or `-OutputPath`. LowBar
creates the directory if needed. All files from one run share a UTC timestamp:

```text
MyModule.StandardTests.20261027T003000123Z.xml
MyModule.StandardTests.20261027T003000123Z.html
MyModule.StandardTests.20261027T003000123Z.md
```

The timestamped XML name replaces the former fixed filename. Earlier reports
stay untouched. A filename collision fails explicitly, including one caused by
a concurrent run. LowBar does not clean up old reports.

Reports use the results of the current Pester run. Rerun the suite after changing
your module or LowBar. Earlier reports do not update.

## License

MIT License w/Commons Clause - see [LICENSE](LICENSE) file for details.

---

Made with 💜 by [Jake Hildreth](https://jakehildreth.com)
