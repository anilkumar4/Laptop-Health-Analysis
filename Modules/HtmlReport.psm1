Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Generates the self-contained HTML dashboard report.
.DESCRIPTION
    Produces a single HTML file embedding all CSS, JS, and report data inline.
    Uses Bootstrap 5, Chart.js, and Lucide icons via CDN. The report works
    offline once loaded -- all data is embedded as a JSON blob.
#>

function ConvertTo-HtmlText {
    [CmdletBinding()]
    param([Parameter()]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode(($Value | Out-String).Trim())
}

function New-ScoreCardHtml {
    [CmdletBinding()]
    param([string]$Label, [int]$Score, [string]$Icon)
    $class = if ($Score -ge 85) { 'excellent' } elseif ($Score -ge 70) { 'good' } elseif ($Score -ge 55) { 'warn' } else { 'bad' }
    return @"
<div class="score-card $class">
  <div class="score-icon"><i data-lucide="$Icon"></i></div>
  <div>
    <div class="score-label">$Label</div>
    <div class="score-value">$Score<span>/100</span></div>
    <div class="progress"><div class="progress-bar" style="width:$Score%"></div></div>
  </div>
</div>
"@
}

function New-TableHtml {
    [CmdletBinding()]
    param(
        [Parameter()]$Items,
        [Parameter(Mandatory)][string]$Id,
        [Parameter()][string[]]$Properties,
        [Parameter()][switch]$ShowExport
    )
    $array = @($Items)
    if ($array.Count -eq 0) { return "<p class='muted'>No data collected.</p>" }
    if (-not $Properties -or $Properties.Count -eq 0) {
        $Properties = @($array[0].PSObject.Properties.Name | Select-Object -First 8)
    }

    $head = ($Properties | ForEach-Object { "<th>$(ConvertTo-HtmlText $_)</th>" }) -join ''

    $rowsHtml = [System.Text.StringBuilder]::new()
    foreach ($item in $array) {
        [void]$rowsHtml.Append('<tr>')
        foreach ($property in $Properties) {
            $value = Get-ObjectPropertyValue -InputObject $item -Name $property -Default ''
            if ($value -is [array]) { $value = ($value -join ', ') }
            [void]$rowsHtml.Append("<td>$(ConvertTo-HtmlText $value)</td>")
        }
        [void]$rowsHtml.Append('</tr>')
    }

    $exportBtn = ''
    if ($ShowExport) {
        $exportBtn = "<button class='btn btn-sm btn-outline-secondary export-csv' data-table='$Id' title='Export CSV'>CSV</button>"
    }

    return @"
<div class="table-responsive">
  <div style="display:flex;gap:10px;align-items:center;margin-bottom:10px">
    <input class="form-control form-control-sm table-search" placeholder="Search..." data-table="$Id" style="flex:1;max-width:320px">
    $exportBtn
  </div>
  <table id="$Id" class="table table-sm sortable align-middle">
    <thead><tr>$head</tr></thead>
    <tbody>$($rowsHtml.ToString())</tbody>
  </table>
</div>
"@
}

function New-BadgeHtml {
    [CmdletBinding()]
    param([Parameter()]$Value, [string]$TrueLabel = 'Enabled', [string]$FalseLabel = 'Disabled')

    if ($Value -eq $true -or $Value -eq 1) {
        return ('<span class="badge badge-pass">{0}</span>' -f $TrueLabel)
    }
    elseif ($Value -eq $false -or $Value -eq 0) {
        return ('<span class="badge badge-fail">{0}</span>' -f $FalseLabel)
    }
    return '<span class="badge badge-na">Unknown</span>'
}

function New-RecommendationHtml {
    [CmdletBinding()]
    param([Parameter()]$Recommendations)
    $items = @($Recommendations)
    if ($items.Count -eq 0) {
        return '<div class="empty-state">No recommendations. This workstation looks healthy.</div>'
    }

    $html = [System.Text.StringBuilder]::new()
    foreach ($rec in $items) {
        $priority    = ConvertTo-HtmlText $rec.Priority
        $category    = ConvertTo-HtmlText $rec.Category
        $problem     = ConvertTo-HtmlText $rec.Problem
        $reason      = ConvertTo-HtmlText $rec.Reason
        $risk        = ConvertTo-HtmlText $rec.Risk
        $fix         = ConvertTo-HtmlText $rec.SuggestedFix
        $improvement = ConvertTo-HtmlText $rec.EstimatedImprovement
        $priorityLow = $priority.ToLowerInvariant()

        [void]$html.Append(@"
<article class="recommendation priority-$priorityLow">
  <div class="rec-head"><span class="badge">$priority</span> <strong>$category</strong></div>
  <h4>$problem</h4>
  <p>$reason</p>
  <dl>
    <dt>Risk</dt><dd>$risk</dd>
    <dt>Suggested fix</dt><dd>$fix</dd>
    <dt>Est. improvement</dt><dd>$improvement</dd>
  </dl>
</article>
"@)
    }
    return $html.ToString()
}

function New-SectionHtml {
    [CmdletBinding()]
    param([string]$Id, [string]$Title, [string]$Body, [string]$Icon = 'square')
    return @"
<section class="dashboard-section">
  <button class="section-toggle" type="button" data-bs-toggle="collapse" data-bs-target="#$Id" aria-expanded="true" aria-controls="$Id">
    <span class="section-title"><i data-lucide="$Icon"></i> $Title</span>
    <i data-lucide="chevron-down"></i>
  </button>
  <div id="$Id" class="collapse show"><div class="section-body">$Body</div></div>
</section>
"@
}

function New-SecurityChecklistHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Security)

    $firewallOk  = @($Security.Firewall | Where-Object { -not $_.Enabled }).Count -eq 0
    $defenderRt  = Get-ObjectPropertyValue -InputObject $Security.Defender -Name 'RealTimeProtectionEnabled' -Default $null
    $tpmReady    = Get-ObjectPropertyValue -InputObject $Security.TPM -Name 'TpmReady' -Default $null
    $bdInstalled = Get-ObjectPropertyValue -InputObject $Security.Bitdefender -Name 'Installed' -Default $false

    return @"
<div class="kv-grid">
  <div><span>Firewall</span><strong>$(New-BadgeHtml $firewallOk 'All Profiles On' 'Profile(s) Off')</strong></div>
  <div><span>Secure Boot</span><strong>$(New-BadgeHtml $Security.SecureBoot)</strong></div>
  <div><span>TPM</span><strong>$(New-BadgeHtml $tpmReady 'Ready' 'Not Ready')</strong></div>
  <div><span>Defender Real-Time</span><strong>$(New-BadgeHtml $defenderRt)</strong></div>
  <div><span>Bitdefender</span><strong>$(New-BadgeHtml $bdInstalled 'Installed' 'Not Found')</strong></div>
  <div><span>UAC</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue $Security.UAC 'Enabled' $null))</strong></div>
  <div><span>Memory Integrity</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue $Security.CoreIsolation 'MemoryIntegrity' $null) 'On' 'Off')</strong></div>
  <div><span>Credential Guard</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue $Security.CredentialGuard 'Enabled' $null))</strong></div>
</div>
"@
}

function New-HtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$ReportData,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$AssetRoot
    )

    $cssPath = Join-Path $AssetRoot 'css\style.css'
    $jsPath  = Join-Path $AssetRoot 'js\dashboard.js'
    $css = if (Test-Path -LiteralPath $cssPath) { Get-Content -Raw -LiteralPath $cssPath } else { '/* style.css not found */' }
    $js  = if (Test-Path -LiteralPath $jsPath)  { Get-Content -Raw -LiteralPath $jsPath }  else { '/* dashboard.js not found */' }
    $reportJson = ($ReportData | ConvertTo-Json -Depth 12 -Compress).Replace('</', '<\/')

    $scores    = $ReportData.Scores
    $generated = ConvertTo-HtmlText $ReportData.Metadata.GeneratedAt
    $computer  = ConvertTo-HtmlText $ReportData.Metadata.ComputerName
    $version   = ConvertTo-HtmlText $ReportData.Metadata.AnalyzerVersion

    # -- Score Cards -------------------------------------------
    $scoreCards = @(
        (New-ScoreCardHtml -Label 'Overall Health'  -Score $scores.Overall           -Icon 'activity'),
        (New-ScoreCardHtml -Label 'Windows'         -Score $scores.Windows            -Icon 'monitor-cog'),
        (New-ScoreCardHtml -Label 'Performance'     -Score $scores.Performance        -Icon 'gauge'),
        (New-ScoreCardHtml -Label 'Storage'         -Score $scores.Storage            -Icon 'hard-drive'),
        (New-ScoreCardHtml -Label 'Security'        -Score $scores.Security           -Icon 'shield-check'),
        (New-ScoreCardHtml -Label 'Battery'         -Score $scores.Battery            -Icon 'battery-charging'),
        (New-ScoreCardHtml -Label 'Developer Env'   -Score $scores.DeveloperEnvironment -Icon 'terminal')
    ) -join "`n"

    # -- System Section ----------------------------------------
    $sys = $ReportData.WindowsHealth.System
    $rebootAlert = ''
    if ($ReportData.WindowsHealth.PendingReboot.Pending) {
        $rebootAlert = '<div class="callout" style="border-left-color:var(--fair)"><strong>Pending reboot detected.</strong> Some updates or services may require a restart.</div>'
    }

    $systemBody = @"
$rebootAlert
<div class="kv-grid">
  <div><span>Computer</span><strong>$(ConvertTo-HtmlText $sys.ComputerModel)</strong></div>
  <div><span>CPU</span><strong>$(ConvertTo-HtmlText $sys.CPU)</strong></div>
  <div><span>RAM</span><strong>$($sys.RAMGB) GB</strong></div>
  <div><span>Motherboard</span><strong>$(ConvertTo-HtmlText $sys.Motherboard)</strong></div>
  <div><span>BIOS</span><strong>$(ConvertTo-HtmlText $sys.BIOS)</strong></div>
  <div><span>Windows</span><strong>$(ConvertTo-HtmlText $sys.WindowsEdition)</strong></div>
  <div><span>Build</span><strong>$(ConvertTo-HtmlText $sys.BuildNumber)</strong></div>
  <div><span>Install Date</span><strong>$(ConvertTo-HtmlText $sys.InstallDate)</strong></div>
  <div><span>Last Boot</span><strong>$(ConvertTo-HtmlText $sys.LastBoot)</strong></div>
  <div><span>Uptime</span><strong>$(ConvertTo-HtmlText $sys.Uptime)</strong></div>
</div>
"@

    # -- Storage Section ---------------------------------------
    $storageBody = @"
<div class="chart-grid">
  <canvas id="storageChart"></canvas>
  <div id="folderTreemap" class="treemap"></div>
</div>
<h3>Drives</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $ReportData.Storage -Name 'Drives') -Id 'drivesTable' -Properties @('Drive','Label','FileSystem','Total','Used','Free','FreePercent') -ShowExport)
<h3>Physical Disks</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $ReportData.Storage -Name 'PhysicalDisks') -Id 'physicalDisksTable' -Properties @('FriendlyName','MediaType','HealthStatus','OperationalStatus','SerialNumber'))
<h3>Largest Folders</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $ReportData.Storage -Name 'LargestFolders') -Id 'foldersTable' -Properties @('Path','SizeGB','FileCount','DirectoryCount') -ShowExport)
<h3>Largest Files</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $ReportData.Storage -Name 'LargestFiles') -Id 'filesTable' -Properties @('Path','SizeMB','Extension','LastModified') -ShowExport)
"@

    # -- Developer Environment Section -------------------------
    $devToolsInstalled = @($ReportData.DeveloperEnvironment.Tools | Where-Object { $_.Installed })
    $devToolsNotFound  = @($ReportData.DeveloperEnvironment.Tools | Where-Object { -not $_.Installed })
    $devFoldersExist   = @($ReportData.DeveloperEnvironment.Folders | Where-Object { $_.Exists })
    $devFoldersTotalGB = 0
    if ($devFoldersExist.Count -gt 0) {
        $devFoldersTotalGB = [math]::Round(($devFoldersExist | Measure-Object -Property SizeGB -Sum).Sum, 2)
    }

    $developerBody = @"
<div class="mini-grid">
  <div><span>Tools Detected</span><strong>$($devToolsInstalled.Count)</strong></div>
  <div><span>Not Found</span><strong>$($devToolsNotFound.Count)</strong></div>
  <div><span>Dev Folders</span><strong>$($devFoldersExist.Count)</strong></div>
  <div><span>Total Dev Size</span><strong>$devFoldersTotalGB GB</strong></div>
</div>
<div class="chart-grid">
  <canvas id="devFoldersChart"></canvas>
  <div>
    <h3>Installed Tools</h3>
    $(New-TableHtml -Items $devToolsInstalled -Id 'toolsInstalledTable' -Properties @('Name','Version','Path','DiskUsage','Detection') -ShowExport)
  </div>
</div>
<h3>Developer Folders</h3>
$(New-TableHtml -Items $devFoldersExist -Id 'devFoldersTable' -Properties @('Name','Category','Path','SizeGB','FileCount') -ShowExport)
<h3>Not Found</h3>
$(New-TableHtml -Items $devToolsNotFound -Id 'toolsNotFoundTable' -Properties @('Name','Detection'))
"@

    # -- Performance Section -----------------------------------
    $perf = $ReportData.Performance
    $cpuDisplay = if ($perf.CPU.LoadPercent) { "$($perf.CPU.LoadPercent)%" } else { 'N/A' }
    $ramDisplay = if ($perf.Memory.UsedPercent) { "$($perf.Memory.UsedPercent)%" } else { 'N/A' }
    $ramTotal   = if ($perf.Memory.TotalGB) { "$($perf.Memory.TotalGB) GB" } else { 'N/A' }

    $performanceBody = @"
<div class="mini-grid">
  <div><span>CPU Usage</span><strong>$cpuDisplay</strong></div>
  <div><span>RAM Used</span><strong>$ramDisplay</strong></div>
  <div><span>Total RAM</span><strong>$ramTotal</strong></div>
  <div><span>Processes</span><strong>$($perf.BackgroundProcessCount)</strong></div>
</div>
<div class="chart-grid">
  <canvas id="processChart"></canvas>
  <canvas id="eventChart"></canvas>
</div>
<h3>Top CPU Processes</h3>
$(New-TableHtml -Items $perf.TopCpuProcesses -Id 'cpuTable' -Properties @('Name','Id','CPU','MemoryMB') -ShowExport)
<h3>Top Memory Processes</h3>
$(New-TableHtml -Items $perf.TopMemoryProcesses -Id 'memoryTable' -Properties @('Name','Id','CPU','MemoryMB') -ShowExport)
<h3>Network Adapters</h3>
$(New-TableHtml -Items $perf.Network.Adapters -Id 'networkTable' -Properties @('Name','InterfaceDescription','Status','LinkSpeed','DriverVersion'))
"@

    if ($perf.Network.VpnAdapters -and @($perf.Network.VpnAdapters).Count -gt 0) {
        $performanceBody += @"

<h3>VPN Adapters</h3>
$(New-TableHtml -Items $perf.Network.VpnAdapters -Id 'vpnTable' -Properties @('Name','InterfaceDescription','Status'))
"@
    }

    # -- Security Section --------------------------------------
    $securityBody = @"
$(New-SecurityChecklistHtml -Security $ReportData.Security)
<div class="chart-grid" style="margin-top:18px">
  <canvas id="securityRadar"></canvas>
  <div>
    <h3>Firewall Profiles</h3>
    $(New-TableHtml -Items $ReportData.Security.Firewall -Id 'firewallTable' -Properties @('Name','Enabled','DefaultInboundAction','DefaultOutboundAction'))
  </div>
</div>
<h3>BitLocker Volumes</h3>
$(New-TableHtml -Items $ReportData.Security.BitLocker -Id 'bitlockerTable' -Properties @('MountPoint','VolumeStatus','ProtectionStatus','EncryptionPercentage','EncryptionMethod'))
"@

    # -- Windows Health Section --------------------------------
    $wuInfo = $ReportData.WindowsHealth.WindowsUpdate
    $windowsHealthBody = @"
<div class="kv-grid">
  <div><span>Pending Reboot</span><strong>$(New-BadgeHtml $ReportData.WindowsHealth.PendingReboot.Pending 'Yes' 'No')</strong></div>
  <div><span>Available Updates</span><strong>$(ConvertTo-HtmlText $wuInfo.AvailableUpdates)</strong></div>
  <div><span>Last Update Check</span><strong>$(ConvertTo-HtmlText $wuInfo.LastSearchSuccessDate)</strong></div>
  <div><span>SFC / DISM</span><strong>$(ConvertTo-HtmlText $ReportData.WindowsHealth.Servicing.Notes)</strong></div>
</div>
"@

    if ($ReportData.WindowsHealth.ReliabilityRecords -and @($ReportData.WindowsHealth.ReliabilityRecords).Count -gt 0) {
        $windowsHealthBody += @"

<h3>Recent Reliability Records</h3>
$(New-TableHtml -Items ($ReportData.WindowsHealth.ReliabilityRecords | Select-Object -First 30) -Id 'reliabilityTable' -Properties @('TimeGenerated','SourceName','ProductName','Message'))
"@
    }

    # -- Battery Section ---------------------------------------
    $batteryBody = ''
    if (Get-ObjectPropertyValue -InputObject $ReportData.Battery -Name 'Present' -Default $false) {
        $batKvHtml = [System.Text.StringBuilder]::new()
        foreach ($bat in $ReportData.Battery.Batteries) {
            $rtDisplay = if ($bat.EstimatedRunTimeMinutes -and $bat.EstimatedRunTimeMinutes -ne 71582788) {
                "$($bat.EstimatedRunTimeMinutes) min"
            } else { 'On AC' }

            [void]$batKvHtml.Append(@"
      <div><span>Name</span><strong>$(ConvertTo-HtmlText $bat.Name)</strong></div>
      <div><span>Charge</span><strong>$($bat.EstimatedChargeRemaining)%</strong></div>
      <div><span>Design Capacity</span><strong>$($bat.DesignCapacity) mWh</strong></div>
      <div><span>Full Charge</span><strong>$($bat.CurrentFullChargeCapacity) mWh</strong></div>
      <div><span>Wear Level</span><strong>$(if ($bat.WearLevelPercent) { "$($bat.WearLevelPercent)%" } else { 'N/A' })</strong></div>
      <div><span>Health</span><strong>$(if ($bat.EstimatedHealthPercent) { "$($bat.EstimatedHealthPercent)%" } else { 'N/A' })</strong></div>
      <div><span>Cycle Count</span><strong>$(if ($bat.CycleCount) { $bat.CycleCount } else { 'N/A' })</strong></div>
      <div><span>Runtime</span><strong>$rtDisplay</strong></div>
"@)
        }

        $batteryBody = @"
<div class="chart-grid">
  <canvas id="batteryChart"></canvas>
  <div>
    <div class="kv-grid">
$($batKvHtml.ToString())
    </div>
  </div>
</div>
"@
    }
    else {
        $batteryBody = '<div class="empty-state">No battery detected -- this appears to be a desktop system.</div>'
    }

    # -- Event Logs Section ------------------------------------
    $evtSummary = $ReportData.EventLogs
    $eventsBody = @"
<div class="mini-grid">
  <div><span>Critical Events</span><strong>$(@($evtSummary.CriticalEvents).Count)</strong></div>
  <div><span>Errors (sample)</span><strong>$(@($evtSummary.ErrorSample).Count)</strong></div>
  <div><span>Shutdowns</span><strong>$(@($evtSummary.UnexpectedShutdowns).Count)</strong></div>
  <div><span>BSODs</span><strong>$(@($evtSummary.BsodHistory).Count)</strong></div>
</div>
<h3>Critical Events</h3>
$(New-TableHtml -Items $evtSummary.CriticalEvents -Id 'criticalEventsTable' -Properties @('TimeCreated','ProviderName','Id','LevelDisplayName','LogName') -ShowExport)
<h3>BSOD History</h3>
$(New-TableHtml -Items $evtSummary.BsodHistory -Id 'bsodTable' -Properties @('TimeCreated','ProviderName','Id','Message'))
<h3>Unexpected Shutdowns</h3>
$(New-TableHtml -Items $evtSummary.UnexpectedShutdowns -Id 'shutdownTable' -Properties @('TimeCreated','ProviderName','Id','LevelDisplayName'))
<h3>Driver Failures</h3>
$(New-TableHtml -Items $evtSummary.DriverFailures -Id 'driverTable' -Properties @('TimeCreated','ProviderName','Id','LevelDisplayName'))
"@

    # -- Startup Section ---------------------------------------
    $bootAvg = if ($ReportData.Startup.BootTimeSecondsAverage) { "$($ReportData.Startup.BootTimeSecondsAverage)s" } else { 'N/A' }

    $startupBody = @"
<div class="mini-grid">
  <div><span>Avg Boot Time</span><strong>$bootAvg</strong></div>
  <div><span>Fast Startup</span><strong>$(New-BadgeHtml $ReportData.Startup.FastStartup.Enabled)</strong></div>
  <div><span>Startup Apps</span><strong>$(@($ReportData.Startup.StartupApplications).Count)</strong></div>
  <div><span>Auto Services</span><strong>$(@($ReportData.Startup.Services).Count)</strong></div>
</div>
<h3>Startup Applications</h3>
$(New-TableHtml -Items $ReportData.Startup.StartupApplications -Id 'startupAppsTable' -Properties @('Name','Location','User','Command') -ShowExport)
<h3>Auto-Start Services</h3>
$(New-TableHtml -Items ($ReportData.Startup.Services | Select-Object -First 60) -Id 'servicesTable' -Properties @('Name','DisplayName','State','StartMode') -ShowExport)
<h3>Scheduled Tasks</h3>
$(New-TableHtml -Items ($ReportData.Startup.ScheduledTasks | Select-Object -First 50) -Id 'tasksTable' -Properties @('TaskName','TaskPath','State','Author'))
"@

    # -- Cleanup Section ---------------------------------------
    $safeItems    = @($ReportData.CleanupAdvisor.Findings | Where-Object { $_.Safety -eq 'Safe to delete' -and $_.Exists -and $_.SizeBytes -gt 0 })
    $reviewItems  = @($ReportData.CleanupAdvisor.Findings | Where-Object { $_.Safety -eq 'Review before deleting' -and $_.Exists -and $_.SizeBytes -gt 0 })
    $neverItems   = @($ReportData.CleanupAdvisor.Findings | Where-Object { $_.Safety -eq 'Never delete' })

    $cleanupBody = @"
<div class="callout">
  <strong>Estimated reclaimable space:</strong> $(ConvertTo-HtmlText $ReportData.CleanupAdvisor.EstimatedReclaimable).
  This tool is read-only and will never delete anything.
</div>
<div class="mini-grid">
  <div><span>Safe to Delete</span><strong>$($safeItems.Count) items</strong></div>
  <div><span>Review First</span><strong>$($reviewItems.Count) items</strong></div>
  <div><span>Protected</span><strong>$($neverItems.Count) items</strong></div>
  <div><span>node_modules Found</span><strong>$(@($ReportData.CleanupAdvisor.DuplicateNodeModules).Count)</strong></div>
</div>
<h3>Safe to Delete</h3>
$(New-TableHtml -Items $safeItems -Id 'cleanupSafeTable' -Properties @('Name','Category','Reclaimable','Path','Reason') -ShowExport)
<h3>Review Before Deleting</h3>
$(New-TableHtml -Items $reviewItems -Id 'cleanupReviewTable' -Properties @('Name','Category','Reclaimable','Path','Reason') -ShowExport)
<h3>Large Archives and Installers</h3>
$(New-TableHtml -Items $ReportData.CleanupAdvisor.LargeArchivesAndInstallers -Id 'archivesTable' -Properties @('FullName','Extension','SizeGB','LastWriteTime'))
<h3>node_modules Directories</h3>
$(New-TableHtml -Items $ReportData.CleanupAdvisor.DuplicateNodeModules -Id 'nodeModulesTable' -Properties @('Path','SizeGB','FileCount'))
"@

    # -- Assemble Sections -------------------------------------
    $sections = @(
        (New-SectionHtml -Id 'systemSection'      -Title 'System Overview'       -Icon 'monitor'        -Body $systemBody),
        (New-SectionHtml -Id 'storageSection'      -Title 'Storage Analysis'      -Icon 'hard-drive'     -Body $storageBody),
        (New-SectionHtml -Id 'developerSection'    -Title 'Developer Environment' -Icon 'terminal'       -Body $developerBody),
        (New-SectionHtml -Id 'performanceSection'  -Title 'Performance and Network' -Icon 'gauge'        -Body $performanceBody),
        (New-SectionHtml -Id 'securitySection'     -Title 'Security'              -Icon 'shield-check'   -Body $securityBody),
        (New-SectionHtml -Id 'windowsSection'      -Title 'Windows Health'        -Icon 'monitor-cog'    -Body $windowsHealthBody),
        (New-SectionHtml -Id 'startupSection'      -Title 'Boot and Startup'      -Icon 'rocket'         -Body $startupBody),
        (New-SectionHtml -Id 'eventsSection'       -Title 'Event Logs'            -Icon 'alert-triangle' -Body $eventsBody),
        (New-SectionHtml -Id 'batterySection'      -Title 'Battery Health'        -Icon 'battery'        -Body $batteryBody),
        (New-SectionHtml -Id 'cleanupSection'      -Title 'Cleanup Advisor'       -Icon 'sparkles'       -Body $cleanupBody),
        (New-SectionHtml -Id 'recsSection'         -Title 'Recommendations'       -Icon 'lightbulb'      -Body (New-RecommendationHtml -Recommendations $ReportData.Recommendations))
    ) -join "`n"

    # -- Final HTML Assembly -----------------------------------
    $html = @"
<!doctype html>
<html lang="en" data-bs-theme="dark">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Developer Health Analyzer Report for $computer">
  <title>Developer Health Analyzer - $computer</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
  <script src="https://unpkg.com/lucide@latest"></script>
  <style>$css</style>
</head>
<body>
  <script id="report-data" type="application/json">$reportJson</script>

  <header class="app-header">
    <div>
      <p class="eyebrow">Read-only Windows Diagnostics - v$version</p>
      <h1>Developer Health Analyzer</h1>
      <p>$computer - Generated $generated</p>
    </div>
    <div style="display:flex;gap:8px">
      <button id="printReport" class="icon-button" type="button" title="Print report"><i data-lucide="printer"></i></button>
      <button id="themeToggle" class="icon-button" type="button" title="Toggle dark/light"><i data-lucide="sun-moon"></i></button>
    </div>
  </header>

  <main class="container-fluid dashboard-shell">
    <section class="score-grid">
$scoreCards
    </section>
$sections
  </main>

  <footer class="app-footer">
    Developer Health Analyzer v$version - No files were modified or deleted - Review recommendations before taking action
  </footer>

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
  <script>$js</script>
</body>
</html>
"@

    # -- Write to disk -----------------------------------------
    $directory = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
    Set-Content -Path $OutputPath -Value $html -Encoding UTF8
}

Export-ModuleMember -Function New-HtmlReport
