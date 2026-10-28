#requires -Version 5.1
BeforeAll {
    $repositoryRoot = Split-Path $PSScriptRoot -Parent
    $engine = (Get-Process -Id $PID).Path
    $pesterVersion = (Get-Module Pester).Version.ToString()

    function Invoke-RunnerCase {
        <#
        .SYNOPSIS
            Runs a fixture through the public runner in an isolated process.
        .DESCRIPTION
            Captures native results, errors, presentation, and generated files.
        .PARAMETER Parameters
            Arguments for the standard runner.
        .PARAMETER Setup
            Child-process setup for third-party boundary failures or fixtures.
        .EXAMPLE
            Invoke-RunnerCase -Parameters @{ ReportFormat = @('All') }
        .OUTPUTS
            System.Management.Automation.PSCustomObject
        #>
        param(
            [hashtable]$Parameters = @{},
            [string]$Setup = ''
        )

        $Parameters.ModuleRoot = $moduleRoot
        if (-not $Parameters.ContainsKey('Tag')) { $Parameters.Tag = @('Formatting') }
        $parameterPath = Join-Path $caseRoot 'parameters.clixml'
        $resultPath = Join-Path $caseRoot 'result.clixml'
        $Parameters | Export-Clixml -LiteralPath $parameterPath
        $command = @"
`$ErrorActionPreference = 'Stop'
`$env:PSModulePath = '$env:PSModulePath'
Import-Module Pester -RequiredVersion '$pesterVersion'
$Setup
try {
    `$parameters = Import-Clixml -LiteralPath '$parameterPath'
    `$objects = @(& '$repositoryRoot\Invoke-StandardModuleTests.ps1' @parameters)
    @{ Objects = `$objects; Error = `$null } | Export-Clixml -LiteralPath '$resultPath'
} catch {
    @{ Objects = @(); Error = `$_.ToString() } | Export-Clixml -LiteralPath '$resultPath'
}
"@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $console = & $engine -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $encodedCommand 2>&1 | Out-String
        $snapshot = Import-Clixml -LiteralPath $resultPath
        [pscustomobject]@{
            Objects = @($snapshot.Objects)
            Error = $snapshot.Error
            Console = $console
            Files = @(Get-ChildItem -LiteralPath $outputPath -File -ErrorAction SilentlyContinue)
        }
    }
}

Describe 'Maintainer reports through the standard runner' {
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $moduleRoot = Join-Path $caseRoot 'Sample'
        $outputPath = Join-Path $moduleRoot 'Tests'
        $null = New-Item -ItemType Directory -Path (Join-Path $moduleRoot 'Public') -Force
        $null = New-Item -ItemType Directory -Path $outputPath -Force
        Set-Content -LiteralPath (Join-Path $moduleRoot 'Public\Get-Sample.ps1') -Value @'
function Get-Sample {
    <#
    .SYNOPSIS
        Gets a sample.
    .DESCRIPTION
        Returns the supplied count.
    .PARAMETER Count
        Count to return.
    .EXAMPLE
        Get-Sample -Count 1
    .OUTPUTS
        System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([int]$Count)
    $Count
}
'@
        Set-Content -LiteralPath (Join-Path $moduleRoot 'Sample.psm1') -Value @'
. (Join-Path $PSScriptRoot 'Public\Get-Sample.ps1')
Export-ModuleMember -Function Get-Sample
'@
        New-ModuleManifest -Path (Join-Path $moduleRoot 'Sample.psd1') -RootModule 'Sample.psm1' -ModuleVersion '1.0' -Author 'Fixture' -Description 'Reporting fixture' -PowerShellVersion '5.1' -CompatiblePSEditions Desktop,Core -FunctionsToExport Get-Sample
    }

    It 'declares the supported PowerShell and module minimum versions' {
        $runner = Join-Path $repositoryRoot 'Invoke-StandardModuleTests.ps1'
        $syntax = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$null, [ref]$null)
        $syntax.ScriptRequirements.RequiredPSVersion | Should -Be ([version]'5.1')
        $modules = @($syntax.ScriptRequirements.RequiredModules)
        ($modules | Where-Object Name -eq 'Pester').Version | Should -Be ([version]'5.2.0')
        ($modules | Where-Object Name -eq 'PSScriptAnalyzer').Version | Should -Be ([version]'1.25.0')
    }

    It 'always writes timestamped native XML and returns only the Pester result with Passthru' {
        $run = Invoke-RunnerCase -Parameters @{ Passthru = $true }
        $run.Error | Should -BeNullOrEmpty
        $run.Objects.Count | Should -Be 1
        $run.Objects[0].Version.ToString() | Should -Be $pesterVersion
        $run.Objects[0].TotalCount | Should -BeGreaterThan 0
        $run.Files.Count | Should -Be 1
        $run.Files[0].Name | Should -Match '^Sample\.StandardTests\.\d{8}T\d{9}Z\.xml$'
        ([xml](Get-Content -LiteralPath $run.Files[0].FullName -Raw)).DocumentElement.LocalName | Should -Be 'test-results'
    }

    It 'writes all selected reports from one run, grouped by source file, without success-stream text' {
        Add-Content -LiteralPath (Join-Path $moduleRoot 'Public\Get-Sample.ps1') -Value "`t# failing formatting   "
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('All') }
        $run.Error | Should -BeNullOrEmpty
        $run.Objects.Count | Should -Be 0
        $reports = @($run.Files | Where-Object { $_.Extension -in '.xml', '.html', '.md' })
        $reports.Count | Should -Be 3
        @($reports.BaseName | Select-Object -Unique).Count | Should -Be 1
        $html = Get-Content -LiteralPath ($reports | Where-Object Extension -eq '.html').FullName -Raw
        $markdown = Get-Content -LiteralPath ($reports | Where-Object Extension -eq '.md').FullName -Raw
        $html | Should -Match 'Failed: 2'
        $html | Should -Match 'Passed: 10'
        $html | Should -Match 'Not run: \d+'
        $html | Should -Match 'Affected source'
        $html | Should -Match 'Check location'
        $html | Should -Match 'Get-Sample\.ps1'
        $markdown | Should -Match ([regex]::Escape((Join-Path $moduleRoot 'Public\Get-Sample.ps1')))
        $markdown | Should -Match 'Formatting'
        $run.Console | Should -Match 'Failed: 2'
        $run.Console | Should -Match 'Html report:'
    }

    It 'makes HTML recommendations visible before expandable diagnostics and labels files clearly' {
        Add-Content -LiteralPath (Join-Path $moduleRoot 'Public\Get-Sample.ps1') -Value "`t# failing formatting   "
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('Html') }
        $run.Error | Should -BeNullOrEmpty
        $html = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.html').FullName -Raw
        $html | Should -Match '<title>Sample - LowBar hygiene report</title>'
        $html | Should -Match 'aria-label=.Run summary.'
        $html | Should -Match '<a class=.skip-link. href=.#failures.'
        $html | Should -Match '<span class=.file-name.>Get-Sample\.ps1</span>'
        $html | Should -Match '<span class=.file-directory.>'
        $recommendations = @([regex]::Matches($html, '<p class=.recommendation-text.>(.*?)</p>'))
        $recommendations.Count | Should -Be 2
        foreach ($recommendation in $recommendations) {
            $recommendation.Groups[1].Value | Should -Match '^Recommendation: '
            $recommendation.Groups[1].Value | Should -Not -Match 'Expected|but got|To opt out'
        }
        [regex]::Matches($html, '<details class=.diagnostic.>').Count | Should -Be 2
        $html | Should -Match 'Original failure'
        $html | Should -Match 'Expected'
        $html | Should -Match 'Check location'
        $html | Should -Not -Match '<(?:script|link)[^>]+(?:src|href)='
    }

    It 'keeps identical HTML file names distinct and escapes prominent recommendations' {
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('Html') } -Setup @'
function Invoke-Pester {
    param($Configuration)
    $Configuration.Run.Container = @(New-PesterContainer -ScriptBlock {
        Describe 'Help checks' -Tag Formatting -ForEach @(
            @{ SourcePath = 'C:\Sample\Public\Get-Item.ps1' }
            @{ SourcePath = 'C:\Sample\Private\Get-Item.ps1' }
        ) {
            It 'needs help' { throw 'Recommendation: Add <help> & examples.' }
        }
    })
    Pester\Invoke-Pester -Configuration $Configuration
}
'@
        $run.Error | Should -BeNullOrEmpty
        $html = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.html').FullName -Raw
        [regex]::Matches($html, '<span class=.file-name.>Get-Item\.ps1</span>').Count | Should -Be 2
        $html | Should -Match '<span class=.file-directory.>C:\\Sample\\Public</span>'
        $html | Should -Match '<span class=.file-directory.>C:\\Sample\\Private</span>'
        [regex]::Matches($html, '<h3>needs help</h3>').Count | Should -Be 2
        [regex]::Matches($html, '<p>1 failed check</p>').Count | Should -Be 2
        $html | Should -Match '<p class=.recommendation-text.>Recommendation: Add &lt;help&gt; &amp; examples\.</p>'
        $html | Should -Not -Match '<help>|<section[^>]*class=.file-group.[^>]*\shidden'
    }

    It 'includes actionable formatting recommendations in every report and native failure result' {
        Add-Content -LiteralPath (Join-Path $moduleRoot 'Public\Get-Sample.ps1') -Value "`t# failing formatting   "
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('All'); Passthru = $true }
        $run.Error | Should -BeNullOrEmpty
        $result = $run.Objects[0]
        $result.FailedCount | Should -Be 2
        $xml = [xml](Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.xml').FullName -Raw)
        $failures = @($xml.SelectNodes('//test-case/failure/message'))
        $failures.Count | Should -Be 2
        $html = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.html').FullName -Raw
        $markdown = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.md').FullName -Raw
        foreach ($recommendation in @(
            'Recommendation: Remove spaces and tabs from the end of each affected line.'
            'Recommendation: Replace tab characters with spaces for indentation.'
        )) {
            $pattern = [regex]::Escape($recommendation)
            ($failures.InnerText -join "`n") | Should -Match $pattern
            $html | Should -Match $pattern
            $markdown | Should -Match $pattern
            $run.Console | Should -Match $pattern
            (($result.Tests | ForEach-Object { $_.ErrorRecord }) -join "`n") | Should -Match $pattern
        }
        ($markdown -split 'Other outcomes', 2)[1] | Should -Not -Match 'Recommendation:'
    }

    It 'includes <Suite> recommendations in every report' -ForEach @(
        @{ Suite = 'Manifest'; Recommendation = "Set Author to a non-empty author name in the module manifest." }
        @{ Suite = 'CBH'; Recommendation = 'Add a .DESCRIPTION section with text to the function comment-based help.' }
        @{ Suite = 'Structure'; Recommendation = 'Create a Get-Sample.Tests.ps1 file under the configured tests directory.' }
        @{ Suite = 'FunctionConventions'; Recommendation = 'Add [OutputType([TypeName])] before param() to describe the function output.' }
        @{ Suite = 'ScriptAnalyzer'; Recommendation = 'Correct each reported ScriptAnalyzer rule violation at the listed source line.' }
        @{ Suite = 'AdvancedFunction'; Recommendation = 'Replace Write-Error with $PSCmdlet.WriteError() and throw with $PSCmdlet.ThrowTerminatingError().' }
    ) {
        Set-Content -LiteralPath (Join-Path $moduleRoot 'Public\Get-Sample.ps1') -Value @'
function Get-Sample {
    [CmdletBinding()]
    param($Count)
    $ErrorActionPreference = 'Stop'
    Write-Error 'Sample failure'
    Write-Host 'Sample output'
    $Count
}
'@
        $manifestPath = Join-Path $moduleRoot 'Sample.psd1'
        $manifestText = Get-Content -LiteralPath $manifestPath -Raw
        Set-Content -LiteralPath $manifestPath -Value ($manifestText -replace "(?m)^Author\s*=.*$", "Author = ''")
        $run = Invoke-RunnerCase -Parameters @{ Tag = @($Suite); ReportFormat = @('All'); Passthru = $true }
        $run.Error | Should -BeNullOrEmpty
        $run.Objects[0].FailedBlocks.Count | Should -Be 0 -Because $run.Console
        $run.Objects[0].FailedCount | Should -BeGreaterThan 0
        $xml = [xml](Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.xml').FullName -Raw)
        $failures = @($xml.SelectNodes('//test-case/failure/message'))
        $failures.Count | Should -Be $run.Objects[0].FailedCount
        foreach ($failure in $failures) { $failure.InnerText | Should -Match 'Recommendation: ' }
        $pattern = [regex]::Escape("Recommendation: $Recommendation")
        ($failures.InnerText -join "`n") | Should -Match $pattern
        $html = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.html').FullName -Raw
        $markdown = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.md').FullName -Raw
        [Net.WebUtility]::HtmlDecode($html) | Should -Match $pattern
        $markdown | Should -Match $pattern
        $run.Console | Should -Match $pattern
        foreach ($recommendationText in [regex]::Matches($html, '<p class=.recommendation-text.>(.*?)</p>')) {
            $recommendationText.Groups[1].Value | Should -Not -Match ', but got|To opt out:'
        }
    }

    It 'does not recommend changes for complete comment-based help' {
        $run = Invoke-RunnerCase -Parameters @{ Tag = @('CBH'); ReportFormat = @('All'); Passthru = $true }
        $run.Error | Should -BeNullOrEmpty
        $run.Objects[0].FailedBlocks.Count | Should -Be 0
        $run.Objects[0].FailedCount | Should -Be 0
        $run.Objects[0].PassedCount | Should -Be 5
        $markdown = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.md').FullName -Raw
        $markdown | Should -Not -Match 'Recommendation:'
    }

    It 'preserves documented help after manifest import tests unload the module' {
        $run = Invoke-RunnerCase -Parameters @{ Tag = @('Manifest', 'CBH'); ReportFormat = @('All'); Passthru = $true }
        $run.Error | Should -BeNullOrEmpty
        $run.Objects[0].FailedBlocks.Count | Should -Be 0 -Because $run.Console
        $helpChecks = @($run.Objects[0].Tests | Where-Object { ($_.ExpandedPath -join '.') -like 'Comment-Based Help*' })
        $helpChecks.Count | Should -Be 5
        @($helpChecks | Where-Object Result -ne Passed).Count | Should -Be 0
        $run.Objects[0].FailedCount | Should -Be 0
        $xml = [xml](Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.xml').FullName -Raw)
        $xml.SelectNodes('//failure').Count | Should -Be 0
        foreach ($extension in '.html', '.md') {
            $content = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq $extension).FullName -Raw
            $content | Should -Not -Match 'Recommendation:'
        }
        $run.Console | Should -Not -Match 'Recommendation:'
    }

    It 'checks documented parameterless functions without a discovery error' {
        Set-Content -LiteralPath (Join-Path $moduleRoot 'Public\Get-Sample.ps1') -Value @'
function Get-Sample {
    <#
    .SYNOPSIS
        Gets a sample.
    .DESCRIPTION
        Returns one sample.
    .EXAMPLE
        Get-Sample
    .OUTPUTS
        System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()
    1
}
'@
        $run = Invoke-RunnerCase -Parameters @{ Tag = @('Manifest', 'CBH'); ReportFormat = @('All'); Passthru = $true }
        $run.Error | Should -BeNullOrEmpty
        $run.Objects[0].FailedContainers.Count | Should -Be 0 -Because $run.Console
        $run.Objects[0].FailedBlocks.Count | Should -Be 0
        $helpChecks = @($run.Objects[0].Tests | Where-Object { ($_.ExpandedPath -join '.') -like 'Comment-Based Help*' })
        $helpChecks.Count | Should -Be 4
        @($helpChecks | Where-Object Result -ne Passed).Count | Should -Be 0
        $run.Objects[0].FailedCount | Should -Be 0
    }

    It 'includes unexpected-error guidance in XML when human-readable reports are disabled' {
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('None'); Passthru = $true } -Setup @'
function Invoke-Pester {
    param($Configuration)
    $Configuration.Run.Container = @(New-PesterContainer -ScriptBlock {
        Describe 'Unexpected error' -Tag Formatting {
            It 'fails before an assertion' { throw 'Unexpected check failure' }
        }
    })
    Pester\Invoke-Pester -Configuration $Configuration
}
'@
        $run.Error | Should -BeNullOrEmpty
        $run.Files.Count | Should -Be 1
        $run.Files[0].Extension | Should -Be '.xml'
        $xml = [xml](Get-Content -LiteralPath $run.Files[0].FullName -Raw)
        $failure = $xml.SelectSingleNode('//test-case/failure/message').InnerText
        $failure | Should -Match 'Unexpected check failure'
        $failure | Should -Match 'Recommendation: Resolve the reported test or setup error'
        $nativeErrors = ($run.Objects[0].Tests | ForEach-Object { $_.ErrorRecord }) -join "`n"
        $nativeErrors | Should -Match 'Unexpected check failure'
        $nativeErrors | Should -Not -Match 'Recommendation:'
    }

    It 'honors generated config selections and lets explicit None override them without deleting reports' {
        $null = & (Join-Path $repositoryRoot 'New-StandardModuleTestConfig.ps1') -ModuleRoot $moduleRoot -ReportFormat Html
        $settings = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'StandardModuleTestConfig.psd1')
        $settings.ReportFormat | Should -Contain 'Html'
        $configured = Invoke-RunnerCase
        $configured.Error | Should -BeNullOrEmpty
        @($configured.Files | Where-Object Extension -eq '.html').Count | Should -Be 1
        $firstHtml = ($configured.Files | Where-Object Extension -eq '.html').FullName
        $original = Get-Content -LiteralPath $firstHtml -Raw
        $overridden = Invoke-RunnerCase -Parameters @{ ReportFormat = @('None') }
        $overridden.Error | Should -BeNullOrEmpty
        @($overridden.Files | Where-Object Extension -eq '.xml').Count | Should -Be 2
        @($overridden.Files | Where-Object Extension -eq '.html').Count | Should -Be 1
        (Get-Content -LiteralPath $firstHtml -Raw) | Should -BeExactly $original
    }

    It 'writes truthful incomplete reports after a catchable Pester failure and preserves the run error' {
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('All'); Passthru = $true } -Setup @'
function Invoke-Pester { throw ('<script>literal & failure</script>' + [Environment]::NewLine + 'second line ```') }
'@
        $run.Error | Should -Match 'literal & failure'
        $run.Objects.Count | Should -Be 0
        @($run.Files | Where-Object Extension -eq '.xml').Count | Should -Be 0
        $html = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.html').FullName -Raw
        $markdown = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.md').FullName -Raw
        $html | Should -Match 'Incomplete'
        $html | Should -Match 'Test counts unavailable'
        $html | Should -Match 'Native XML/results unavailable'
        $html | Should -Match '&lt;script&gt;literal &amp; failure&lt;/script&gt;'
        $html | Should -Not -Match '<script>literal'
        $html | Should -Not -Match 'Failed: 0'
        $markdown | Should -Match 'second line'
        $run.Console | Should -Match 'Native XML/results unavailable'
    }

    It 'rejects timestamp collisions before running tests and preserves previous reports' {
        $fixedTime = "function Get-Date { [datetime]'2026-10-27T01:00:00Z' }"
        $first = Invoke-RunnerCase -Setup $fixedTime
        $first.Error | Should -BeNullOrEmpty
        $original = Get-Content -LiteralPath $first.Files[0].FullName -Raw
        $second = Invoke-RunnerCase -Setup $fixedTime
        $second.Error | Should -Match 'Report already exists'
        $second.Console | Should -Not -Match 'Pester v'
        $second.Files.Count | Should -Be 1
        (Get-Content -LiteralPath $first.Files[0].FullName -Raw) | Should -BeExactly $original
    }

    It 'attempts human reports after native XML export fails and does not return a success result' {
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('All'); Passthru = $true } -Setup @'
function ConvertTo-NUnitReport { throw 'Native exporter failed' }
'@
        $run.Error | Should -Match 'Xml report'
        $run.Error | Should -Match '\.xml'
        $run.Error | Should -Match 'Native exporter failed'
        $run.Objects.Count | Should -Be 0
        @($run.Files | Where-Object Extension -eq '.html').Count | Should -Be 1
        @($run.Files | Where-Object Extension -eq '.md').Count | Should -Be 1
        $run.Console | Should -Match 'Result: Passed'
    }

    It 'rejects invalid <Label> before running tests' -ForEach @(
        @{ Label = 'mixed All'; Selection = @('All', 'Html') }
        @{ Label = 'mixed None'; Selection = @('None', 'Terminal') }
        @{ Label = 'unknown format'; Selection = @('Json') }
    ) {
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = $Selection }
        $run.Error | Should -Not -BeNullOrEmpty
        $run.Files.Count | Should -Be 0
        $run.Console | Should -Not -Match 'Pester v'
    }

    It 'rejects invalid configured values before running tests' {
        Set-Content -LiteralPath (Join-Path $moduleRoot 'StandardModuleTestConfig.psd1') -Value '@{ ReportFormat = 42 }'
        $run = Invoke-RunnerCase
        $run.Error | Should -Match 'ReportFormat accepts'
        $run.Files.Count | Should -Be 0
        $run.Console | Should -Not -Match 'Pester v'
    }

    It 'does not overwrite a report created after preflight and still writes the remaining formats' {
        $collision = Join-Path $outputPath 'Sample.StandardTests.20261027T010000000Z.html'
        $setup = @"
function Get-Date { [datetime]'2026-10-27T01:00:00Z' }
function ConvertTo-NUnitReport {
    param(`$Result, [switch]`$AsString)
    [IO.File]::WriteAllText('$collision', 'Preserve concurrent report')
    Pester\ConvertTo-NUnitReport -Result `$Result -AsString:`$AsString
}
"@
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('All'); Passthru = $true } -Setup $setup
        $run.Error | Should -Match 'Html report'
        $run.Error | Should -Match ([regex]::Escape($collision))
        $run.Objects.Count | Should -Be 0
        (Get-Content -LiteralPath $collision -Raw) | Should -BeExactly 'Preserve concurrent report'
        @($run.Files | Where-Object Extension -eq '.xml').Count | Should -Be 1
        @($run.Files | Where-Object Extension -eq '.md').Count | Should -Be 1
        $run.Console | Should -Match 'Result: Passed'
    }

    It 'preserves both run and report errors while attempting remaining reports' {
        $collision = Join-Path $outputPath 'Sample.StandardTests.20261027T010000000Z.html'
        $setup = @"
function Get-Date { [datetime]'2026-10-27T01:00:00Z' }
function Invoke-Pester {
    [IO.File]::WriteAllText('$collision', 'Concurrent file')
    throw 'Original Pester failure'
}
"@
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('All') } -Setup $setup
        $run.Error | Should -Match 'Original Pester failure'
        $run.Error | Should -Match 'Html report'
        @($run.Files | Where-Object Extension -eq '.md').Count | Should -Be 1
        @($run.Files | Where-Object Extension -eq '.xml').Count | Should -Be 0
        $run.Console | Should -Match 'Result: Incomplete'
    }

    It 'supports concrete selection <Label> in a custom output directory' -ForEach @(
        @{ Label = 'Html'; Selection = @('Html'); Extensions = @('.xml', '.html') }
        @{ Label = 'Markdown'; Selection = @('Markdown'); Extensions = @('.xml', '.md') }
        @{ Label = 'Terminal'; Selection = @('Terminal'); Extensions = @('.xml') }
        @{ Label = 'Html,Markdown'; Selection = @('Html', 'Markdown'); Extensions = @('.xml', '.html', '.md') }
        @{ Label = 'Html,Terminal'; Selection = @('Html', 'Terminal'); Extensions = @('.xml', '.html') }
        @{ Label = 'Markdown,Terminal'; Selection = @('Markdown', 'Terminal'); Extensions = @('.xml', '.md') }
        @{ Label = 'Html,Markdown,Terminal'; Selection = @('Html', 'Markdown', 'Terminal'); Extensions = @('.xml', '.html', '.md') }
    ) {
        $outputPath = Join-Path $caseRoot 'custom reports'
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = $Selection; OutputPath = $outputPath }
        $run.Error | Should -BeNullOrEmpty
        $run.Files.Count | Should -Be $Extensions.Count
        foreach ($extension in $Extensions) { $run.Files.Extension | Should -Contain $extension }
        @(Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'Tests') -File).Count | Should -Be 0
        if ($Selection -contains 'Terminal') { $run.Console | Should -Match 'LowBar hygiene report' }
        else { $run.Console | Should -Not -Match 'LowBar hygiene report' }
    }

    It 'accepts the empty default config without enabling human-readable reports' {
        $null = & (Join-Path $repositoryRoot 'New-StandardModuleTestConfig.ps1') -ModuleRoot $moduleRoot
        $run = Invoke-RunnerCase
        $run.Error | Should -BeNullOrEmpty
        $run.Objects.Count | Should -Be 0
        $run.Files.Count | Should -Be 1
        $run.Files[0].Extension | Should -Be '.xml'
    }

    It 'treats concrete report names as case-insensitive, unique selections' {
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('Html', 'HTML', 'Markdown') }
        $run.Error | Should -BeNullOrEmpty
        $run.Files.Count | Should -Be 3
    }

    It 'reports <Label> truthfully from actual Pester results' -ForEach @(
        @{
            Label = 'a passing run'; Status = 'Passed'
            Body = "Describe 'Passing' -Tag Formatting { It 'passes' { 1 | Should -Be 1 } }"
        }
        @{
            Label = 'only skipped checks'; Status = 'No conclusive pass'
            Body = "Describe 'Skipped' -Tag Formatting { It 'skips' -Skip { 1 | Should -Be 1 } }"
        }
        @{
            Label = 'only filtered checks'; Status = 'No conclusive pass'
            Body = "Describe 'Filtered' -Tag Formatting { It 'not run' -Tag Integration { 1 | Should -Be 1 } }"
        }
        @{
            Label = 'zero discovery'; Status = 'No checks discovered'
            Body = ''
        }
        @{
            Label = 'a setup error'; Status = 'Incomplete'
            Body = "Describe 'Setup' -Tag Formatting { BeforeAll { throw 'Actual setup failure' }; It 'known check' { 1 | Should -Be 1 } }"
        }
        @{
            Label = 'a discovery error'; Status = 'Incomplete'
            Body = "throw 'Actual discovery failure'"
        }
        @{
            Label = 'partial results'; Status = 'Incomplete'
            Body = "Describe 'Good' -Tag Formatting { It 'passes' { 1 | Should -Be 1 } }; Describe 'Broken' -Tag Formatting { BeforeAll { throw 'Actual partial failure' }; It 'known check' { 1 | Should -Be 1 } }"
        }
    ) {
        $setup = @"
function Invoke-Pester {
    param(`$Configuration)
    `$Configuration.Run.Container = @(New-PesterContainer -ScriptBlock {
        $Body
    })
    Pester\Invoke-Pester -Configuration `$Configuration
}
"@
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('All'); Passthru = $true } -Setup $setup
        $run.Error | Should -BeNullOrEmpty
        $result = $run.Objects[0]
        $html = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.html').FullName -Raw
        $markdown = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.md').FullName -Raw
        $html | Should -Match "Result: <strong>$Status</strong>"
        $markdown | Should -Match "Result: $Status"
        $html | Should -Match "Failed: $($result.FailedCount)"
        $html | Should -Match "Passed: $($result.PassedCount)"
        $html | Should -Match "Skipped: $($result.SkippedCount)"
        $html | Should -Match "Not run: $($result.NotRunCount)"
        if ($Status -eq 'Incomplete') {
            $actualErrors = @($result.FailedContainers) + @($result.FailedBlocks)
            $actualErrors.Count | Should -BeGreaterThan 0
            foreach ($item in $actualErrors) {
                foreach ($record in $item.ErrorRecord) {
                    $html | Should -Match ([regex]::Escape([Net.WebUtility]::HtmlEncode($record.Exception.Message)))
                }
            }
            $html | Should -Match 'Counts cover available results only'
        }
    }

    It 'preserves nested source metadata, literal messages and distinct check locations in every format' {
        $source = 'C:\fixture & <source>\nested\Get-Example.ps1'
        $setup = @'
function Invoke-Pester {
    param($Configuration)
    $Configuration.Run.Container = @(New-PesterContainer -ScriptBlock {
        Describe 'File checks' -Tag Formatting -ForEach @(@{ SourcePath = 'C:\fixture & <source>\nested\Get-Example.ps1'; SourceLine = 7; SourceFunction = 'Get-Example' }) {
            Context 'Nested parameter' -ForEach @(@{ ParameterName = 'Name' }) {
                It 'fails literally' { throw ('<script>alert("literal")</script> & |' + [Environment]::NewLine + '``` fence') }
            }
            It 'passes' { 1 | Should -Be 1 }
            It 'skips' -Skip { 1 | Should -Be 1 }
            It 'filtered' -Tag Integration { 1 | Should -Be 1 }
        }
        Describe 'Module checks' -Tag Formatting -ForEach @(@{ SourceScope = 'Module' }) {
            It 'module-wide failure' { throw 'Module failure' }
        }
        Describe 'Unknown checks' -Tag Formatting {
            It 'unattributed failure' { throw 'Unknown source' }
        }
    })
    Pester\Invoke-Pester -Configuration $Configuration
}
'@
        $run = Invoke-RunnerCase -Parameters @{ ReportFormat = @('All'); Passthru = $true } -Setup $setup
        $run.Error | Should -BeNullOrEmpty
        $result = $run.Objects[0]
        $result.FailedCount | Should -Be 3
        $result.PassedCount | Should -Be 1
        $result.SkippedCount | Should -Be 1
        $result.NotRunCount | Should -Be 1
        $html = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.html').FullName -Raw
        $markdown = Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.md').FullName -Raw
        $html | Should -Match 'C:\\fixture &amp; &lt;source&gt;\\nested\\Get-Example\.ps1:7'
        $html | Should -Match 'Function: Get-Example'
        $html | Should -Match '&lt;script&gt;alert'
        $html | Should -Not -Match '<script>alert'
        $html | Should -Match 'Module-level checks'
        $html | Should -Match 'Unattributed failures'
        $html | Should -Match 'Failed: 3'
        $html | Should -Match 'Skipped: 1'
        $html | Should -Not -Match 'Check location: C:\\fixture'
        $markdown | Should -Match ([regex]::Escape($source))
        $markdown | Should -Match '(?m)^````text$'
        $markdown | Should -Match '(?m)^``` fence$'
        $run.Console | Should -Match ([regex]::Escape($source))
        $run.Console | Should -Match 'Module-level checks'
        $run.Console | Should -Match 'Unattributed failures'
        $xml = [xml](Get-Content -LiteralPath ($run.Files | Where-Object Extension -eq '.xml').FullName -Raw)
        $recommendation = 'Recommendation: Resolve the reported test or setup error using the failure details and available locations, then rerun LowBar.'
        $pattern = [regex]::Escape($recommendation)
        foreach ($failure in $xml.SelectNodes('//test-case/failure/message')) {
            $failure.InnerText | Should -Match $pattern
        }
        [regex]::Matches($html, "<p class='recommendation-text'>$pattern</p>").Count | Should -Be 3
        [regex]::Matches($markdown, $pattern).Count | Should -Be 3
        [regex]::Matches($run.Console, $pattern).Count | Should -Be 3
    }
}
