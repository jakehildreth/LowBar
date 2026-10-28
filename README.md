# LowBar

The bar is on the floor. Trip over it at your own risk.

LowBar is a community-standard hygiene suite for PowerShell modules. It checks structure, conventions, formatting, comment-based help, manifest integrity, and static analysis — everything except behavior. Behavior is your problem. Dust is LowBar's.

## Installation

Clone this repo and point `Invoke-StandardModuleTests.ps1` at any module root:

```powershell
git clone https://github.com/jakehildreth/LowBar.git
```

Requires PowerShell 5.1+, Pester 5.2.0+, and PSScriptAnalyzer 1.25.0+.
The runner enforces these minimums with `#requires` before tests run.
PSScriptAnalyzer 1.25.0 supports PowerShell 5.1 and is the tested baseline.
Check your chosen Pester version's own PowerShell requirements too.

```powershell
Install-Module Pester -MinimumVersion 5.2.0 -Scope CurrentUser
Install-Module PSScriptAnalyzer -MinimumVersion 1.25.0 -Scope CurrentUser
```

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

## Reports

XML is always on. Human-readable reports are opt-in:

```powershell
.\Invoke-StandardModuleTests.ps1 -ModuleRoot 'C:\Code\MyModule' -ReportFormat All
.\Invoke-StandardModuleTests.ps1 -ModuleRoot 'C:\Code\MyModule' -ReportFormat Html,Markdown
```

Choose any combination of `Html`, `Markdown`, and `Terminal`. Use `All` or
`None` alone. `None` disables the new reports, not XML. Detailed Pester output
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

Reports group failures by affected file. They show check names, literal failure
messages, recommendations, and available locations. Every failed check includes
a `Recommendation:` in XML, HTML, Markdown, and terminal reports. Known check
failures suggest a specific correction. Unexpected test or setup errors direct
you to resolve the reported error and rerun LowBar. XML includes this guidance
even when human-readable reports are disabled. Original errors and stack traces
remain intact, and `-Passthru` still returns the native Pester result.
Source locations and check/assertion locations stay separate. Module-wide and
unattributed failures have their own groups. Passed, skipped, and not-run checks
appear after failures.

HTML shows the run result and outcome counts first. Select a file to see its
failed checks, with the most failures first. File names stay short; directories
and full paths distinguish files with the same name. Recommendations stay
visible. Expand **Failure details** for original messages, full check names,
locations, and opt-out notes. **Other outcomes** contains the remaining checks.
The layout adapts to narrow screens and supports keyboard navigation. Printing
includes all files and diagnostics. With JavaScript disabled, all file groups
remain visible. Reports work offline, with no external assets, reporting module,
or network dependency.

Empty and incomplete runs do not appear to pass. When Pester returns partial
results, counts cover those results only. If Pester throws before returning
results, selected human-readable reports show `Incomplete` and unavailable
counts. LowBar cannot produce native XML without a Pester result.

If one output fails, LowBar attempts the others, keeps successful files, and
ends with an error. File paths and terminal presentation stay off the success
stream. `-Passthru` returns only the native Pester result, and only when run and
report generation do not terminate with an error. A forcibly killed process
cannot guarantee final reports.

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

## Testing LowBar's reports

Run the focused tests in a fresh PowerShell process with the Pester version
you want to check:

```powershell
Import-Module Pester -RequiredVersion 5.2.0
Invoke-Pester -Path .\Tests\Reporting.Tests.ps1 -Output Normal
```

Use the same command with Pester `6.1.0`. Check both versions on Windows
PowerShell 5.1 and PowerShell 7. These tests run fixture modules in child
processes and check generated files, native results, selection rules, and error
handling. They verify recommendations from all seven suites in every report
format. They do not replace browser checks of the HTML report.

## License

MIT License w/Commons Clause - see [LICENSE](LICENSE) file for details.

---

Made with 💜 by [Jake Hildreth](https://jakehildreth.com)
