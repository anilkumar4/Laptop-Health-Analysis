Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Performance analysis module — CPU, RAM, page file, disk I/O, processes, network.
.DESCRIPTION
    Collects point-in-time CPU usage (sampled via Win32_Processor LoadPercentage),
    memory pressure, page file usage, disk queue lengths, top processes by CPU and
    RAM, background process count, and network adapter inventory. Read-only.
#>

function Get-PerformanceReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][scriptblock]$Log)

    $recommendations = New-Object System.Collections.ArrayList
    $score = 100

    # ── CPU Information & Usage ──────────────────────────────
    $processor = Invoke-SafeCommand -Log $Log -Context 'processor info' -ScriptBlock {
        Get-CimInstance Win32_Processor | Select-Object -First 1 Name, NumberOfCores,
            NumberOfLogicalProcessors, MaxClockSpeed, LoadPercentage, Architecture
    }

    # Sample CPU load twice for better accuracy
    $cpuSamples = @()
    for ($i = 0; $i -lt 2; $i++) {
        $sample = Invoke-SafeCommand -Log $Log -Context "CPU sample $i" -ScriptBlock {
            (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        }
        if ($null -ne $sample) { $cpuSamples += $sample }
        if ($i -eq 0) { Start-Sleep -Milliseconds 800 }
    }
    $cpuLoad = if ($cpuSamples.Count -gt 0) { [math]::Round(($cpuSamples | Measure-Object -Average).Average, 1) }
               elseif ($processor) { $processor.LoadPercentage }
               else { $null }

    $cpuInfo = [pscustomobject]@{
        Name               = if ($processor) { $processor.Name } else { $null }
        Cores              = if ($processor) { $processor.NumberOfCores } else { $null }
        LogicalProcessors  = if ($processor) { $processor.NumberOfLogicalProcessors } else { $null }
        MaxClockSpeedMHz   = if ($processor) { $processor.MaxClockSpeed } else { $null }
        LoadPercent        = $cpuLoad
        Architecture       = if ($processor) {
            switch ($processor.Architecture) {
                0 { 'x86' }; 5 { 'ARM' }; 9 { 'x64' }; 12 { 'ARM64' }; default { "Unknown ($($processor.Architecture))" }
            }
        } else { $null }
    }

    # ── Memory ───────────────────────────────────────────────
    $os = Invoke-SafeCommand -Log $Log -Context 'OS memory info' -ScriptBlock {
        Get-CimInstance Win32_OperatingSystem
    }

    $totalMemoryGB   = if ($os) { [math]::Round(($os.TotalVisibleMemorySize * 1KB) / 1GB, 2) } else { $null }
    $freeMemoryGB    = if ($os) { [math]::Round(($os.FreePhysicalMemory * 1KB) / 1GB, 2) } else { $null }
    $usedMemoryGB    = if ($totalMemoryGB -and $freeMemoryGB) { [math]::Round($totalMemoryGB - $freeMemoryGB, 2) } else { $null }
    $memoryUsedPct   = if ($os -and $os.TotalVisibleMemorySize -gt 0) {
        [math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100, 1)
    } else { $null }

    # Memory modules info
    $memoryModules = @(Invoke-SafeCommand -Log $Log -Context 'memory modules' -Default @() -ScriptBlock {
        Get-CimInstance Win32_PhysicalMemory |
            Select-Object BankLabel, Capacity, Speed, Manufacturer, MemoryType, FormFactor |
            ForEach-Object {
                [pscustomobject]@{
                    Bank         = $_.BankLabel
                    CapacityGB   = [math]::Round($_.Capacity / 1GB, 1)
                    SpeedMHz     = $_.Speed
                    Manufacturer = $_.Manufacturer
                }
            }
    })

    $memoryInfo = [pscustomobject]@{
        TotalGB     = $totalMemoryGB
        UsedGB      = $usedMemoryGB
        FreeGB      = $freeMemoryGB
        UsedPercent = $memoryUsedPct
        Slots       = $memoryModules.Count
        Modules     = @($memoryModules)
    }

    # ── Page File ────────────────────────────────────────────
    $pageFiles = @(Invoke-SafeCommand -Log $Log -Context 'page files' -Default @() -ScriptBlock {
        Get-CimInstance Win32_PageFileUsage | ForEach-Object {
            [pscustomobject]@{
                Path          = $_.Name
                AllocatedMB   = $_.AllocatedBaseSize
                CurrentUseMB  = $_.CurrentUsage
                PeakUseMB     = $_.PeakUsage
                UsagePercent  = if ($_.AllocatedBaseSize -gt 0) {
                    [math]::Round(($_.CurrentUsage / $_.AllocatedBaseSize) * 100, 1)
                } else { 0 }
            }
        }
    })

    # ── Disk Activity ────────────────────────────────────────
    $diskCounters = @(Invoke-SafeCommand -Log $Log -Context 'disk counters' -Default @() -ScriptBlock {
        Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk |
            Where-Object { $_.Name -ne '_Total' } |
            ForEach-Object {
                [pscustomobject]@{
                    Disk               = $_.Name
                    PercentDiskTime    = $_.PercentDiskTime
                    AvgQueueLength     = $_.AvgDiskQueueLength
                    ReadBytesPerSec    = $_.DiskReadBytesPerSec
                    WriteBytesPerSec   = $_.DiskWriteBytesPerSec
                    ReadSpeed          = ConvertTo-SizeString $_.DiskReadBytesPerSec
                    WriteSpeed         = ConvertTo-SizeString $_.DiskWriteBytesPerSec
                }
            }
    })

    # -- Top Processes -----------------------------------------
    $allProcesses = @(Get-Process -ErrorAction SilentlyContinue)

    $topCpu = @($allProcesses |
        Where-Object { try { $null -ne $_.CPU } catch { $false } } |
        Sort-Object @{Expression={try{$_.CPU.TotalSeconds}catch{0}}} -Descending |
        Select-Object -First 15 Name, Id,
            @{N='CPU'; E={try{[math]::Round($_.CPU.TotalSeconds, 2)}catch{0}}},
            @{N='MemoryMB'; E={[math]::Round($_.WorkingSet64 / 1MB, 1)}},
            @{N='Path';     E={$_.Path}} -ErrorAction SilentlyContinue)

    $topMemory = @($allProcesses |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 15 Name, Id,
            @{N='MemoryMB'; E={[math]::Round($_.WorkingSet64 / 1MB, 1)}},
            @{N='CPU'; E={try{[math]::Round($_.CPU.TotalSeconds, 2)}catch{0}}},
            @{N='Path'; E={$_.Path}} -ErrorAction SilentlyContinue)

    $bgProcessCount = $allProcesses.Count

    # ── Network ──────────────────────────────────────────────
    $networkAdapters = @(Invoke-SafeCommand -Log $Log -Context 'network adapters' -Default @() -ScriptBlock {
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
            Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress,
                          DriverVersion, MediaConnectionState
    })

    $dnsServers = @(Invoke-SafeCommand -Log $Log -Context 'DNS servers' -Default @() -ScriptBlock {
        Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddresses.Count -gt 0 } |
            Select-Object InterfaceAlias, @{N='Servers'; E={$_.ServerAddresses -join ', '}}
    })

    $proxy = Invoke-SafeCommand -Log $Log -Context 'proxy settings' -ScriptBlock {
        $regProxy = Get-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name 'ProxyEnable'
        $proxyServer = Get-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name 'ProxyServer'
        [pscustomobject]@{
            Enabled = ($regProxy -eq 1)
            Server  = $proxyServer
        }
    }

    $vpnAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object {
            $_.InterfaceDescription -match 'VPN|TAP|WireGuard|OpenVPN|Cisco|AnyConnect|GlobalProtect|Pulse|Juniper|Fortinet' -or
            $_.Name -match 'VPN|WireGuard|OpenVPN'
        } |
        Select-Object Name, InterfaceDescription, Status)

    # ── Scoring ──────────────────────────────────────────────
    if ($cpuLoad -and $cpuLoad -gt 90) {
        $score -= 20
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority High -Category Performance `
            -Problem ("Very high CPU usage: {0:n1}%" -f $cpuLoad) `
            -Reason 'CPU utilization is above 90%.' `
            -Risk 'Compilation, indexing, and IDE responsiveness will be severely impacted.' `
            -SuggestedFix 'Identify and pause resource-intensive background tasks.' `
            -EstimatedImprovement '+10 to +15 performance score'))
    }
    elseif ($cpuLoad -and $cpuLoad -gt 80) {
        $score -= 10
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Medium -Category Performance `
            -Problem ("High CPU usage: {0:n1}%" -f $cpuLoad) `
            -Reason 'CPU load is elevated above 80%.' `
            -Risk 'Builds and tests may run slower than expected.' `
            -SuggestedFix 'Review top CPU processes and pause nonessential workloads.' `
            -EstimatedImprovement '+5 to +10 performance score'))
    }

    if ($memoryUsedPct -and $memoryUsedPct -gt 90) {
        $score -= 25
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority High -Category Performance `
            -Problem ("Critical memory pressure: {0:n1}% used" -f $memoryUsedPct) `
            -Reason 'Memory usage exceeds 90%, forcing heavy paging.' `
            -Risk 'IDEs, Docker, WSL, and browsers will experience significant slowdowns.' `
            -SuggestedFix 'Close memory-intensive applications or consider upgrading RAM.' `
            -EstimatedImprovement '+15 to +25 performance score'))
    }
    elseif ($memoryUsedPct -and $memoryUsedPct -gt 80) {
        $score -= 15
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Medium -Category Performance `
            -Problem ("High memory usage: {0:n1}%" -f $memoryUsedPct) `
            -Reason 'Memory usage above 80% with limited headroom.' `
            -Risk 'Opening additional tools may trigger excessive paging.' `
            -SuggestedFix 'Close unused browser tabs and idle containers.' `
            -EstimatedImprovement '+5 to +15 performance score'))
    }

    # Disk queue pressure
    $highQueueDisks = @($diskCounters | Where-Object { $_.AvgQueueLength -gt 2 })
    if ($highQueueDisks.Count -gt 0) {
        $score -= 10
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Medium -Category Performance `
            -Problem 'Disk I/O queue pressure detected' `
            -Reason ("Disk(s) with queue > 2: {0}" -f (($highQueueDisks | ForEach-Object { $_.Disk }) -join ', ')) `
            -Risk 'Compilation, git operations, and package restores may be I/O-bound.' `
            -SuggestedFix 'Move working projects to faster storage or reduce concurrent I/O.' `
            -EstimatedImprovement '+5 performance score'))
    }

    # Too many processes
    if ($bgProcessCount -gt 300) {
        $score -= 5
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Low -Category Performance `
            -Problem ("High process count: $bgProcessCount") `
            -Reason 'A large number of running processes increases context-switch overhead.' `
            -Risk 'Minor performance impact from scheduling overhead.' `
            -SuggestedFix 'Review startup applications and disable unused background services.' `
            -EstimatedImprovement '+3 performance score'))
    }

    # Low RAM for dev workstation
    if ($totalMemoryGB -and $totalMemoryGB -lt 8) {
        $score -= 10
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Medium -Category Performance `
            -Problem ("Low total RAM: $totalMemoryGB GB") `
            -Reason 'Modern development workloads typically need at least 16 GB.' `
            -Risk 'Running IDEs, Docker, and browsers simultaneously may be constrained.' `
            -SuggestedFix 'Upgrade system RAM to 16 GB or more.' `
            -EstimatedImprovement '+10 performance score'))
    }

    [pscustomobject]@{
        Score                = [int](Limit-Number -Value $score -Minimum 0 -Maximum 100)
        CPU                  = $cpuInfo
        Memory               = $memoryInfo
        PageFile             = @($pageFiles)
        DiskActivity         = @($diskCounters)
        TopCpuProcesses      = @($topCpu)
        TopMemoryProcesses   = @($topMemory)
        BackgroundProcessCount = $bgProcessCount
        Network              = [pscustomobject]@{
            Adapters    = @($networkAdapters)
            Dns         = @($dnsServers)
            Proxy       = $proxy
            VpnAdapters = @($vpnAdapters)
            SpeedTest   = 'Optional: integrate an approved enterprise speed-test endpoint.'
        }
        Recommendations      = @($recommendations)
    }
}

Export-ModuleMember -Function Get-PerformanceReport
