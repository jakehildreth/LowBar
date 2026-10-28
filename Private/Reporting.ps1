#requires -Version 5.1
function Resolve-StandardReportFormat {
    <#
    .SYNOPSIS
        Validates and expands the report selection.
    .DESCRIPTION
        Rejects invalid combinations and returns unique concrete format names.
    .PARAMETER Selection
        Report names from parameters or configuration.
    .OUTPUTS
        System.String
    .EXAMPLE
        Resolve-StandardReportFormat -Selection All
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$Selection
    )

    $formats = @($Selection)
    foreach ($format in $formats) {
        if ($format -isnot [string] -or $format -notin @('Html', 'Markdown', 'Terminal', 'All', 'None')) {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new('ReportFormat accepts Html, Markdown, Terminal, All, or None.'),
                'InvalidReportFormat', 'InvalidArgument', $Selection
            ))
        }
    }
    if ($formats.Count -gt 1 -and ($formats -contains 'All' -or $formats -contains 'None')) {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.ArgumentException]::new('All and None must each be used alone in ReportFormat.'),
            'InvalidReportFormatCombination', 'InvalidArgument', $Selection
        ))
    }
    if ($formats -contains 'All') { return 'Html', 'Markdown', 'Terminal' }
    $formats | ForEach-Object {
        switch ($_) {
            'Html' { 'Html' }
            'Markdown' { 'Markdown' }
            'Terminal' { 'Terminal' }
        }
    } | Select-Object -Unique
}

function Write-StandardReportFile {
    <#
    .SYNOPSIS
        Creates a report without replacing an existing file.
    .DESCRIPTION
        Uses an exclusive create operation to prevent concurrent overwrites.
    .PARAMETER Path
        Destination file.
    .PARAMETER Content
        Complete report text.
    .PARAMETER Encoding
        Text encoding, matching any declaration in Content.
    .OUTPUTS
        None.
    .EXAMPLE
        Write-StandardReportFile -Path 'C:\Reports\run.md' -Content $markdown
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Content,
        [Parameter()]
        [System.Text.Encoding]$Encoding = [System.Text.UTF8Encoding]::new($false)
    )

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, $Encoding)
        try { $writer.Write($Content) } finally { $writer.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-StandardFailureMessage {
    <#
    .SYNOPSIS
        Ensures a failed check includes a next step.
    .DESCRIPTION
        Keeps check-specific recommendations and adds guidance for unexpected errors.
    .PARAMETER Message
        Original failure text.
    .OUTPUTS
        System.String
    .EXAMPLE
        Get-StandardFailureMessage -Message 'The test could not execute.'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ($Message -notmatch 'Recommendation:') {
        return "$Message`n`nRecommendation: Resolve the reported test or setup error using the failure details and available locations, then rerun LowBar."
    }
    $Message
}

function ConvertTo-StandardReport {
    <#
    .SYNOPSIS
        Projects one Pester run into source-aware report data.
    .DESCRIPTION
        Reads explicit test/block metadata and keeps run errors separate from check outcomes.
    .PARAMETER Result
        Native Pester result, when available.
    .PARAMETER RunError
        A catchable error that prevented Pester from returning.
    .PARAMETER ModuleName
        Module under test.
    .PARAMETER Timestamp
        Shared UTC run timestamp.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .EXAMPLE
        ConvertTo-StandardReport -Result $result -ModuleName Example -Timestamp '20261027T010000000Z'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowNull()][object]$Result,
        [Parameter()][AllowNull()][System.Management.Automation.ErrorRecord]$RunError,
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$Timestamp
    )

    $errors = @(
        if ($RunError) { $RunError.Exception.Message }
        if ($Result) {
            foreach ($item in @($Result.FailedContainers) + @($Result.FailedBlocks)) {
                $name = if ($item.PSObject.Properties['Name']) { $item.Name } else { [string]$item.Item }
                foreach ($record in $item.ErrorRecord) {
                    "${name}: $($record.Exception.Message)`n$($record.ScriptStackTrace)"
                }
            }
        }
    )
    $checks = @(
        if ($Result) {
            foreach ($test in $Result.Tests) {
                $metadata = @{}
                $node = $test
                while ($null -ne $node) {
                    if ($node.Data -is [System.Collections.IDictionary]) {
                        foreach ($key in @('SourcePath', 'SourceLine', 'SourceFunction', 'SourceScope')) {
                            if (-not $metadata.ContainsKey($key) -and $node.Data.Contains($key)) {
                                $metadata[$key] = $node.Data[$key]
                            }
                        }
                    }
                    if ($node.ItemType -eq 'Test') { $node = $node.Block } else { $node = $node.Parent }
                }
                $source = [string]$metadata['SourcePath']
                $group = if ($source) { $source } elseif ($metadata['SourceScope'] -eq 'Module') {
                    'Module-level checks'
                } else { 'Unattributed failures' }
                $checkFile = $test.ScriptBlock.File
                $checkLine = $test.StartLine
                $messages = @(
                    foreach ($record in $test.ErrorRecord) {
                        $record.Exception.Message
                        $target = $record.TargetObject
                        if ($null -ne $target -and $target.PSObject.Properties['File'] -and $target.File) {
                            $checkFile = $target.File
                            $checkLine = $target.Line
                        }
                    }
                )
                $category = if ($checkFile) {
                    [System.IO.Path]::GetFileNameWithoutExtension($checkFile) -replace '^Module\.', '' -replace '\.Tests$', ''
                } else { 'Check' }
                [pscustomobject]@{
                    Name = $test.ExpandedPath
                    Title = $test.ExpandedName
                    Category = $category
                    Outcome = [string]$test.Result
                    Group = $group
                    SourcePath = $source
                    SourceLine = $metadata['SourceLine']
                    SourceFunction = [string]$metadata['SourceFunction']
                    CheckLocation = if ($checkFile) { "${checkFile}:$checkLine" } else { 'Unavailable' }
                    Message = if ($test.Result -eq 'Failed') {
                        Get-StandardFailureMessage -Message ($messages -join "`n`n")
                    } else { $messages -join "`n`n" }
                }
            }
        }
    )
    $counts = [ordered]@{}
    foreach ($outcome in @('Failed', 'Passed', 'Skipped', 'NotRun', 'Inconclusive')) {
        $counts[$outcome] = if ($Result) { @($checks | Where-Object Outcome -eq $outcome).Count } else { $null }
    }
    $status = if (-not $Result -or $errors.Count -gt 0 -or -not $Result.Executed) {
        'Incomplete'
    } elseif ($checks.Count -eq 0) {
        'No checks discovered'
    } elseif ($counts.Failed -gt 0) {
        'Failed'
    } elseif ($counts.Passed -eq 0 -or $counts.Inconclusive -gt 0) {
        'No conclusive pass'
    } else { 'Passed' }
    [pscustomobject]@{
        ModuleName = $ModuleName
        Timestamp = $Timestamp
        Status = $status
        CountsAvailable = ($null -ne $Result)
        Counts = $counts
        Checks = $checks
        Errors = $errors
    }
}

function ConvertTo-StandardTextReport {
    <#
    .SYNOPSIS
        Renders a file-grouped Markdown or terminal report.
    .DESCRIPTION
        Lists failures first and retains literal messages and secondary outcomes.
    .PARAMETER Report
        Shared run projection.
    .PARAMETER Markdown
        Use Markdown headings and safe literal text blocks.
    .OUTPUTS
        System.String
    .EXAMPLE
        ConvertTo-StandardTextReport -Report $report -Markdown
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][psobject]$Report,
        [Parameter()][switch]$Markdown
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("LowBar hygiene report - $($Report.ModuleName)")
    $lines.Add("Result: $($Report.Status)")
    $lines.Add("UTC run: $($Report.Timestamp)")
    if ($Report.CountsAvailable) {
        $lines.Add("Failed: $($Report.Counts.Failed) | Passed: $($Report.Counts.Passed) | Skipped: $($Report.Counts.Skipped) | Not run: $($Report.Counts.NotRun) | Inconclusive: $($Report.Counts.Inconclusive)")
        if ($Report.Status -eq 'Incomplete') { $lines.Add('Counts cover available results only.') }
    } else { $lines.Add('Test counts unavailable. Native XML/results unavailable.') }
    foreach ($errorMessage in $Report.Errors) {
        $lines.Add('')
        $lines.Add('Run error:')
        $lines.Add($errorMessage)
    }
    $lines.Add('')
    $lines.Add('Failed checks by affected file')
    foreach ($group in @($Report.Checks | Where-Object Outcome -eq 'Failed' | Group-Object Group)) {
        $lines.Add('')
        $lines.Add($group.Name)
        foreach ($check in $group.Group) {
            $lines.Add("[$($check.Category)] $($check.Name)")
            if ($check.SourcePath) {
                $source = $check.SourcePath
                if ($check.SourceLine) { $source += ":$($check.SourceLine)" }
                $lines.Add("Affected source: $source")
                if ($check.SourceFunction) { $lines.Add("Function: $($check.SourceFunction)") }
            }
            $lines.Add("Check location: $($check.CheckLocation)")
            $lines.Add($check.Message)
            $lines.Add('')
        }
    }
    $lines.Add('')
    $lines.Add('Other outcomes')
    foreach ($check in @($Report.Checks | Where-Object Outcome -ne 'Failed')) {
        $lines.Add("[$($check.Outcome)] [$($check.Category)] $($check.Name)")
        $lines.Add("Affected source: $($check.Group)")
        if ($check.Message) { $lines.Add($check.Message) }
    }
    $text = $lines -join "`n"
    if ($Markdown.IsPresent) {
        # A longer fence keeps literal messages safe even when they contain code fences.
        $longest = 2
        foreach ($match in [regex]::Matches($text, '`+')) { $longest = [Math]::Max($longest, $match.Length) }
        $fence = '`' * ($longest + 1)
        return "# LowBar hygiene report`n`n${fence}text`n$text`n$fence`n"
    }
    $text + "`n"
}

function ConvertTo-StandardHtmlReport {
    <#
    .SYNOPSIS
        Renders an offline, affected-file-first HTML report.
    .DESCRIPTION
        Escapes result data and embeds styles and file-selection controls without external resources.
    .PARAMETER Report
        Shared run projection.
    .OUTPUTS
        System.String
    .EXAMPLE
        ConvertTo-StandardHtmlReport -Report $report
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][psobject]$Report)

    $encode = { param($value) [System.Net.WebUtility]::HtmlEncode([string]$value) }
    $statusClass = switch ($Report.Status) {
        'Passed' { 'status-passed' }
        'Failed' { 'status-failed' }
        default { 'status-incomplete' }
    }
    $timestamp = $Report.Timestamp -replace '^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(\d{3})Z$', '$1-$2-$3 $4:$5:$6.$7 UTC'
    $body = [System.Text.StringBuilder]::new()
    $null = $body.Append("<header class='report-header'><div class='run-heading'><h1>$(& $encode $Report.ModuleName)</h1><p class='run-status $statusClass'>Result: <strong>$(& $encode $Report.Status)</strong></p></div><p class='run-time'>UTC run: $(& $encode $timestamp)</p>")
    if ($Report.CountsAvailable) {
        $null = $body.Append("<ul class='counts' aria-label='Run summary'><li class='count-failed'>Failed: $($Report.Counts.Failed)</li><li class='count-passed'>Passed: $($Report.Counts.Passed)</li><li>Skipped: $($Report.Counts.Skipped)</li><li>Not run: $($Report.Counts.NotRun)</li><li>Inconclusive: $($Report.Counts.Inconclusive)</li></ul>")
        if ($Report.Status -eq 'Incomplete') { $null = $body.Append('<p class="notice">Counts cover available results only.</p>') }
    } else { $null = $body.Append('<p class="notice">Test counts unavailable. Native XML/results unavailable.</p>') }
    $null = $body.Append('</header>')
    foreach ($errorMessage in $Report.Errors) {
        $null = $body.Append("<section class='notice'><h2>Run error</h2><pre>$(& $encode $errorMessage)</pre></section>")
    }
    $groups = @($Report.Checks | Where-Object Outcome -eq 'Failed' | Group-Object Group |
        Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)
    $sourceLabel = if ($groups.Count -eq 1) { 'affected source' } else { 'affected sources' }
    $null = $body.Append("<section id='failures' tabindex='-1' aria-labelledby='failures-heading'><div class='section-heading'><h2 id='failures-heading'>Failed checks by affected file</h2><p>$($groups.Count) $sourceLabel</p></div>")
    if ($groups.Count -gt 0) {
        $null = $body.Append('<div class="split"><nav class="file-nav" aria-label="Affected files"><p class="nav-help">Select a file to review its failures.</p>')
        for ($index = 0; $index -lt $groups.Count; $index++) {
            $groupName = $groups[$index].Name
            $fileName = ($groupName -split '[\\/]')[-1]
            $directory = if ($groupName -match '[\\/]') { $groupName -replace '[\\/][^\\/]+$', '' } else { 'No source file' }
            $failureLabel = if ($groups[$index].Count -eq 1) { 'failed check' } else { 'failed checks' }
            $null = $body.Append("<a class='file-choice' href='#file-$index' aria-controls='file-$index' title='$(& $encode $groupName)'><span class='file-label'><span class='file-name'>$(& $encode $fileName)</span><span class='failure-count'>$($groups[$index].Count)<span class='sr-only'> $failureLabel</span></span></span><span class='file-directory'>$(& $encode $directory)</span></a>")
        }
        $null = $body.Append('</nav><div class="file-details">')
        for ($index = 0; $index -lt $groups.Count; $index++) {
            $groupName = $groups[$index].Name
            $fileName = ($groupName -split '[\\/]')[-1]
            $failureLabel = if ($groups[$index].Count -eq 1) { 'failed check' } else { 'failed checks' }
            $null = $body.Append("<section class='file-group' id='file-$index' tabindex='-1' aria-labelledby='file-heading-$index'><div class='file-heading'><h2 id='file-heading-$index'>$(& $encode $fileName)</h2><p>$($groups[$index].Count) $failureLabel</p></div><p class='source-path'>$(& $encode $groupName)</p>")
            foreach ($check in $groups[$index].Group) {
                $source = $check.SourcePath
                if ($check.SourceLine) { $source += ":$($check.SourceLine)" }
                $title = if ($check.PSObject.Properties['Title'] -and $check.Title) { $check.Title } else { $check.Name }
                $recommendations = @(
                    foreach ($match in [regex]::Matches($check.Message, '(?m)Recommendation:[^\r\n]+')) {
                        # Pester appends assertion values and opt-out notes after the correction.
                        ($match.Value -replace ', but (?:got|found)\b.*$', '' -replace '\s+To opt out:.*$', '').Trim()
                    }
                ) | Select-Object -Unique
                $null = $body.Append("<article class='failure'><div class='check-heading'><h3>$(& $encode $title)</h3><span class='check-category'>$(& $encode $check.Category)</span></div>")
                if ($check.SourceFunction) { $null = $body.Append("<p class='function-name'>Function: $(& $encode $check.SourceFunction)</p>") }
                foreach ($recommendation in $recommendations) {
                    $null = $body.Append("<p class='recommendation-text'>$(& $encode $recommendation)</p>")
                }
                $null = $body.Append("<details class='diagnostic'><summary>Failure details <span>Original message and locations</span></summary><div class='diagnostic-body'><p class='check-path'>$(& $encode $check.Name)</p>")
                if ($source) {
                    $null = $body.Append("<p class='location'>Affected source: $(& $encode $source)</p>")
                }
                $null = $body.Append("<p class='location'>Check location: $(& $encode $check.CheckLocation)</p><h4>Original failure</h4><pre>$(& $encode $check.Message)</pre></div></details></article>")
            }
            $null = $body.Append('</section>')
        }
        $null = $body.Append('</div></div>')
    } else {
        $emptyMessage = switch ($Report.Status) {
            'Passed' { 'No failed checks in the available results. Review skipped and not-run checks below for coverage gaps.' }
            'Incomplete' { 'This run is incomplete, not a pass. Resolve the run errors and rerun LowBar.' }
            'No checks discovered' { 'No checks were discovered. Check the module paths and tag filters, then rerun LowBar.' }
            default { 'No conclusive pass. Review skipped, not-run, and inconclusive checks below, then rerun LowBar.' }
        }
        $null = $body.Append("<p class='empty-state $statusClass'>$emptyMessage</p>")
    }
    $null = $body.Append('</section>')
    $otherChecks = @($Report.Checks | Where-Object Outcome -ne 'Failed')
    $checkLabel = if ($otherChecks.Count -eq 1) { 'check' } else { 'checks' }
    $null = $body.Append("<details class='other'><summary>Other outcomes <span>$($otherChecks.Count) $checkLabel</span></summary>")
    if ($otherChecks.Count -gt 0) {
        $null = $body.Append('<table><caption class="sr-only">Passed, skipped, not-run, and inconclusive checks</caption><thead><tr><th scope="col">Outcome</th><th scope="col">Check and affected source</th></tr></thead><tbody>')
        foreach ($check in $otherChecks) {
            $outcomeClass = if ($check.Outcome -eq 'Passed') { 'count-passed' } else { 'outcome-neutral' }
            $null = $body.Append("<tr><td class='$outcomeClass'>$(& $encode $check.Outcome)</td><td><p><span class='check-category'>$(& $encode $check.Category)</span> $(& $encode $check.Name)</p><p class='source-path'>Affected source: $(& $encode $check.Group)</p>")
            if ($check.Message) { $null = $body.Append("<pre>$(& $encode $check.Message)</pre>") }
            $null = $body.Append('</td></tr>')
        }
        $null = $body.Append('</tbody></table>')
    } else {
        $null = $body.Append('<p class="nav-help">No other check outcomes are available.</p>')
    }
    $null = $body.Append('</details><footer><strong>LowBar</strong><span>This report checks hygiene, not behavioral correctness.</span></footer>')
    @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(& $encode $Report.ModuleName) - LowBar hygiene report</title>
<style>
:root{color-scheme:light;--paper:#f7f8fa;--surface:#fff;--ink:#202a35;--muted:#536171;--line:#cbd3dd;--accent:#244e86;--fail:#a62232;--pass:#17613f}
*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif}
a{color:var(--accent);text-underline-offset:.2em}
:focus-visible{outline:3px solid #986300;outline-offset:4px}
::selection{background:#cce0ff;color:#172f50}
[hidden]{display:none!important}
.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap;border:0}
.skip-link{position:absolute;top:-100px;left:1rem;z-index:2;background:var(--surface);padding:.75rem 1rem}
.skip-link:focus{top:1rem}
.brand-bar{border-bottom:1px solid var(--line);background:var(--surface)}
.brand-inner{max-width:1328px;margin:auto;display:flex;align-items:center;gap:1rem;padding:1rem 2rem;font-size:.875rem;color:var(--muted)}
.brand-inner strong{color:var(--ink);font-size:1.125rem;letter-spacing:-.025em}
main{max-width:1328px;margin:auto;padding:2.5rem 2rem}
h1,h2,h3,h4,p{margin:0;overflow-wrap:anywhere}
h1{font-size:2rem;line-height:1.2;letter-spacing:-.025em}
h2{font-size:1.25rem;line-height:1.35;letter-spacing:-.015em}
h3{font-size:1.0625rem;line-height:1.5;font-weight:650}
h4{font-size:.875rem;margin:1.5rem 0 .5rem}
.run-heading,.section-heading,.file-heading,.check-heading{display:flex;align-items:baseline;justify-content:space-between;gap:.75rem 1.5rem;flex-wrap:wrap}
.run-status{font-size:.875rem;padding:.375rem .75rem;border:1px solid currentColor;border-radius:4px}
.status-failed,.count-failed{color:var(--fail)}
.status-passed,.count-passed{color:var(--pass)}
.status-incomplete{color:#654300}
.run-time{margin-top:.75rem;color:var(--muted);font-size:.875rem}
.counts{display:flex;flex-wrap:wrap;gap:.5rem 2rem;list-style:none;padding:1rem 0;margin:1.5rem 0 0;border-block:1px solid var(--line);font-size:.9375rem;font-variant-numeric:tabular-nums}
.counts li:first-child{font-weight:700}
.counts li:not(:first-child):not(.count-passed){color:var(--muted)}
.notice{margin:1rem 0;padding:1rem 1.25rem;background:#fff1d5;color:#654300}
.notice h2{margin-bottom:.75rem}
.section-heading{margin:2rem 0 1.25rem}
.section-heading p,.file-heading p{color:var(--muted);font-size:.875rem}
.split{display:grid;grid-template-columns:minmax(220px,280px) minmax(0,1fr);gap:2rem;align-items:start}
.file-nav{position:sticky;top:1rem;max-height:calc(100vh - 2rem);overflow:auto;padding:0 .25rem .25rem}
.nav-help{font-size:.8125rem;color:var(--muted);margin:0 0 .75rem}
.file-choice{display:block;padding:1rem;margin-top:.25rem;text-decoration:none;border:1px solid transparent;border-radius:4px;overflow-wrap:anywhere}
.file-choice:hover{background:#e9eef5;border-color:var(--line)}
.file-choice[aria-current="true"]{background:#e6edf7;border-color:#a6bad6;color:#183d70}
.file-label{display:flex;align-items:baseline;justify-content:space-between;gap:.75rem}
.file-name{font-weight:650;font-size:.9375rem}
.failure-count{font-size:.8125rem;font-weight:700;font-variant-numeric:tabular-nums;flex-shrink:0}
.file-directory{display:block;color:var(--muted);font-size:.75rem;line-height:1.5;margin-top:.375rem}
.file-details,.file-group{min-width:0}
.file-group{background:var(--surface);border:1px solid var(--line);padding:1.5rem 2rem;scroll-margin-top:1rem}
.file-group+.file-group{margin-top:1.5rem}
.source-path,.location{font:.8125rem/1.6 Consolas,"Liberation Mono",monospace;color:var(--muted);overflow-wrap:anywhere}
.file-group>.source-path{margin:.5rem 0 1.5rem}
.failure{padding:1.5rem 0;border-top:1px solid var(--line)}
.failure:last-child{padding-bottom:.25rem}
.check-heading{flex-wrap:nowrap;align-items:baseline}
.check-category{font-size:.75rem;color:var(--muted);font-weight:500;overflow-wrap:anywhere}
.check-heading .check-category{max-width:35%;flex-shrink:0}
.function-name{color:var(--muted);font-size:.8125rem;margin-top:.375rem}
.recommendation-text{margin-top:1rem;padding:.875rem 1rem;background:#edf5f0;color:#174e35;font-size:.9375rem;line-height:1.65;overflow-wrap:anywhere}
summary{cursor:pointer;touch-action:manipulation;overflow-wrap:anywhere}
.diagnostic{margin-top:1rem;font-size:.8125rem}
.diagnostic>summary{padding:.5rem 0;color:var(--accent);min-height:44px}
.diagnostic>summary span{color:var(--muted);margin-left:.5rem}
.diagnostic-body{padding:.75rem 0 .25rem}
.check-path{color:var(--muted);margin-bottom:1rem}
.location+.location{margin-top:.5rem}
pre{white-space:pre-wrap;overflow-wrap:anywhere;font:.8125rem/1.7 Consolas,"Liberation Mono",monospace;margin:0}
.diagnostic pre{padding:1rem;background:var(--paper);border:1px solid var(--line)}
.empty-state{max-width:75ch;padding:1.5rem 0;font-size:1rem}
.other{margin-top:2rem;border-top:1px solid var(--line);padding-top:1rem}
.other>summary{font-weight:650;padding:.5rem 0;min-height:44px}
.other>summary span{color:var(--muted);font-size:.875rem;font-weight:400;margin-left:.75rem}
table{width:100%;border-collapse:collapse;table-layout:fixed;margin-top:1rem;font-size:.875rem}
th,td{text-align:left;vertical-align:top;padding:1rem;border-bottom:1px solid var(--line);overflow-wrap:anywhere}
th{color:var(--muted);font-size:.8125rem;font-weight:600;background:#edf0f4}
th:first-child{width:8rem}
td:first-child{font-weight:600;font-size:.8125rem}
td .source-path{margin-top:.5rem}
td pre{margin-top:1rem}
.outcome-neutral{color:var(--muted)}
footer{display:flex;gap:1rem;align-items:baseline;flex-wrap:wrap;margin-top:3rem;padding-top:1rem;border-top:1px solid var(--line);color:var(--muted);font-size:.8125rem}
footer strong{color:var(--ink)}
@media(max-width:850px){
  main{padding:1.5rem}
  .brand-inner{padding:1rem 1.5rem}
  .split{grid-template-columns:minmax(180px,230px) minmax(0,1fr);gap:1rem}
  .file-group{padding:1.25rem}
  .check-heading{flex-wrap:wrap;gap:.375rem}
  .check-heading .check-category{max-width:none}
}
@media(max-width:650px){
  main{padding:1.5rem 1rem}
  .brand-inner{padding:.875rem 1rem}
  h1{font-size:1.75rem}
  .run-heading{gap:1rem}
  .run-status{font-size:.8125rem}
  .counts{gap:.5rem 1rem;font-size:.8125rem}
  .split{grid-template-columns:minmax(0,1fr);gap:1.25rem}
  .file-nav{position:static;max-height:180px;padding:.25rem}
  .file-choice{padding:.75rem}
  .file-group{padding:1rem}
  .file-heading{gap:.5rem}
  .recommendation-text{padding:.75rem}
  .diagnostic>summary span{display:block;margin-left:1rem}
  th,td{padding:.75rem .5rem}
  th:first-child{width:6rem}
}
@media print{
  body{background:white;font-size:11pt}
  main{max-width:none;padding:0}
  .brand-bar,.skip-link,.file-nav{display:none}
  .split{display:block}
  .file-group[hidden]{display:block!important}
  .file-group{border:0;padding:0;margin-top:1.5rem;break-before:auto}
  .failure{break-inside:avoid}
  .diagnostic-body{display:block!important}
  details::details-content{content-visibility:visible;display:block}
  .other{display:block}
  .run-status,.recommendation-text{color:var(--ink)}
}
</style></head><body>
<a class='skip-link' href='#failures'>Skip to failed checks</a>
<div class='brand-bar'><div class='brand-inner'><strong>LowBar</strong><span>Module hygiene report</span></div></div>
<main>$body</main>
<script>
(() => {
  const links = Array.from(document.querySelectorAll('.file-choice'));
  const groups = Array.from(document.querySelectorAll('.file-group'));
  function selectFile(moveFocus = false) {
    const selected = groups.find(group => '#' + group.id === location.hash) || groups.find(group => !group.hidden) || groups[0];
    if (!selected) return;
    groups.forEach(group => { group.hidden = group !== selected; });
    links.forEach(link => {
      if (link.hash === '#' + selected.id) link.setAttribute('aria-current', 'true');
      else link.removeAttribute('aria-current');
    });
    if (moveFocus) {
      selected.focus({preventScroll: true});
      if (matchMedia('(max-width:650px)').matches) selected.scrollIntoView({block: 'start'});
    }
  }
  links.forEach(link => link.addEventListener('click', event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    history.pushState(null, '', link.hash);
    selectFile(true);
  }));
  selectFile();
  window.addEventListener('hashchange', () => selectFile());
  window.addEventListener('popstate', () => selectFile());
})();
</script></body></html>
"@
}
