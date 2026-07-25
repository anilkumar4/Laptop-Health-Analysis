#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Developer Health Analyzer.

.DESCRIPTION
    Read-only diagnostics for Windows developer workstations. The analyzer scans
    Windows health, storage, performance, developer tools, security, startup,
    battery status, event logs, and cleanup opportunities, then emits console,
    HTML, JSON, and CSV reports.

    The analyzer never deletes files, never changes Windows configuration, and
    never performs cleanup automatically.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDirectory,

    [Parameter()]
    [switch]$SkipBattery,

    [Parameter()]
    [switch]$SkipEventLogs,

    [Parameter()]
    [switch]$NoHtml,

    [Parameter()]
    [switch]$Quiet,

    [Parameter()]
    [switch]$QuickScan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:AnalyzerVersion = '1.0.0'
$script:ScriptRoot = $PSScriptRoot
$script:ModuleRoot = Join-Path $script:ScriptRoot 'Modules'
$script:AssetRoot = Join-Path $script:ScriptRoot 'Assets'
$script:StartedAt = Get-Date

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $script:ScriptRoot 'Reports'
}

$script:LogDirectory = Join-Path $script:ScriptRoot 'Logs'
foreach ($directory in @($OutputDirectory, $script:LogDirectory)) {
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
}

$script:LogFile = Join-Path $script:LogDirectory ("HealthAnalyzer_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

function Write-AnalyzerLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    try {
        Add-Content -Path $script:LogFile -Value $entry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Verbose "Unable to write log entry: $($_.Exception.Message)"
    }

    if ($Quiet) { return }

    switch ($Level) {
        'ERROR' { Write-Host $entry -ForegroundColor Red }
        'WARN' { Write-Host $entry -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $entry -ForegroundColor Green }
        'DEBUG' { Write-Verbose $entry }
        default { Write-Host $entry -ForegroundColor Cyan }
    }
}

$script:LogScriptBlock = ${function:Write-AnalyzerLog}

function Test-Administrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Import-AnalyzerModule {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $path = Join-Path $script:ModuleRoot $Name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required module not found: $path"
    }

    Import-Module $path -Force -DisableNameChecking -ErrorAction Stop
    Write-AnalyzerLog "Loaded module $Name" -Level 'DEBUG'
}

function Import-AnalyzerModules {
    [CmdletBinding()]
    param()

    $modules = @(
        'Common.psm1',
        'WindowsHealth.psm1',
        'Storage.psm1',
        'Performance.psm1',
        'DeveloperEnvironment.psm1',
        'Security.psm1',
        'Battery.psm1',
        'EventLogs.psm1',
        'Startup.psm1',
        'CleanupAdvisor.psm1',
        'HtmlReport.psm1'
    )

    foreach ($module in $modules) {
        Import-AnalyzerModule -Name $module
    }
}

function Get-HealthScores {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][pscustomobject]$ReportData)

    $windowsScore = Get-SafeScore -Value $ReportData.WindowsHealth.Score -Default 50
    $eventScore = Get-SafeScore -Value $ReportData.EventLogs.Score -Default 70
    $startupScore = Get-SafeScore -Value $ReportData.Startup.Score -Default 70
    $performanceScore = Get-SafeScore -Value $ReportData.Performance.Score -Default 50
    $windowsComposite = [math]::Round(($windowsScore * 0.70) + ($eventScore * 0.30))
    $performanceComposite = [math]::Round(($performanceScore * 0.70) + ($startupScore * 0.30))
    $storageScore = Get-SafeScore -Value $ReportData.Storage.Score -Default 50
    $securityScore = Get-SafeScore -Value $ReportData.Security.Score -Default 50
    $batteryScore = Get-SafeScore -Value $ReportData.Battery.Score -Default 100
    $developerScore = Get-SafeScore -Value $ReportData.DeveloperEnvironment.Score -Default 50

    $overall = [math]::Round(
        ($windowsComposite * 0.25) +
        ($performanceComposite * 0.20) +
        ($storageScore * 0.20) +
        ($securityScore * 0.15) +
        ($batteryScore * 0.10) +
        ($developerScore * 0.10)
    )

    [pscustomobject]@{
        Overall = [int](Limit-Number -Value $overall -Minimum 0 -Maximum 100)
        Windows = [int](Limit-Number -Value $windowsComposite -Minimum 0 -Maximum 100)
        Performance = [int](Limit-Number -Value $performanceComposite -Minimum 0 -Maximum 100)
        Storage = [int](Limit-Number -Value $storageScore -Minimum 0 -Maximum 100)
        Security = [int](Limit-Number -Value $securityScore -Minimum 0 -Maximum 100)
        Battery = [int](Limit-Number -Value $batteryScore -Minimum 0 -Maximum 100)
        DeveloperEnvironment = [int](Limit-Number -Value $developerScore -Minimum 0 -Maximum 100)
        EventLogs = [int](Limit-Number -Value $eventScore -Minimum 0 -Maximum 100)
        Startup = [int](Limit-Number -Value $startupScore -Minimum 0 -Maximum 100)
    }
}

function Get-AggregatedRecommendations {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][pscustomobject]$ReportData)

    $priorityOrder = @{ Critical = 0; High = 1; Medium = 2; Low = 3 }
    $recommendations = New-Object System.Collections.ArrayList
    $sources = @(
        @{ Name = 'Windows'; Data = $ReportData.WindowsHealth },
        @{ Name = 'Storage'; Data = $ReportData.Storage },
        @{ Name = 'Performance'; Data = $ReportData.Performance },
        @{ Name = 'Developer Environment'; Data = $ReportData.DeveloperEnvironment },
        @{ Name = 'Security'; Data = $ReportData.Security },
        @{ Name = 'Battery'; Data = $ReportData.Battery },
        @{ Name = 'Event Logs'; Data = $ReportData.EventLogs },
        @{ Name = 'Startup'; Data = $ReportData.Startup },
        @{ Name = 'Cleanup Advisor'; Data = $ReportData.CleanupAdvisor }
    )

    foreach ($source in $sources) {
        if ($null -eq $source.Data -or $null -eq $source.Data.Recommendations) { continue }
        foreach ($recommendation in $source.Data.Recommendations) {
            [void]$recommendations.Add((New-AnalyzerRecommendation `
                -Priority (Get-ObjectPropertyValue -InputObject $recommendation -Name 'Priority' -Default 'Medium') `
                -Category (Get-ObjectPropertyValue -InputObject $recommendation -Name 'Category' -Default $source.Name) `
                -Problem (Get-ObjectPropertyValue -InputObject $recommendation -Name 'Problem' -Default 'Review finding') `
                -Reason (Get-ObjectPropertyValue -InputObject $recommendation -Name 'Reason' -Default '') `
                -Risk (Get-ObjectPropertyValue -InputObject $recommendation -Name 'Risk' -Default '') `
                -SuggestedFix (Get-ObjectPropertyValue -InputObject $recommendation -Name 'SuggestedFix' -Default '') `
                -EstimatedImprovement (Get-ObjectPropertyValue -InputObject $recommendation -Name 'EstimatedImprovement' -Default 'Varies')))
        }
    }

    $recommendations | Sort-Object @{ Expression = { if ($priorityOrder.ContainsKey($_.Priority)) { $priorityOrder[$_.Priority] } else { 4 } } }, Category, Problem
}

function Invoke-ScanSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][int]$PercentComplete
    )

    Write-AnalyzerLog "Scanning $Name" -Level 'INFO'
    if (-not $Quiet) {
        Write-Progress -Activity 'Developer Health Analyzer' -Status $Name -PercentComplete $PercentComplete
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $result = & $ScriptBlock
        $timer.Stop()
        Write-AnalyzerLog ("Completed {0} in {1:n1}s" -f $Name, $timer.Elapsed.TotalSeconds) -Level 'SUCCESS'
        return $result
    }
    catch {
        $timer.Stop()
        Write-AnalyzerLog "Failed $Name`: $($_.Exception.Message)" -Level 'ERROR'
        Write-AnalyzerLog $_.ScriptStackTrace -Level 'DEBUG'
        return [pscustomobject]@{
            Score = 50
            Error = $_.Exception.Message
            Recommendations = @(New-AnalyzerRecommendation -Priority Medium -Category $Name -Problem "$Name scan failed" -Reason $_.Exception.Message -Risk 'Report section is incomplete.' -SuggestedFix 'Run PowerShell as Administrator and review the log file.' -EstimatedImprovement 'Improves diagnostic completeness')
        }
    }
}

function Invoke-HealthAnalysis {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $metadata = [pscustomobject]@{
        AnalyzerVersion = $script:AnalyzerVersion
        GeneratedAt = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        IsAdministrator = Test-Administrator
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Edition = $PSVersionTable.PSEdition
        ProcessArchitecture = $env:PROCESSOR_ARCHITECTURE
        ReadOnlyMode = $true
        QuickScan = [bool]$QuickScan
        OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
        LogFile = $script:LogFile
    }

    $report = [pscustomobject]@{
        Metadata = $metadata
        WindowsHealth = $null
        Storage = $null
        Performance = $null
        DeveloperEnvironment = $null
        Security = $null
        Battery = $null
        EventLogs = $null
        Startup = $null
        CleanupAdvisor = $null
        Scores = $null
        OverallScore = 0
        Recommendations = @()
    }

    $sections = [ordered]@{
        WindowsHealth = @{ Name = 'Windows health'; Script = { Get-WindowsHealthReport -Log $script:LogScriptBlock } }
        Storage = @{ Name = 'Storage'; Script = { Get-StorageReport -Log $script:LogScriptBlock -QuickScan:$QuickScan } }
        Performance = @{ Name = 'Performance'; Script = { Get-PerformanceReport -Log $script:LogScriptBlock } }
        DeveloperEnvironment = @{ Name = 'Developer environment'; Script = { Get-DeveloperEnvironmentReport -Log $script:LogScriptBlock -QuickScan:$QuickScan } }
        Security = @{ Name = 'Security'; Script = { Get-SecurityReport -Log $script:LogScriptBlock } }
        EventLogs = @{ Name = 'Event logs'; Script = { if ($SkipEventLogs) { Get-SkippedReport -Name 'Event logs' } else { Get-EventLogReport -Log $script:LogScriptBlock } } }
        Startup = @{ Name = 'Startup'; Script = { Get-StartupReport -Log $script:LogScriptBlock } }
        Battery = @{ Name = 'Battery'; Script = { if ($SkipBattery) { Get-SkippedReport -Name 'Battery' -DefaultScore 100 } else { Get-BatteryReport -Log $script:LogScriptBlock } } }
        CleanupAdvisor = @{ Name = 'Cleanup advisor'; Script = { Get-CleanupReport -DeveloperEnvironment $report.DeveloperEnvironment -Storage $report.Storage -Log $script:LogScriptBlock -QuickScan:$QuickScan } }
    }

    $index = 0
    foreach ($key in $sections.Keys) {
        $index++
        $percent = [math]::Min(95, [math]::Round(($index / $sections.Count) * 95))
        $section = $sections[$key]
        $report.$key = Invoke-ScanSection -Name $section.Name -ScriptBlock $section.Script -PercentComplete $percent
    }

    if (-not $Quiet) { Write-Progress -Activity 'Developer Health Analyzer' -Completed }

    $report.Scores = Get-HealthScores -ReportData $report
    $report.OverallScore = $report.Scores.Overall
    $report.Recommendations = @(Get-AggregatedRecommendations -ReportData $report)
    return $report
}

function Export-AnalyzerReports {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$ReportData)

    $jsonPath = Join-Path $OutputDirectory 'HealthReport.json'
    $recommendationsPath = Join-Path $OutputDirectory 'Recommendations.json'
    $foldersPath = Join-Path $OutputDirectory 'LargestFolders.csv'
    $filesPath = Join-Path $OutputDirectory 'LargestFiles.csv'

    $ReportData | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding UTF8
    $ReportData.Recommendations | ConvertTo-Json -Depth 8 | Set-Content -Path $recommendationsPath -Encoding UTF8

    $storageFolders = $null
    $storageFiles = $null
    if ($null -ne $ReportData.Storage -and $null -ne $ReportData.Storage.PSObject.Properties['LargestFolders']) {
        $storageFolders = $ReportData.Storage.LargestFolders
    }
    if ($null -ne $ReportData.Storage -and $null -ne $ReportData.Storage.PSObject.Properties['LargestFiles']) {
        $storageFiles = $ReportData.Storage.LargestFiles
    }

    if ($storageFolders -and @($storageFolders).Count -gt 0) {
        $storageFolders | Export-Csv -Path $foldersPath -NoTypeInformation -Encoding UTF8
    }
    if ($storageFiles -and @($storageFiles).Count -gt 0) {
        $storageFiles | Export-Csv -Path $filesPath -NoTypeInformation -Encoding UTF8
    }
    if (-not $NoHtml) {
        $htmlPath = Join-Path $OutputDirectory 'HealthReport.html'
        New-HtmlReport -ReportData $ReportData -OutputPath $htmlPath -AssetRoot $script:AssetRoot
    }

    Write-AnalyzerLog "Wrote reports to $OutputDirectory" -Level 'SUCCESS'
}

function Show-Banner {
    [CmdletBinding()]
    param()
    if ($Quiet) { return }
    Write-Host ''
    Write-Host 'Developer Health Analyzer' -ForegroundColor Cyan
    Write-Host 'Read-only Windows diagnostics for software developers' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-ConsoleSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$ReportData)
    if ($Quiet) { return }

    $score = $ReportData.Scores
    Write-Host ''
    Write-Host 'Health Summary' -ForegroundColor White
    Write-Host ('  Overall:               {0,3}/100 {1}' -f $score.Overall, (Get-ConsoleBar -Value $score.Overall -Width 30)) -ForegroundColor (Get-ConsoleScoreColor -Score $score.Overall)
    Write-Host ('  Windows:               {0,3}/100' -f $score.Windows)
    Write-Host ('  Performance:           {0,3}/100' -f $score.Performance)
    Write-Host ('  Storage:               {0,3}/100' -f $score.Storage)
    Write-Host ('  Security:              {0,3}/100' -f $score.Security)
    Write-Host ('  Battery:               {0,3}/100' -f $score.Battery)
    Write-Host ('  Developer Environment: {0,3}/100' -f $score.DeveloperEnvironment)
    Write-Host ''

    $critical = @($ReportData.Recommendations | Where-Object Priority -eq 'Critical').Count
    $high = @($ReportData.Recommendations | Where-Object Priority -eq 'High').Count
    $medium = @($ReportData.Recommendations | Where-Object Priority -eq 'Medium').Count
    $low = @($ReportData.Recommendations | Where-Object Priority -eq 'Low').Count
    Write-Host ('Recommendations: {0} critical, {1} high, {2} medium, {3} low' -f $critical, $high, $medium, $low) -ForegroundColor Cyan

    $topRecommendations = @($ReportData.Recommendations | Select-Object -First 5)
    if ($topRecommendations.Count -gt 0) {
        Write-Host ''
        Write-Host 'Top Findings' -ForegroundColor White
        foreach ($item in $topRecommendations) {
            Write-Host ('  [{0}] {1}: {2}' -f $item.Priority, $item.Category, $item.Problem)
        }
    }
    Write-Host ''
}

function Get-ConsoleScoreColor {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][int]$Score)
    if ($Score -ge 85) { return 'Green' }
    if ($Score -ge 70) { return 'Cyan' }
    if ($Score -ge 55) { return 'Yellow' }
    return 'Red'
}

function Get-ConsoleBar {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][int]$Value, [Parameter()][int]$Width = 30)
    $filled = [int][math]::Round(($Value / 100) * $Width)
    $filled = [int](Limit-Number -Value $filled -Minimum 0 -Maximum $Width)
    return ('#' * $filled) + ('-' * ($Width - $filled))
}

function Start-Analyzer {
    [CmdletBinding()]
    param()

    Show-Banner
    Write-AnalyzerLog 'Starting read-only scan. No cleanup or system modification will be performed.' -Level 'INFO'
    try {
        Import-AnalyzerModules
        $report = Invoke-HealthAnalysis
        Show-ConsoleSummary -ReportData $report
        Export-AnalyzerReports -ReportData $report
        $elapsed = (Get-Date) - $script:StartedAt
        Write-AnalyzerLog ("Analysis complete in {0:n1}s" -f $elapsed.TotalSeconds) -Level 'SUCCESS'
        if (-not $Quiet) {
            Write-Host 'Output files:' -ForegroundColor White
            Get-ChildItem -Path $OutputDirectory -File | Sort-Object Name | ForEach-Object {
                Write-Host ('  {0} ({1:n1} KB)' -f $_.Name, ($_.Length / 1KB))
            }
        }
    }
    catch {
        Write-AnalyzerLog "Fatal analyzer error: $($_.Exception.Message)" -Level 'ERROR'
        throw
    }
}

Start-Analyzer



