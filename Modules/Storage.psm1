Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Storage analysis module — drives, SMART health, largest folders/files, disk usage summary.
.DESCRIPTION
    Enumerates logical and physical disks, collects SMART-like health via StorageReliabilityCounter,
    scans user-profile directories for large folders and files, calculates Recycle Bin size,
    and builds a categorized disk-usage summary for pie charts. Read-only — never modifies anything.
#>

function Get-StorageReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][scriptblock]$Log,
        [Parameter()][switch]$QuickScan
    )

    $recommendations = New-Object System.Collections.ArrayList

    # ── Logical Disks ────────────────────────────────────────
    $logicalDisks = @(Invoke-SafeCommand -Log $Log -Context 'logical disks' -Default @() -ScriptBlock {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    })

    # ── Physical Disks ───────────────────────────────────────
    $physicalDisks = @(Invoke-SafeCommand -Log $Log -Context 'physical disks' -Default @() -ScriptBlock {
        Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, SerialNumber, MediaType,
            HealthStatus, OperationalStatus, Size, BusType, FirmwareVersion
    })

    # ── Disk Drives (for NVMe detection) ─────────────────────
    $diskDrives = @(Invoke-SafeCommand -Log $Log -Context 'disk drives' -Default @() -ScriptBlock {
        Get-CimInstance Win32_DiskDrive | Select-Object Model, SerialNumber, InterfaceType,
            MediaType, Size, Status, FirmwareRevision
    })
    $nvme = @($diskDrives | Where-Object { $_.InterfaceType -match 'NVMe' -or $_.Model -match 'NVMe' })

    # ── SMART / Reliability Data ─────────────────────────────
    $smartData = @(Invoke-SafeCommand -Log $Log -Context 'storage reliability' -Default @() -ScriptBlock {
        Get-PhysicalDisk | ForEach-Object {
            $disk = $_
            $reliability = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            [pscustomobject]@{
                DiskNumber     = $disk.DeviceId
                Model          = $disk.FriendlyName
                HealthStatus   = $disk.HealthStatus
                MediaType      = $disk.MediaType
                Temperature    = if ($reliability) { $reliability.Temperature } else { $null }
                WearLevel      = if ($reliability) { $reliability.Wear } else { $null }
                PowerOnHours   = if ($reliability) { $reliability.PowerOnHours } else { $null }
                ReadErrors     = if ($reliability) { $reliability.ReadErrorsTotal } else { $null }
                WriteErrors    = if ($reliability) { $reliability.WriteErrorsTotal } else { $null }
            }
        }
    })

    # ── Build Drive Objects ──────────────────────────────────
    $drives = New-Object System.Collections.ArrayList
    $worstFreePercent = 100

    foreach ($disk in $logicalDisks) {
        $totalBytes = [int64]$disk.Size
        $freeBytes  = [int64]$disk.FreeSpace
        $usedBytes  = $totalBytes - $freeBytes
        $freePercent = if ($totalBytes -gt 0) { [math]::Round(($freeBytes / $totalBytes) * 100, 1) } else { 0 }

        if ($freePercent -lt $worstFreePercent) { $worstFreePercent = $freePercent }

        # Find matching physical disk media type
        $mediaType = 'Unknown'
        foreach ($pd in $physicalDisks) {
            if ($pd.MediaType) { $mediaType = $pd.MediaType.ToString(); break }
        }

        if ($freePercent -lt 10) {
            [void]$recommendations.Add((New-AnalyzerRecommendation `
                -Priority High -Category Storage `
                -Problem ("Low free space on {0} ({1:n1}% free)" -f $disk.DeviceID, $freePercent) `
                -Reason ("Only {0} free of {1} total." -f (ConvertTo-SizeString $freeBytes), (ConvertTo-SizeString $totalBytes)) `
                -Risk 'Builds, Docker, package managers, WSL, and Windows Update can fail with low disk space.' `
                -SuggestedFix 'Review the Cleanup Advisor section for safe cleanup opportunities.' `
                -EstimatedImprovement '+10 to +20 storage score'))
        }
        elseif ($freePercent -lt 20) {
            [void]$recommendations.Add((New-AnalyzerRecommendation `
                -Priority Medium -Category Storage `
                -Problem ("Moderate disk space on {0} ({1:n1}% free)" -f $disk.DeviceID, $freePercent) `
                -Reason ("Disk space is getting low with {0} free." -f (ConvertTo-SizeString $freeBytes)) `
                -Risk 'Large builds or Docker images may run into space issues.' `
                -SuggestedFix 'Monitor disk usage and consider cleaning caches.' `
                -EstimatedImprovement '+5 to +10 storage score'))
        }

        [void]$drives.Add([pscustomobject]@{
            Drive       = $disk.DeviceID
            Label       = $disk.VolumeName
            FileSystem  = $disk.FileSystem
            TotalBytes  = $totalBytes
            UsedBytes   = $usedBytes
            FreeBytes   = $freeBytes
            Total       = ConvertTo-SizeString $totalBytes
            Used        = ConvertTo-SizeString $usedBytes
            Free        = ConvertTo-SizeString $freeBytes
            FreePercent = $freePercent
            MediaType   = $mediaType
        })
    }

    # ── Recycle Bin ──────────────────────────────────────────
    $recycleBin = Invoke-SafeCommand -Log $Log -Context 'Recycle Bin' -Default ([pscustomobject]@{ ItemCount = 0; SizeBytes = 0; SizeGB = 0 }) -ScriptBlock {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.NameSpace(0x0a)
        $items = $folder.Items()
        $totalSize = 0L
        $count = $items.Count
        foreach ($item in $items) {
            try { $totalSize += $folder.GetDetailsOf($item, 2) -replace '[^\d]', '' } catch { }
        }
        # Fallback: estimate from $Recycle.Bin if COM size is 0
        if ($totalSize -eq 0 -and $count -gt 0) {
            foreach ($drv in @($logicalDisks)) {
                $rbPath = Join-Path $drv.DeviceID '$Recycle.Bin'
                if (Test-Path -LiteralPath $rbPath) {
                    try {
                        $totalSize += (Get-ChildItem -LiteralPath $rbPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    } catch { }
                }
            }
        }
        [pscustomobject]@{
            ItemCount = [int]$count
            SizeBytes = [int64]$totalSize
            SizeGB    = [math]::Round($totalSize / 1GB, 3)
        }
    }

    # ── Scan Roots for Large Folders ─────────────────────────
    $scanRoots = New-Object System.Collections.ArrayList
    $candidateRoots = @(
        $env:USERPROFILE,
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Documents'),
        $env:TEMP
    )
    if ($QuickScan) {
        $candidateRoots = @(
            (Join-Path $env:USERPROFILE 'Downloads'),
            (Join-Path $env:USERPROFILE 'Desktop'),
            $env:TEMP
        )
    }
    foreach ($path in $candidateRoots) {
        if ($path -and (Test-Path -LiteralPath $path)) { [void]$scanRoots.Add($path) }
    }

    $largestFolders = New-Object System.Collections.ArrayList
    foreach ($root in $scanRoots) {
        Invoke-AnalyzerLog -Log $Log -Level INFO -Message "Sizing top-level folders under $root"
        try {
            Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $info = Get-FolderSizeInfo -Path $_.FullName -Log $Log
                if ($info.SizeBytes -ge 500MB) { [void]$largestFolders.Add($info) }
            }
        }
        catch {
            Invoke-AnalyzerLog -Log $Log -Level DEBUG -Message "Folder scan skipped for $root`: $($_.Exception.Message)"
        }
    }
    $largestFolders = @($largestFolders | Sort-Object SizeBytes -Descending | Select-Object -First 100)

    # ── Largest Files ────────────────────────────────────────
    $largestFiles = New-Object System.Collections.ArrayList
    if (-not $QuickScan) {
        foreach ($root in $scanRoots) {
            Invoke-AnalyzerLog -Log $Log -Level INFO -Message "Finding large files under $root"
            try {
                Get-ChildItem -LiteralPath $root -File -Force -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -ge 50MB } |
                    Sort-Object Length -Descending |
                    Select-Object -First 100 |
                    ForEach-Object {
                        [void]$largestFiles.Add([pscustomobject]@{
                            Path         = $_.FullName
                            SizeBytes    = [int64]$_.Length
                            SizeMB       = [math]::Round($_.Length / 1MB, 1)
                            Extension    = $_.Extension
                            LastModified = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                        })
                    }
            }
            catch {
                Invoke-AnalyzerLog -Log $Log -Level DEBUG -Message "File scan skipped for $root`: $($_.Exception.Message)"
            }
        }
    }
    $largestFiles = @($largestFiles | Sort-Object SizeBytes -Descending | Select-Object -First 200)

    # ── Folder Thresholds ────────────────────────────────────
    $thresholdSummary = [ordered]@{}
    foreach ($threshold in @(500MB, 1GB, 5GB, 10GB, 20GB)) {
        $thresholdSummary[(ConvertTo-SizeString $threshold)] = @($largestFolders | Where-Object { $_.SizeBytes -ge $threshold }).Count
    }

    # ── Disk Usage Summary (for pie chart) ───────────────────
    $diskUsageSummary = New-Object System.Collections.ArrayList
    $totalUsedBytes = ($drives | Measure-Object -Property UsedBytes -Sum).Sum
    $categorized = @{
        'Downloads'   = (Get-FolderSizeInfo -Path (Join-Path $env:USERPROFILE 'Downloads') -Log $Log).SizeBytes
        'Documents'   = (Get-FolderSizeInfo -Path (Join-Path $env:USERPROFILE 'Documents') -Log $Log).SizeBytes
        'Desktop'     = (Get-FolderSizeInfo -Path (Join-Path $env:USERPROFILE 'Desktop') -Log $Log).SizeBytes
        'AppData'     = (Get-FolderSizeInfo -Path $env:LOCALAPPDATA -Log $Log).SizeBytes
        'Recycle Bin' = $recycleBin.SizeBytes
    }
    $categorizedTotal = ($categorized.Values | Measure-Object -Sum).Sum
    $otherBytes = [math]::Max([long]0, $totalUsedBytes - $categorizedTotal)

    foreach ($key in $categorized.Keys) {
        [void]$diskUsageSummary.Add([pscustomobject]@{
            Category   = $key
            SizeGB     = [math]::Round($categorized[$key] / 1GB, 2)
            SizeBytes  = $categorized[$key]
        })
    }
    [void]$diskUsageSummary.Add([pscustomobject]@{ Category = 'Other'; SizeGB = [math]::Round($otherBytes / 1GB, 2); SizeBytes = $otherBytes })

    # ── Scoring ──────────────────────────────────────────────
    $score = 100

    # Free space deductions
    if ($worstFreePercent -lt 5)        { $score -= 35 }
    elseif ($worstFreePercent -lt 10)   { $score -= 25 }
    elseif ($worstFreePercent -lt 15)   { $score -= 15 }
    elseif ($worstFreePercent -lt 20)   { $score -= 5  }

    # Unhealthy physical disks
    $unhealthyPhysical = @($physicalDisks | Where-Object { $_.HealthStatus -and $_.HealthStatus -ne 'Healthy' })
    if ($unhealthyPhysical.Count -gt 0) {
        $score -= 30
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Critical -Category Storage `
            -Problem 'Physical disk reporting non-healthy status' `
            -Reason (($unhealthyPhysical | ForEach-Object { "$($_.FriendlyName): $($_.HealthStatus)" }) -join '; ') `
            -Risk 'Data loss or drive failure may be imminent.' `
            -SuggestedFix 'Back up critical data immediately and run vendor disk diagnostics.' `
            -EstimatedImprovement 'Risk reduction — data safety'))
    }

    # SMART temperature warnings
    $hotDisks = @($smartData | Where-Object { $_.Temperature -and $_.Temperature -gt 65 })
    if ($hotDisks.Count -gt 0) {
        $score -= 10
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Medium -Category Storage `
            -Problem 'Disk temperature elevated' `
            -Reason (($hotDisks | ForEach-Object { "$($_.Model): $($_.Temperature)°C" }) -join '; ') `
            -Risk 'High temperatures can reduce SSD lifespan and cause throttling.' `
            -SuggestedFix 'Ensure adequate cooling and airflow. Check if heatsinks are properly installed.' `
            -EstimatedImprovement '+5 storage score'))
    }

    # SMART wear level
    $wornDisks = @($smartData | Where-Object { $null -ne $_.WearLevel -and $_.WearLevel -gt 80 })
    if ($wornDisks.Count -gt 0) {
        $score -= 15
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority High -Category Storage `
            -Problem 'SSD wear level is high' `
            -Reason (($wornDisks | ForEach-Object { "$($_.Model): $($_.WearLevel)% worn" }) -join '; ') `
            -Risk 'The SSD is approaching end of life and may fail.' `
            -SuggestedFix 'Plan SSD replacement and ensure backups are current.' `
            -EstimatedImprovement 'Risk reduction'))
    }

    [pscustomobject]@{
        Score             = [int](Limit-Number -Value $score -Minimum 0 -Maximum 100)
        Drives            = @($drives)
        PhysicalDisks     = @($physicalDisks)
        DiskDrives        = @($diskDrives)
        SmartData         = @($smartData)
        Nvme              = @($nvme)
        RecycleBin        = $recycleBin
        LargestFolders    = @($largestFolders)
        LargestFiles      = @($largestFiles)
        FolderThresholds  = [pscustomobject]$thresholdSummary
        DiskUsageSummary  = @($diskUsageSummary)
        Treemap           = @($largestFolders | Select-Object -First 40 Path, SizeBytes, SizeGB)
        Recommendations   = @($recommendations)
    }
}

Export-ModuleMember -Function Get-StorageReport
