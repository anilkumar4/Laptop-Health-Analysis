Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Windows health analysis module.
.DESCRIPTION
    Collects system inventory (computer model, CPU, RAM, BIOS, motherboard),
    OS details (edition, build, install date, uptime), pending reboot detection,
    Windows Update status, SFC/DISM last-known results from logs, and reliability
    records from WMI. Read-only — never runs repairs.
#>

function Test-PendingReboot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $signals = New-Object System.Collections.ArrayList

    # Component Based Servicing
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        [void]$signals.Add('Component Based Servicing')
    }

    # Windows Update
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        [void]$signals.Add('Windows Update')
    }

    # Pending file rename operations
    $pendingRename = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations'
    if ($pendingRename) {
        [void]$signals.Add('PendingFileRenameOperations')
    }

    # SCCM client
    try {
        $sccm = Invoke-CimMethod -Namespace 'root\CCM\ClientSDK' -ClassName CCM_ClientUtilities -MethodName DetermineIfRebootPending -ErrorAction Stop
        if ($sccm.RebootPending -or $sccm.IsHardRebootPending) {
            [void]$signals.Add('SCCM Client')
        }
    }
    catch { }

    [pscustomobject]@{
        Pending = ($signals.Count -gt 0)
        Signals = @($signals)
    }
}

function Get-WindowsUpdateSummary {
    [CmdletBinding()]
    param([Parameter()][scriptblock]$Log)

    $summary = [pscustomobject]@{
        AvailableUpdates     = $null
        LastSearchSuccessDate = $null
        RecentUpdates        = @()
        Error                = $null
        ServiceReachable     = $false
    }

    # Get recent installed updates via Get-HotFix
    $summary.RecentUpdates = @(Invoke-SafeCommand -Log $Log -Context 'installed hotfixes' -Default @() -ScriptBlock {
        Get-HotFix -ErrorAction SilentlyContinue |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 15 HotFixID, Description, InstalledBy,
                @{N='InstalledOn'; E={ if ($_.InstalledOn) { $_.InstalledOn.ToString('yyyy-MM-dd') } else { 'Unknown' } }}
    })

    # Query Windows Update for pending updates via COM
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()

        # Last search date
        $history = $searcher.QueryHistory(0, 1)
        if ($history.Count -gt 0) {
            $summary.LastSearchSuccessDate = $history.Item(0).Date
        }

        # Pending (not installed, not hidden)
        $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
        $summary.AvailableUpdates = $result.Updates.Count
        $summary.ServiceReachable = $true
    }
    catch {
        $summary.Error = $_.Exception.Message
        Invoke-AnalyzerLog -Log $Log -Level DEBUG -Message "Windows Update COM query failed: $($_.Exception.Message)"
    }

    return $summary
}

function Get-SfcDismStatus {
    [CmdletBinding()]
    param([Parameter()][scriptblock]$Log)

    $sfcResult  = [pscustomobject]@{ LastRun = $null; Result = 'Not checked'; Details = $null }
    $dismResult = [pscustomobject]@{ LastRun = $null; Result = 'Not checked'; Details = $null }

    # Parse CBS.log for last SFC verification/scan
    $cbsLog = 'C:\Windows\Logs\CBS\CBS.log'
    if (Test-Path -LiteralPath $cbsLog) {
        try {
            # Read last 500 lines for speed
            $cbsLines = Get-Content -LiteralPath $cbsLog -Tail 500 -ErrorAction SilentlyContinue
            $sfcLines = @($cbsLines | Where-Object { $_ -match 'Verify complete|verification.*complete|found corruption|no integrity violations' })
            if ($sfcLines.Count -gt 0) {
                $lastLine = $sfcLines[-1]
                $sfcResult.Details = $lastLine.Trim()
                if ($lastLine -match 'no integrity violations') {
                    $sfcResult.Result = 'No integrity violations found'
                }
                elseif ($lastLine -match 'found corruption') {
                    $sfcResult.Result = 'Corruption detected'
                }
                else {
                    $sfcResult.Result = 'Completed'
                }
                # Try to extract timestamp
                if ($lastLine -match '^\d{4}-\d{2}-\d{2}') {
                    $sfcResult.LastRun = $lastLine.Substring(0, 19)
                }
            }
        }
        catch {
            Invoke-AnalyzerLog -Log $Log -Level DEBUG -Message "CBS.log parse failed: $($_.Exception.Message)"
        }
    }

    # Parse DISM.log for last check
    $dismLog = 'C:\Windows\Logs\DISM\dism.log'
    if (Test-Path -LiteralPath $dismLog) {
        try {
            $dismLines = Get-Content -LiteralPath $dismLog -Tail 200 -ErrorAction SilentlyContinue
            $healthLines = @($dismLines | Where-Object { $_ -match 'The component store is repairable|no component store corruption|RestoreHealth' })
            if ($healthLines.Count -gt 0) {
                $dismResult.Details = $healthLines[-1].Trim()
                if ($healthLines[-1] -match 'no component store corruption') {
                    $dismResult.Result = 'Healthy'
                }
                elseif ($healthLines[-1] -match 'repairable') {
                    $dismResult.Result = 'Repairable corruption found'
                }
                else {
                    $dismResult.Result = 'Checked'
                }
            }
        }
        catch {
            Invoke-AnalyzerLog -Log $Log -Level DEBUG -Message "DISM.log parse failed: $($_.Exception.Message)"
        }
    }

    [pscustomobject]@{
        SFC  = $sfcResult
        DISM = $dismResult
        Notes = 'Analyzer is read-only and does not run sfc /scannow or DISM /RestoreHealth. Results show last known state from log files.'
    }
}

function Get-WindowsHealthReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][scriptblock]$Log)

    $recommendations = New-Object System.Collections.ArrayList

    # ── System Inventory ─────────────────────────────────────
    $os        = Invoke-SafeCommand -Log $Log -Context 'Win32_OperatingSystem' -ScriptBlock { Get-CimInstance Win32_OperatingSystem }
    $computer  = Invoke-SafeCommand -Log $Log -Context 'Win32_ComputerSystem'  -ScriptBlock { Get-CimInstance Win32_ComputerSystem }
    $processor = Invoke-SafeCommand -Log $Log -Context 'Win32_Processor'       -ScriptBlock { Get-CimInstance Win32_Processor | Select-Object -First 1 }
    $bios      = Invoke-SafeCommand -Log $Log -Context 'Win32_BIOS'            -ScriptBlock { Get-CimInstance Win32_BIOS }
    $baseBoard = Invoke-SafeCommand -Log $Log -Context 'Win32_BaseBoard'       -ScriptBlock { Get-CimInstance Win32_BaseBoard }

    # ── Derived Values ───────────────────────────────────────
    $lastBoot = $null
    $uptime   = $null
    $uptimeFormatted = $null

    if ($os -and $os.LastBootUpTime) {
        # CIM returns [DateTime] directly — no conversion needed
        $lastBoot = $os.LastBootUpTime
        $uptime = New-TimeSpan -Start $lastBoot -End (Get-Date)
        $uptimeFormatted = '{0}d {1}h {2}m' -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    }

    $installDate = $null
    if ($os -and $os.InstallDate) {
        $installDate = $os.InstallDate
    }

    # Windows display version (e.g., "23H2")
    $displayVersion = Get-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'DisplayVersion'

    # ── Checks ───────────────────────────────────────────────
    $pendingReboot = Test-PendingReboot
    $windowsUpdate = Get-WindowsUpdateSummary -Log $Log
    $servicing     = Get-SfcDismStatus -Log $Log

    # Reliability records (last 14 days)
    $reliability = @(Invoke-SafeCommand -Log $Log -Context 'reliability records' -Default @() -ScriptBlock {
        Get-CimInstance -Namespace root\cimv2 -ClassName Win32_ReliabilityRecords -ErrorAction Stop |
            Where-Object { $_.TimeGenerated -gt (Get-Date).AddDays(-14) } |
            Sort-Object TimeGenerated -Descending |
            Select-Object -First 50 SourceName, EventIdentifier, ProductName, Message, TimeGenerated
    })

    # ── Scoring ──────────────────────────────────────────────
    $score = 100

    if ($pendingReboot.Pending) {
        $score -= 10
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Medium -Category Windows `
            -Problem 'Pending reboot detected' `
            -Reason ("Reboot signals: {0}" -f ($pendingReboot.Signals -join ', ')) `
            -Risk 'Updates, driver installs, or component servicing may remain incomplete.' `
            -SuggestedFix 'Save work and reboot at a convenient time.' `
            -EstimatedImprovement '+5 to +10 Windows score'))
    }

    if ($windowsUpdate.AvailableUpdates -and $windowsUpdate.AvailableUpdates -gt 0) {
        $deduction = [math]::Min(20, $windowsUpdate.AvailableUpdates * 3)
        $score -= $deduction
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority High -Category Windows `
            -Problem ("{0} Windows update(s) pending" -f $windowsUpdate.AvailableUpdates) `
            -Reason 'Uninstalled updates may include security patches and bug fixes.' `
            -Risk 'Missing critical patches exposes the system to known vulnerabilities.' `
            -SuggestedFix 'Open Settings > Windows Update and install available updates.' `
            -EstimatedImprovement '+5 to +15 Windows score'))
    }

    if ($servicing.SFC.Result -match 'Corruption') {
        $score -= 15
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority High -Category Windows `
            -Problem 'SFC detected system file corruption' `
            -Reason $servicing.SFC.Details `
            -Risk 'Corrupted system files can cause crashes, build failures, and erratic behavior.' `
            -SuggestedFix 'Run "sfc /scannow" and "DISM /Online /Cleanup-Image /RestoreHealth" in an elevated prompt.' `
            -EstimatedImprovement '+10 to +15 Windows score'))
    }

    if (@($reliability).Count -gt 15) {
        $score -= 10
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Medium -Category Windows `
            -Problem ("$(@($reliability).Count) reliability events in the last 14 days") `
            -Reason 'Windows Reliability Monitor has logged many recent failures.' `
            -Risk 'Repeated failures can indicate driver, runtime, or toolchain instability.' `
            -SuggestedFix 'Review the reliability records and address recurring sources.' `
            -EstimatedImprovement '+5 stability improvement'))
    }

    # High uptime warning
    if ($uptime -and $uptime.TotalDays -gt 30) {
        $score -= 5
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Low -Category Windows `
            -Problem ("System uptime: $uptimeFormatted") `
            -Reason 'The system has not been restarted in over 30 days.' `
            -Risk 'Memory leaks, stale drivers, and kernel patches may not be applied.' `
            -SuggestedFix 'Schedule a reboot to apply pending updates and clear resources.' `
            -EstimatedImprovement '+3 Windows score'))
    }

    # ── Build Result ─────────────────────────────────────────
    [pscustomobject]@{
        Score = [int](Limit-Number -Value $score -Minimum 0 -Maximum 100)
        System = [pscustomobject]@{
            ComputerModel        = if ($computer) { "$($computer.Manufacturer) $($computer.Model)".Trim() } else { $null }
            Manufacturer         = if ($computer) { $computer.Manufacturer } else { $null }
            Model                = if ($computer) { $computer.Model } else { $null }
            CPU                  = if ($processor) { $processor.Name } else { $null }
            CPUCores             = if ($processor) { $processor.NumberOfCores } else { $null }
            CPULogicalProcessors = if ($processor) { $processor.NumberOfLogicalProcessors } else { $null }
            RAMGB                = if ($computer -and $computer.TotalPhysicalMemory) { [math]::Round($computer.TotalPhysicalMemory / 1GB, 2) } else { $null }
            Motherboard          = if ($baseBoard) { "$($baseBoard.Manufacturer) $($baseBoard.Product)".Trim() } else { $null }
            BIOS                 = if ($bios) { "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)".Trim() } else { $null }
            BIOSDate             = if ($bios -and $bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') } else { $null }
            SerialNumber         = if ($bios) { $bios.SerialNumber } else { $null }
            WindowsEdition       = if ($os) { $os.Caption } else { $null }
            BuildNumber          = if ($os) { $os.BuildNumber } else { $null }
            DisplayVersion       = $displayVersion
            Architecture         = if ($os) { $os.OSArchitecture } else { $null }
            InstallDate          = if ($installDate) { $installDate.ToString('yyyy-MM-dd') } else { $null }
            LastBoot             = if ($lastBoot) { $lastBoot.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
            Uptime               = $uptimeFormatted
            UptimeDays           = if ($uptime) { [math]::Round($uptime.TotalDays, 1) } else { $null }
        }
        PendingReboot      = $pendingReboot
        WindowsUpdate      = $windowsUpdate
        Servicing          = $servicing
        ReliabilityRecords = @($reliability)
        Recommendations    = @($recommendations)
    }
}

Export-ModuleMember -Function Get-WindowsHealthReport
