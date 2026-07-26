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

function Truncate-Text {
    [CmdletBinding()]
    param([string]$Text, [int]$MaxLength = 200)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if ($Text.Length -le $MaxLength) { return $Text }
    return $Text.Substring(0, $MaxLength) + '...'
}

function New-ScoreCardHtml {
    [CmdletBinding()]
    param([string]$Label, [int]$Score, [string]$Icon)
    $class = if ($Score -ge 85) { 'excellent' } elseif ($Score -ge 70) { 'good' } elseif ($Score -ge 55) { 'warn' } else { 'bad' }
    return @"
<div class="score-card $class" title="85-100: Excellent | 70-84: Good | 55-69: Fair | Below 55: Needs Attention">
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
        [Parameter()][switch]$ShowExport,
        [Parameter()][string]$EmptyStateText = "No data collected."
    )
    $array = @($Items)
    if ($array.Count -eq 0) { return "<p class='muted'>$(ConvertTo-HtmlText $EmptyStateText)</p>" }
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
    <small class="table-count">$($array.Count) items</small>
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
        $priority    = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $rec -Name 'Priority' -Default '')
        $category    = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $rec -Name 'Category' -Default '')
        $problem     = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $rec -Name 'Problem' -Default '')
        $reason      = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $rec -Name 'Reason' -Default '')
        $risk        = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $rec -Name 'Risk' -Default '')
        $fix         = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $rec -Name 'SuggestedFix' -Default '')
        $improvement = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $rec -Name 'EstimatedImprovement' -Default '')
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
    param([string]$Id, [string]$Title, [string]$Body, [string]$Icon = 'square', [int]$RecommendationCount = 0)
    $badge = if ($RecommendationCount -gt 0) { "<span class=`"rec-count-badge`">$RecommendationCount issues</span>" } else { "" }
    return @"
<section class="dashboard-section">
  <button class="section-toggle" type="button" data-bs-toggle="collapse" data-bs-target="#$Id" aria-expanded="true" aria-controls="$Id">
    <span class="section-title"><i data-lucide="$Icon"></i> $Title $badge</span>
    <i data-lucide="chevron-down"></i>
  </button>
  <div id="$Id" class="collapse show"><div class="section-body">$Body</div></div>
</section>
"@
}

function New-SecurityChecklistHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Security)

    $firewallOk  = @((Get-ObjectPropertyValue -InputObject $Security -Name 'Firewall' -Default @()) | Where-Object { -not (Get-ObjectPropertyValue -InputObject $_ -Name 'Enabled' -Default $false) }).Count -eq 0
    $defenderRt  = Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $Security -Name 'Defender') -Name 'RealTimeProtectionEnabled' -Default $null
    $tpmReady    = Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $Security -Name 'TPM') -Name 'TpmReady' -Default $null
    $bdInstalled = Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $Security -Name 'Bitdefender') -Name 'Installed' -Default $false

    return @"
<div class="kv-grid">
  <div><span>Firewall</span><strong>$(New-BadgeHtml $firewallOk 'All Profiles On' 'Profile(s) Off')</strong></div>
  <div><span>Secure Boot</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject $Security -Name 'SecureBoot'))</strong></div>
  <div><span>TPM</span><strong>$(New-BadgeHtml $tpmReady 'Ready' 'Not Ready')</strong></div>
  <div><span>Defender Real-Time</span><strong>$(New-BadgeHtml $defenderRt)</strong></div>
  <div><span>Bitdefender</span><strong>$(New-BadgeHtml $bdInstalled 'Installed' 'Not Found')</strong></div>
  <div><span>UAC</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $Security -Name 'UAC') -Name 'Enabled' -Default $null))</strong></div>
  <div><span>Memory Integrity</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $Security -Name 'CoreIsolation') -Name 'MemoryIntegrity' -Default $null) 'On' 'Off')</strong></div>
  <div><span>Credential Guard</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $Security -Name 'CredentialGuard') -Name 'Enabled' -Default $null))</strong></div>
</div>
"@
}

function Get-CategoryRecCount {
    param([Parameter()]$Recommendations, [string]$Category)
    return @($Recommendations | Where-Object { (Get-ObjectPropertyValue -InputObject $_ -Name 'Category' -Default '') -eq $Category }).Count
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
    $css = if (Test-Path -LiteralPath $cssPath) { Get-Content -Raw -LiteralPath $cssPath -Encoding UTF8 } else { '/* style.css not found */' }
    $js  = if (Test-Path -LiteralPath $jsPath)  { Get-Content -Raw -LiteralPath $jsPath -Encoding UTF8 }  else { '/* dashboard.js not found */' }
    $reportJson = ($ReportData | ConvertTo-Json -Depth 12 -Compress).Replace('</', '<\/')

    $scores    = Get-ObjectPropertyValue -InputObject $ReportData -Name 'Scores'
    $metadata  = Get-ObjectPropertyValue -InputObject $ReportData -Name 'Metadata'
    $generated = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $metadata -Name 'GeneratedAt')
    $computer  = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $metadata -Name 'ComputerName')
    $version   = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $metadata -Name 'AnalyzerVersion')
    $scanDuration = Get-ObjectPropertyValue -InputObject $metadata -Name 'ScanDurationSeconds' -Default 0

    $recs = Get-ObjectPropertyValue -InputObject $ReportData -Name 'Recommendations' -Default @()
    $totalRecs = @($recs).Count

    $scoreProps = @('Overall', 'Windows', 'Performance', 'Storage', 'Security', 'Battery', 'DeveloperEnvironment', 'EventLogs', 'Startup')
    $weakestScore = 100
    $weakestArea = 'None'
    foreach ($p in $scoreProps) {
        if ($p -eq 'Overall') { continue }
        $s = Get-ObjectPropertyValue -InputObject $scores -Name $p -Default 100
        if ($s -lt $weakestScore) {
            $weakestScore = $s
            $weakestArea = $p
        }
    }

    # -- Executive Summary -------------------------------------
    $overallScore = Get-ObjectPropertyValue -InputObject $scores -Name 'Overall' -Default 0
    $highPriorityRecs = @($recs | Where-Object { (Get-ObjectPropertyValue -InputObject $_ -Name 'Priority') -eq 'High' }).Count
    $execSummaryHtml = @"
<div class="executive-summary callout">
  <h2>Executive Summary</h2>
  <p>Your system scored <strong>$overallScore/100</strong>. $highPriorityRecs high-priority issues were found. $(ConvertTo-HtmlText $weakestArea) is your lowest-scoring area at $weakestScore/100.</p>
  <p>Scan completed in ${scanDuration}s on $(ConvertTo-HtmlText $generated). This report is read-only -- no files were modified.</p>
</div>
"@

    # -- Score Cards -------------------------------------------
    # 9 score cards
    $scoreCards = @(
        (New-ScoreCardHtml -Label 'Overall Health'  -Score $overallScore -Icon 'activity'),
        (New-ScoreCardHtml -Label 'Windows'         -Score (Get-ObjectPropertyValue -InputObject $scores -Name 'Windows' -Default 0) -Icon 'monitor-cog'),
        (New-ScoreCardHtml -Label 'Performance'     -Score (Get-ObjectPropertyValue -InputObject $scores -Name 'Performance' -Default 0) -Icon 'gauge'),
        (New-ScoreCardHtml -Label 'Storage'         -Score (Get-ObjectPropertyValue -InputObject $scores -Name 'Storage' -Default 0) -Icon 'hard-drive'),
        (New-ScoreCardHtml -Label 'Security'        -Score (Get-ObjectPropertyValue -InputObject $scores -Name 'Security' -Default 0) -Icon 'shield-check'),
        (New-ScoreCardHtml -Label 'Battery'         -Score (Get-ObjectPropertyValue -InputObject $scores -Name 'Battery' -Default 0) -Icon 'battery-charging'),
        (New-ScoreCardHtml -Label 'Developer Env'   -Score (Get-ObjectPropertyValue -InputObject $scores -Name 'DeveloperEnvironment' -Default 0) -Icon 'terminal'),
        (New-ScoreCardHtml -Label 'Event Logs'      -Score (Get-ObjectPropertyValue -InputObject $scores -Name 'EventLogs' -Default 0) -Icon 'alert-triangle'),
        (New-ScoreCardHtml -Label 'Startup'         -Score (Get-ObjectPropertyValue -InputObject $scores -Name 'Startup' -Default 0) -Icon 'rocket')
    ) -join "`n"

    # -- System Section ----------------------------------------
    $windowsHealth = Get-ObjectPropertyValue -InputObject $ReportData -Name 'WindowsHealth'
    $sys = Get-ObjectPropertyValue -InputObject $windowsHealth -Name 'System'
    $rebootAlert = ''
    $pendingReboot = Get-ObjectPropertyValue -InputObject $windowsHealth -Name 'PendingReboot'
    if (Get-ObjectPropertyValue -InputObject $pendingReboot -Name 'Pending' -Default $false) {
        $rebootAlert = '<div class="callout" style="border-left-color:var(--fair)"><strong>Pending reboot detected.</strong> Some updates or services may require a restart.</div>'
    }

    $systemBody = @"
$rebootAlert
<div class="kv-grid">
  <div><span>Computer</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'ComputerModel'))</strong></div>
  <div><span>CPU</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'CPU'))</strong></div>
  <div><span>RAM</span><strong>$(Get-ObjectPropertyValue -InputObject $sys -Name 'RAMGB') GB</strong></div>
  <div><span>Motherboard</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'Motherboard'))</strong></div>
  <div><span>BIOS</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'BIOS'))</strong></div>
  <div><span>Windows</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'WindowsEdition'))</strong></div>
  <div><span>Build</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'BuildNumber'))</strong></div>
  <div><span>Install Date</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'InstallDate'))</strong></div>
  <div><span>Last Boot</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'LastBoot'))</strong></div>
  <div><span>Uptime</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'Uptime'))</strong></div>
  <div><span>Display Version</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'DisplayVersion'))</strong></div>
  <div><span>Architecture</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'Architecture'))</strong></div>
  <div><span>Serial Number</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'SerialNumber'))</strong></div>
  <div><span>CPU Cores</span><strong>$(Get-ObjectPropertyValue -InputObject $sys -Name 'CPUCores') cores / $(Get-ObjectPropertyValue -InputObject $sys -Name 'CPULogicalProcessors') threads</strong></div>
  <div><span>BIOS Date</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $sys -Name 'BIOSDate'))</strong></div>
</div>
"@

    # -- Storage Section ---------------------------------------
    $storage = Get-ObjectPropertyValue -InputObject $ReportData -Name 'Storage'
    
    $rb = Get-ObjectPropertyValue -InputObject $storage -Name 'RecycleBin'
    $rbCount = Get-ObjectPropertyValue -InputObject $rb -Name 'ItemCount' -Default 0
    $rbSize = Get-ObjectPropertyValue -InputObject $rb -Name 'SizeMB' -Default 0
    $recycleBinHtml = if ($rbCount -gt 0) { "<div class=`"callout`"><strong>Recycle Bin:</strong> $rbCount items ($rbSize MB)</div>" } else { "" }

    $nvme = @(Get-ObjectPropertyValue -InputObject $storage -Name 'Nvme' -Default @())
    $nvmeHtml = if ($nvme.Count -gt 0) { 
        "<div class=`"callout`"><strong>NVMe Drives Detected:</strong> $(ConvertTo-HtmlText ($nvme.Model -join ', '))</div>" 
    } else { "" }

    $folderThresholds = Get-ObjectPropertyValue -InputObject $storage -Name 'FolderThresholds'
    $folderThresholdsHtml = if ($folderThresholds) {
        @"
<div class="mini-grid" style="margin-top:10px">
  <div><span>Folders > 500MB</span><strong>$(Get-ObjectPropertyValue -InputObject $folderThresholds -Name 'GreaterThan500MB' -Default 0)</strong></div>
  <div><span>Folders > 1GB</span><strong>$(Get-ObjectPropertyValue -InputObject $folderThresholds -Name 'GreaterThan1GB' -Default 0)</strong></div>
  <div><span>Folders > 5GB</span><strong>$(Get-ObjectPropertyValue -InputObject $folderThresholds -Name 'GreaterThan5GB' -Default 0)</strong></div>
  <div><span>Folders > 10GB</span><strong>$(Get-ObjectPropertyValue -InputObject $folderThresholds -Name 'GreaterThan10GB' -Default 0)</strong></div>
  <div><span>Folders > 20GB</span><strong>$(Get-ObjectPropertyValue -InputObject $folderThresholds -Name 'GreaterThan20GB' -Default 0)</strong></div>
</div>
"@
    } else { "" }

    $storageBody = @"
$recycleBinHtml
$nvmeHtml
<div class="chart-grid">
  <canvas id="storageChart"></canvas>
  <div id="folderTreemap" class="treemap"></div>
</div>
<div class="chart-grid" style="margin-top:10px;">
  <canvas id="storageCategoryChart"></canvas>
  <div></div>
</div>
<h3>Drives</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $storage -Name 'Drives') -Id 'drivesTable' -Properties @('Drive','Label','FileSystem','Total','Used','Free','FreePercent') -ShowExport)
<h3>Physical Disks</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $storage -Name 'PhysicalDisks') -Id 'physicalDisksTable' -Properties @('FriendlyName','MediaType','HealthStatus','OperationalStatus','SerialNumber'))
<h3>SMART / Disk Health</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $storage -Name 'SmartData') -Id 'smartTable' -Properties @('DiskNumber','Model','HealthStatus','Temperature','WearLevel','PowerOnHours','MediaErrors'))
$folderThresholdsHtml
<h3>Largest Folders</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $storage -Name 'LargestFolders') -Id 'foldersTable' -Properties @('Path','SizeGB','FileCount','DirectoryCount') -ShowExport)
<h3>Largest Files</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $storage -Name 'LargestFiles') -Id 'filesTable' -Properties @('Path','SizeMB','Extension','LastModified') -ShowExport)
"@

    # -- Developer Environment Section -------------------------
    $devEnv = Get-ObjectPropertyValue -InputObject $ReportData -Name 'DeveloperEnvironment'
    $devTools = Get-ObjectPropertyValue -InputObject $devEnv -Name 'Tools' -Default @()
    $devToolsInstalled = @($devTools | Where-Object { Get-ObjectPropertyValue -InputObject $_ -Name 'Installed' })
    $devToolsNotFound  = @($devTools | Where-Object { -not (Get-ObjectPropertyValue -InputObject $_ -Name 'Installed') })
    $devFolders = Get-ObjectPropertyValue -InputObject $devEnv -Name 'Folders' -Default @()
    $devFoldersExist   = @($devFolders | Where-Object { Get-ObjectPropertyValue -InputObject $_ -Name 'Exists' })
    
    $devFoldersTotalGB = 0
    if ($devFoldersExist.Count -gt 0) {
        $devFoldersTotalGB = [math]::Round((($devFoldersExist | Measure-Object -Property SizeGB -Sum).Sum), 2)
    }

    $notFoundNames = @($devToolsNotFound | ForEach-Object { ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $_ -Name 'Name') }) -join ', '
    
    $wsl = @(Get-ObjectPropertyValue -InputObject $devEnv -Name 'WSL' -Default @())
    $wslHtml = if ($wsl.Count -gt 0) {
        "<h3>WSL Distributions</h3>`n" + (New-TableHtml -Items $wsl -Id 'wslTable' -Properties @('Name','State','Version'))
    } else { "" }

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
<details style="margin-top:15px;margin-bottom:15px;">
  <summary><strong>Tools Not Found ($($devToolsNotFound.Count))</strong></summary>
  <div style="padding:10px;background:rgba(0,0,0,0.1);border-radius:4px;">$notFoundNames</div>
</details>
$wslHtml
"@

    # -- Performance Section -----------------------------------
    $perf = Get-ObjectPropertyValue -InputObject $ReportData -Name 'Performance'
    $perfCpu = Get-ObjectPropertyValue -InputObject $perf -Name 'CPU'
    $perfMem = Get-ObjectPropertyValue -InputObject $perf -Name 'Memory'
    $cpuDisplay = if (Get-ObjectPropertyValue -InputObject $perfCpu -Name 'LoadPercent') { "$(Get-ObjectPropertyValue -InputObject $perfCpu -Name 'LoadPercent')%" } else { 'N/A' }
    $ramDisplay = if (Get-ObjectPropertyValue -InputObject $perfMem -Name 'UsedPercent') { "$(Get-ObjectPropertyValue -InputObject $perfMem -Name 'UsedPercent')%" } else { 'N/A' }
    $ramTotal   = if (Get-ObjectPropertyValue -InputObject $perfMem -Name 'TotalGB') { "$(Get-ObjectPropertyValue -InputObject $perfMem -Name 'TotalGB') GB" } else { 'N/A' }
    $perfNetwork = Get-ObjectPropertyValue -InputObject $perf -Name 'Network'
    $proxy = Get-ObjectPropertyValue -InputObject $perfNetwork -Name 'Proxy'
    $proxyHtml = if ($proxy -and (Get-ObjectPropertyValue -InputObject $proxy -Name 'Enabled')) {
        "<div class=`"callout`"><strong>Proxy Enabled:</strong> $(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $proxy -Name 'Server'))</div>"
    } else { "" }

    $performanceBody = @"
$proxyHtml
<div class="mini-grid">
  <div><span>CPU Usage</span><strong>$cpuDisplay</strong></div>
  <div><span>RAM Used</span><strong>$ramDisplay</strong></div>
  <div><span>Total RAM</span><strong>$ramTotal</strong></div>
  <div><span>Processes</span><strong>$(Get-ObjectPropertyValue -InputObject $perf -Name 'BackgroundProcessCount')</strong></div>
</div>
<div class="chart-grid">
  <canvas id="processChart"></canvas>
  <canvas id="eventChart"></canvas>
</div>
<div class="chart-grid" style="margin-top:10px;">
  <canvas id="diskIoChart"></canvas>
  <div></div>
</div>
<h3>Disk I/O Activity</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $perf -Name 'DiskActivity') -Id 'diskActivityTable' -Properties @('Disk','ReadSpeed','WriteSpeed','AvgQueueLength','PercentDiskTime') -ShowExport)
<h3>Top CPU Processes</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $perf -Name 'TopCpuProcesses') -Id 'cpuTable' -Properties @('Name','Id','CPU','MemoryMB') -ShowExport)
<h3>Top Memory Processes</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $perf -Name 'TopMemoryProcesses') -Id 'memoryTable' -Properties @('Name','Id','CPU','MemoryMB') -ShowExport)
<h3>Page File</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $perf -Name 'PageFile') -Id 'pageFileTable' -Properties @('Name','AllocatedBaseSize','CurrentUsage','PeakUsage'))
<h3>Network Adapters</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $perfNetwork -Name 'Adapters') -Id 'networkTable' -Properties @('Name','InterfaceDescription','Status','LinkSpeed','DriverVersion'))
<h3>DNS Servers</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $perfNetwork -Name 'Dns') -Id 'dnsTable' -Properties @('InterfaceAlias','Servers'))
"@

    $vpnAdapters = @(Get-ObjectPropertyValue -InputObject $perfNetwork -Name 'VpnAdapters' -Default @())
    if ($vpnAdapters.Count -gt 0) {
        $performanceBody += @"

<h3>VPN Adapters</h3>
$(New-TableHtml -Items $vpnAdapters -Id 'vpnTable' -Properties @('Name','InterfaceDescription','Status'))
"@
    }

    # -- Security Section --------------------------------------
    $security = Get-ObjectPropertyValue -InputObject $ReportData -Name 'Security'
    
    $defender = Get-ObjectPropertyValue -InputObject $security -Name 'Defender'
    $defenderHtml = if ($defender) {
        @"
<div class="kv-grid" style="margin-top:15px">
  <div><span>Antivirus Signature</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $defender -Name 'AntivirusSignatureLastUpdated'))</strong></div>
  <div><span>Quick Scan Age</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $defender -Name 'QuickScanAge'))</strong></div>
  <div><span>Full Scan Age</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $defender -Name 'FullScanAge'))</strong></div>
  <div><span>Behavior Monitor</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject $defender -Name 'BehaviorMonitorEnabled'))</strong></div>
  <div><span>IOAV Protection</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject $defender -Name 'IoavProtectionEnabled'))</strong></div>
</div>
"@
    } else { "" }

    $tpm = Get-ObjectPropertyValue -InputObject $security -Name 'TPM'
    $tpmHtml = if ($tpm) {
        @"
<div class="kv-grid" style="margin-top:15px">
  <div><span>TPM Ready</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject $tpm -Name 'TpmReady'))</strong></div>
  <div><span>TPM Version</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $tpm -Name 'ManufacturerVersion'))</strong></div>
</div>
"@
    } else { "" }

    $vbs = Get-ObjectPropertyValue -InputObject $security -Name 'VBS'
    $cg = Get-ObjectPropertyValue -InputObject $security -Name 'CredentialGuard'
    $vbsHtml = if ($vbs -or $cg) {
        @"
<div class="kv-grid" style="margin-top:15px">
  <div><span>VBS Enabled</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject $vbs -Name 'Enabled'))</strong></div>
  <div><span>Cred Guard Enabled</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject $cg -Name 'Enabled'))</strong></div>
  <div><span>Cred Guard Config</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $cg -Name 'ConfigurationStatus'))</strong></div>
  <div><span>Cred Guard Running</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $cg -Name 'RunningStatus'))</strong></div>
</div>
"@
    } else { "" }

    $bitdefender = Get-ObjectPropertyValue -InputObject $security -Name 'Bitdefender'
    $bdServices = @(Get-ObjectPropertyValue -InputObject $bitdefender -Name 'Services' -Default @())
    $bdHtml = if ($bdServices.Count -gt 0) {
        "<h3>Bitdefender Services</h3>`n" + (New-TableHtml -Items $bdServices -Id 'bdServicesTable' -Properties @('Name','DisplayName','State'))
    } else { "" }

    $securityBody = @"
$(New-SecurityChecklistHtml -Security $security)
$defenderHtml
$tpmHtml
$vbsHtml
<div class="chart-grid" style="margin-top:18px">
  <canvas id="securityRadar"></canvas>
  <div>
    <h3>Firewall Profiles</h3>
    $(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $security -Name 'Firewall') -Id 'firewallTable' -Properties @('Name','Enabled','DefaultInboundAction','DefaultOutboundAction'))
  </div>
</div>
<h3>BitLocker Volumes</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $security -Name 'BitLocker') -Id 'bitlockerTable' -Properties @('MountPoint','VolumeStatus','ProtectionStatus','EncryptionPercentage','EncryptionMethod'))
$bdHtml
"@

    # -- Windows Health Section --------------------------------
    $wuInfo = Get-ObjectPropertyValue -InputObject $windowsHealth -Name 'WindowsUpdate'
    $servicing = Get-ObjectPropertyValue -InputObject $windowsHealth -Name 'Servicing'
    
    $sfcResult = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $servicing -Name 'SFC.Result')
    $sfcLastRun = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $servicing -Name 'SFC.LastRun')
    $dismResult = ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $servicing -Name 'DISM.Result')
    
    $windowsHealthBody = @"
<div class="kv-grid">
  <div><span>Pending Reboot</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $windowsHealth -Name 'PendingReboot') -Name 'Pending') 'Yes' 'No')</strong></div>
  <div><span>Available Updates</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $wuInfo -Name 'AvailableUpdates'))</strong></div>
  <div><span>Last Update Check</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $wuInfo -Name 'LastSearchSuccessDate'))</strong></div>
  <div><span>SFC Result</span><strong>$sfcResult</strong></div>
  <div><span>SFC Last Run</span><strong>$sfcLastRun</strong></div>
  <div><span>DISM Result</span><strong>$dismResult</strong></div>
</div>
<h3>Recent Hotfixes</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $wuInfo -Name 'RecentUpdates') -Id 'hotfixesTable' -Properties @('HotFixID','Description','InstalledBy','InstalledOn'))
"@

    $relRecords = @(Get-ObjectPropertyValue -InputObject $windowsHealth -Name 'ReliabilityRecords' -Default @())
    if ($relRecords.Count -gt 0) {
        $windowsHealthBody += @"

<h3>Recent Reliability Records</h3>
$(New-TableHtml -Items ($relRecords | Select-Object -First 30) -Id 'reliabilityTable' -Properties @('TimeGenerated','SourceName','ProductName','Message'))
"@
    }

    # -- Battery Section ---------------------------------------
    $battery = Get-ObjectPropertyValue -InputObject $ReportData -Name 'Battery'
    $batteryBody = ''
    if (Get-ObjectPropertyValue -InputObject $battery -Name 'Present' -Default $false) {
        $batKvHtml = [System.Text.StringBuilder]::new()
        foreach ($bat in (Get-ObjectPropertyValue -InputObject $battery -Name 'Batteries')) {
            $ert = Get-ObjectPropertyValue -InputObject $bat -Name 'EstimatedRunTimeMinutes'
            $rtDisplay = if ($ert -and $ert -ne 71582788) {
                "$ert min"
            } else { 'On AC' }

            $wl = Get-ObjectPropertyValue -InputObject $bat -Name 'WearLevelPercent'
            $eh = Get-ObjectPropertyValue -InputObject $bat -Name 'EstimatedHealthPercent'
            $cc = Get-ObjectPropertyValue -InputObject $bat -Name 'CycleCount'
            
            [void]$batKvHtml.Append(@"
      <div><span>Name</span><strong>$(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $bat -Name 'Name'))</strong></div>
      <div><span>Charge</span><strong>$(Get-ObjectPropertyValue -InputObject $bat -Name 'EstimatedChargeRemaining')%</strong></div>
      <div><span>Design Capacity</span><strong>$(Get-ObjectPropertyValue -InputObject $bat -Name 'DesignCapacity') mWh</strong></div>
      <div><span>Full Charge</span><strong>$(Get-ObjectPropertyValue -InputObject $bat -Name 'CurrentFullChargeCapacity') mWh</strong></div>
      <div><span>Wear Level</span><strong>$(if ($wl) { "$wl%" } else { 'N/A' })</strong></div>
      <div><span>Health</span><strong>$(if ($eh) { "$eh%" } else { 'N/A' })</strong></div>
      <div><span>Cycle Count</span><strong>$(if ($cc) { $cc } else { 'N/A' })</strong></div>
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
<div class="chart-grid" style="margin-top:10px;">
  <canvas id="chargingHistoryChart"></canvas>
  <div></div>
</div>
"@
    }
    else {
        $batteryBody = '<div class="empty-state">No battery detected -- this appears to be a desktop system.</div>'
    }

    # -- Event Logs Section ------------------------------------
    $evtSummary = Get-ObjectPropertyValue -InputObject $ReportData -Name 'EventLogs'
    
    $critEvents = @(Get-ObjectPropertyValue -InputObject $evtSummary -Name 'CriticalEvents' -Default @())
    $bsods = @(Get-ObjectPropertyValue -InputObject $evtSummary -Name 'BsodHistory' -Default @())
    $shutdowns = @(Get-ObjectPropertyValue -InputObject $evtSummary -Name 'UnexpectedShutdowns' -Default @())
    $driverFails = @(Get-ObjectPropertyValue -InputObject $evtSummary -Name 'DriverFailures' -Default @())
    
    foreach ($arr in @($critEvents, $bsods, $shutdowns, $driverFails)) {
        foreach ($e in $arr) {
            $msg = Get-ObjectPropertyValue -InputObject $e -Name 'Message' -Default ''
            $e | Add-Member -MemberType NoteProperty -Name 'Message_Truncated' -Value (Truncate-Text $msg 200) -Force
        }
    }

    $eventsBody = @"
<div class="mini-grid">
  <div><span>Critical Events</span><strong>$($critEvents.Count)</strong></div>
  <div><span>Errors (sample)</span><strong>$(@(Get-ObjectPropertyValue -InputObject $evtSummary -Name 'ErrorSample' -Default @()).Count)</strong></div>
  <div><span>Shutdowns</span><strong>$($shutdowns.Count)</strong></div>
  <div><span>BSODs</span><strong>$($bsods.Count)</strong></div>
</div>
<h3>Critical Events</h3>
$(New-TableHtml -Items $critEvents -Id 'criticalEventsTable' -Properties @('TimeCreated','ProviderName','Id','LevelDisplayName','LogName') -ShowExport)
<h3>BSOD History</h3>
$(New-TableHtml -Items $bsods -Id 'bsodTable' -Properties @('TimeCreated','ProviderName','Id','Message_Truncated') -EmptyStateText "No BSOD events recorded -- system appears stable.")
<h3>Unexpected Shutdowns</h3>
$(New-TableHtml -Items $shutdowns -Id 'shutdownTable' -Properties @('TimeCreated','ProviderName','Id','LevelDisplayName'))
<h3>Driver Failures</h3>
$(New-TableHtml -Items $driverFails -Id 'driverTable' -Properties @('TimeCreated','ProviderName','Id','LevelDisplayName') -EmptyStateText "No driver failure events found.")
"@

    # -- Startup Section ---------------------------------------
    $startup = Get-ObjectPropertyValue -InputObject $ReportData -Name 'Startup'
    $bootAvgVal = Get-ObjectPropertyValue -InputObject $startup -Name 'BootTimeSecondsAverage'
    $bootAvg = if ($bootAvgVal) { "${bootAvgVal}s" } else { 'N/A' }

    $startupBody = @"
<div class="mini-grid">
  <div><span>Avg Boot Time</span><strong>$bootAvg</strong></div>
  <div><span>Fast Startup</span><strong>$(New-BadgeHtml (Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $startup -Name 'FastStartup') -Name 'Enabled'))</strong></div>
  <div><span>Startup Apps</span><strong>$(@(Get-ObjectPropertyValue -InputObject $startup -Name 'StartupApplications' -Default @()).Count)</strong></div>
  <div><span>Auto Services</span><strong>$(@(Get-ObjectPropertyValue -InputObject $startup -Name 'Services' -Default @()).Count)</strong></div>
</div>
<div class="chart-grid">
  <canvas id="bootTimeChart"></canvas>
  <div></div>
</div>
<h3>Boot Performance</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $startup -Name 'BootEvents') -Id 'bootEventsTable' -Properties @('TimeCreated','BootDurationSeconds'))
<h3>Startup Applications</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $startup -Name 'StartupApplications') -Id 'startupAppsTable' -Properties @('Name','Location','User','Command') -ShowExport)
<h3>Auto-Start Services</h3>
$(New-TableHtml -Items ((Get-ObjectPropertyValue -InputObject $startup -Name 'Services') | Select-Object -First 60) -Id 'servicesTable' -Properties @('Name','DisplayName','State','StartMode') -ShowExport)
<h3>Scheduled Tasks</h3>
$(New-TableHtml -Items ((Get-ObjectPropertyValue -InputObject $startup -Name 'ScheduledTasks') | Select-Object -First 50) -Id 'tasksTable' -Properties @('TaskName','TaskPath','State','Author'))
"@

    # -- Cleanup Section ---------------------------------------
    $cleanupAdvisor = Get-ObjectPropertyValue -InputObject $ReportData -Name 'CleanupAdvisor'
    $findings = Get-ObjectPropertyValue -InputObject $cleanupAdvisor -Name 'Findings' -Default @()
    $safeItems    = @($findings | Where-Object { (Get-ObjectPropertyValue -InputObject $_ -Name 'Safety') -eq 'Safe to delete' -and (Get-ObjectPropertyValue -InputObject $_ -Name 'Exists') -and (Get-ObjectPropertyValue -InputObject $_ -Name 'SizeBytes') -gt 0 })
    $reviewItems  = @($findings | Where-Object { (Get-ObjectPropertyValue -InputObject $_ -Name 'Safety') -eq 'Review before deleting' -and (Get-ObjectPropertyValue -InputObject $_ -Name 'Exists') -and (Get-ObjectPropertyValue -InputObject $_ -Name 'SizeBytes') -gt 0 })
    $neverItems   = @($findings | Where-Object { (Get-ObjectPropertyValue -InputObject $_ -Name 'Safety') -eq 'Never delete' })

    $catTotalsHtml = [System.Text.StringBuilder]::new()
    $catCounts = @{}
    foreach ($f in $findings) {
        $c = Get-ObjectPropertyValue -InputObject $f -Name 'Category' -Default 'Unknown'
        if (-not $catCounts.Contains($c)) { $catCounts[$c] = 0 }
        $catCounts[$c]++
    }
    foreach ($k in $catCounts.Keys) {
        [void]$catTotalsHtml.Append("<div><span>$k</span><strong>$($catCounts[$k]) items</strong></div>")
    }

    $cleanupBody = @"
<div class="callout">
  <strong>Estimated reclaimable space:</strong> $(ConvertTo-HtmlText (Get-ObjectPropertyValue -InputObject $cleanupAdvisor -Name 'EstimatedReclaimable')).
  This tool is read-only and will never delete anything.
</div>
<div class="mini-grid">
  <div><span>Safe to Delete</span><strong>$($safeItems.Count) items</strong></div>
  <div><span>Review First</span><strong>$($reviewItems.Count) items</strong></div>
  <div><span>Protected</span><strong>$($neverItems.Count) items</strong></div>
  <div><span>node_modules Found</span><strong>$(@(Get-ObjectPropertyValue -InputObject $cleanupAdvisor -Name 'DuplicateNodeModules' -Default @()).Count)</strong></div>
$($catTotalsHtml.ToString())
</div>
<div class="chart-grid" style="margin-top:10px;">
  <canvas id="cleanupCategoryChart"></canvas>
  <div></div>
</div>
<h3>Safe to Delete</h3>
$(New-TableHtml -Items $safeItems -Id 'cleanupSafeTable' -Properties @('Name','Category','Reclaimable','Path','Reason') -ShowExport)
<h3>Review Before Deleting</h3>
$(New-TableHtml -Items $reviewItems -Id 'cleanupReviewTable' -Properties @('Name','Category','Reclaimable','Path','Reason') -ShowExport)
<h3>Large Archives and Installers</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $cleanupAdvisor -Name 'LargeArchivesAndInstallers') -Id 'archivesTable' -Properties @('FullName','Extension','SizeGB','LastWriteTime'))
<h3>node_modules Directories</h3>
$(New-TableHtml -Items (Get-ObjectPropertyValue -InputObject $cleanupAdvisor -Name 'DuplicateNodeModules') -Id 'nodeModulesTable' -Properties @('Path','SizeGB','FileCount'))
"@

    # -- Assemble Sections -------------------------------------
    $sections = @(
        (New-SectionHtml -Id 'systemSection'      -Title 'System Overview'       -Icon 'monitor'        -Body $systemBody),
        (New-SectionHtml -Id 'storageSection'      -Title 'Storage Analysis'      -Icon 'hard-drive'     -Body $storageBody -RecommendationCount (Get-CategoryRecCount $recs 'Storage')),
        (New-SectionHtml -Id 'developerSection'    -Title 'Developer Environment' -Icon 'terminal'       -Body $developerBody -RecommendationCount (Get-CategoryRecCount $recs 'Developer')),
        (New-SectionHtml -Id 'performanceSection'  -Title 'Performance and Network' -Icon 'gauge'        -Body $performanceBody -RecommendationCount (Get-CategoryRecCount $recs 'Performance')),
        (New-SectionHtml -Id 'securitySection'     -Title 'Security'              -Icon 'shield-check'   -Body $securityBody -RecommendationCount (Get-CategoryRecCount $recs 'Security')),
        (New-SectionHtml -Id 'windowsSection'      -Title 'Windows Health'        -Icon 'monitor-cog'    -Body $windowsHealthBody -RecommendationCount (Get-CategoryRecCount $recs 'Windows')),
        (New-SectionHtml -Id 'startupSection'      -Title 'Boot and Startup'      -Icon 'rocket'         -Body $startupBody -RecommendationCount (Get-CategoryRecCount $recs 'Startup')),
        (New-SectionHtml -Id 'eventsSection'       -Title 'Event Logs'            -Icon 'alert-triangle' -Body $eventsBody),
        (New-SectionHtml -Id 'batterySection'      -Title 'Battery Health'        -Icon 'battery'        -Body $batteryBody -RecommendationCount (Get-CategoryRecCount $recs 'Battery')),
        (New-SectionHtml -Id 'cleanupSection'      -Title 'Cleanup Advisor'       -Icon 'sparkles'       -Body $cleanupBody -RecommendationCount (Get-CategoryRecCount $recs 'Cleanup')),
        (New-SectionHtml -Id 'recsSection'         -Title 'Recommendations'       -Icon 'lightbulb'      -Body (New-RecommendationHtml -Recommendations $recs))
    ) -join "`n"

    $overallRecCount = $totalRecs

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
  <script src="https://unpkg.com/lucide@0.263.1"></script>
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
      <button id="toggleAllSections" class="icon-button" type="button" title="Expand/Collapse all"><i data-lucide="layers"></i></button>
      <button id="printReport" class="icon-button" type="button" title="Print report"><i data-lucide="printer"></i></button>
      <button id="themeToggle" class="icon-button" type="button" title="Toggle dark/light"><i data-lucide="sun-moon"></i></button>
    </div>
  </header>

  <main class="container-fluid dashboard-shell">
    $execSummaryHtml
    <section class="score-grid">
      <!-- 9 score cards -->
$scoreCards
    </section>
$sections
  </main>

  <footer class="app-footer">
    Developer Health Analyzer v$version - Scan completed in ${scanDuration}s | No files were modified or deleted | Review recommendations before taking action
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
