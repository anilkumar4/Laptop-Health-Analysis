Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Battery health analysis module.
.DESCRIPTION
    Detects battery presence via WMI/CIM, reads design and full-charge capacity,
    parses powercfg /batteryreport XML for cycle count and charging history,
    and calculates wear level and health percentage. Returns Score=100 for desktops.
    Read-only — the only temp file created is the battery report XML which is cleaned up.
#>

function Get-BatteryReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][scriptblock]$Log)

    $recommendations = New-Object System.Collections.ArrayList

    # ── Detect battery via multiple sources ──────────────────
    $batteries = @(Invoke-SafeCommand -Log $Log -Context 'battery full charge' -Default @() -ScriptBlock {
        Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity |
            Select-Object InstanceName, FullChargedCapacity
    })
    $design = @(Invoke-SafeCommand -Log $Log -Context 'battery static data' -Default @() -ScriptBlock {
        Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData |
            Select-Object InstanceName, DesignedCapacity, ManufactureName, SerialNumber, DeviceName, UniqueID
    })
    $runtime = @(Invoke-SafeCommand -Log $Log -Context 'Win32_Battery' -Default @() -ScriptBlock {
        Get-CimInstance Win32_Battery |
            Select-Object Name, BatteryStatus, EstimatedChargeRemaining, EstimatedRunTime,
                          Chemistry, DesignVoltage, DeviceID
    })

    # No battery — desktop system
    if ($batteries.Count -eq 0 -and $runtime.Count -eq 0) {
        Invoke-AnalyzerLog -Log $Log -Level INFO -Message 'No battery detected — desktop system.'
        return [pscustomobject]@{
            Score           = 100
            Present         = $false
            Batteries       = @()
            ChargingHistory = @()
            Recommendations = @()
        }
    }

    # ── Parse powercfg battery report XML for cycle count ────
    $cycleCount     = $null
    $chargingHistory = @()
    $powercfgDesign = $null
    $powercfgFull   = $null

    $tempXml = Join-Path $env:TEMP "devhealth_battery_$(Get-Random).xml"
    try {
        Invoke-AnalyzerLog -Log $Log -Level INFO -Message 'Generating powercfg battery report...'
        $null = & powercfg /batteryreport /output $tempXml /xml 2>&1

        if (Test-Path -LiteralPath $tempXml) {
            [xml]$xmlDoc = Get-Content -LiteralPath $tempXml -Raw -Encoding UTF8

            # Extract battery info
            $batNode = $xmlDoc.BatteryReport.Batteries.Battery | Select-Object -First 1
            if ($batNode) {
                $powercfgDesign = [int64]$batNode.DesignCapacity
                $powercfgFull   = [int64]$batNode.FullChargeCapacity
                $cycleCount     = if ($batNode.CycleCount) { [int]$batNode.CycleCount } else { $null }
            }

            # Extract recent usage / charging history (last 15 entries)
            $historyEntries = $xmlDoc.BatteryReport.RecentUsage.Usage |
                Select-Object -Last 15 |
                ForEach-Object {
                    [pscustomobject]@{
                        Timestamp          = $_.Timestamp
                        AcOnline           = $_.AcOnline
                        ChargeCapacity     = if ($_.ChargeCapacity) { [int64]$_.ChargeCapacity } else { $null }
                        FullChargeCapacity = if ($_.FullChargeCapacity) { [int64]$_.FullChargeCapacity } else { $null }
                    }
                }
            if ($historyEntries) { $chargingHistory = @($historyEntries) }

            Invoke-AnalyzerLog -Log $Log -Level INFO -Message "Battery report parsed: CycleCount=$cycleCount"
        }
    }
    catch {
        Invoke-AnalyzerLog -Log $Log -Level DEBUG -Message "powercfg battery report parse failed: $($_.Exception.Message)"
    }
    finally {
        # Clean up temp file
        if (Test-Path -LiteralPath $tempXml) {
            Remove-Item -LiteralPath $tempXml -Force -ErrorAction SilentlyContinue
        }
    }

    # ── Build battery objects ────────────────────────────────
    $batteryReports = New-Object System.Collections.ArrayList

    foreach ($item in $runtime) {
        $matchDesign = $design | Select-Object -First 1
        $matchFull   = $batteries | Select-Object -First 1

        # Prefer powercfg data, fall back to WMI
        $designCapacity = if ($powercfgDesign -and $powercfgDesign -gt 0) { $powercfgDesign }
                          elseif ($matchDesign -and $matchDesign.DesignedCapacity) { [double]$matchDesign.DesignedCapacity }
                          else { $null }

        $fullCapacity   = if ($powercfgFull -and $powercfgFull -gt 0) { $powercfgFull }
                          elseif ($matchFull -and $matchFull.FullChargedCapacity) { [double]$matchFull.FullChargedCapacity }
                          else { $null }

        $health = if ($designCapacity -and $designCapacity -gt 0 -and $fullCapacity) {
            [math]::Round(($fullCapacity / $designCapacity) * 100, 1)
        } else { $null }

        $wearLevel = if ($health) { [math]::Round(100 - $health, 1) } else { $null }

        # Battery status mapping
        $statusText = switch ($item.BatteryStatus) {
            1 { 'Discharging' }
            2 { 'AC Connected' }
            3 { 'Fully Charged' }
            4 { 'Low' }
            5 { 'Critical' }
            6 { 'Charging' }
            7 { 'Charging - High' }
            8 { 'Charging - Low' }
            9 { 'Charging - Critical' }
            default { "Status $($item.BatteryStatus)" }
        }

        # Chemistry mapping
        $chemistryText = switch ($item.Chemistry) {
            1 { 'Other' }
            2 { 'Unknown' }
            3 { 'Lead Acid' }
            4 { 'Nickel Cadmium' }
            5 { 'Nickel Metal Hydride' }
            6 { 'Lithium-ion' }
            7 { 'Zinc Air' }
            8 { 'Lithium Polymer' }
            default { 'Unknown' }
        }

        [void]$batteryReports.Add([pscustomobject]@{
            Name                     = $item.Name
            Status                   = $statusText
            EstimatedChargeRemaining = $item.EstimatedChargeRemaining
            EstimatedRunTimeMinutes  = $item.EstimatedRunTime
            DesignCapacity           = $designCapacity
            CurrentFullChargeCapacity = $fullCapacity
            WearLevelPercent         = $wearLevel
            EstimatedHealthPercent   = $health
            CycleCount               = $cycleCount
            Chemistry                = $chemistryText
            Manufacturer             = if ($matchDesign) { $matchDesign.ManufactureName } else { $null }
            SerialNumber             = if ($matchDesign) { $matchDesign.SerialNumber } else { $null }
        })
    }

    # ── Scoring ──────────────────────────────────────────────
    $lowestHealth = ($batteryReports | Where-Object { $_.EstimatedHealthPercent } |
        Measure-Object -Property EstimatedHealthPercent -Minimum).Minimum

    $score = if ($lowestHealth) { [int]$lowestHealth } else { 80 }

    # Deductions
    if ($lowestHealth -and $lowestHealth -lt 50) {
        $score = [math]::Min($score, 40)
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority High -Category Battery `
            -Problem 'Battery capacity severely degraded' `
            -Reason ("Battery health is {0:n1}%, less than half of design capacity." -f $lowestHealth) `
            -Risk 'Very limited unplugged runtime, possible unexpected shutdowns.' `
            -SuggestedFix 'Consider battery replacement through vendor support.' `
            -EstimatedImprovement '+30 to +50 battery score'))
    }
    elseif ($lowestHealth -and $lowestHealth -lt 70) {
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Medium -Category Battery `
            -Problem 'Battery capacity degraded' `
            -Reason ("Battery health is {0:n1}%." -f $lowestHealth) `
            -Risk 'Reduced unplugged runtime and possible performance throttling.' `
            -SuggestedFix 'Monitor battery health; consider replacement if runtime affects work.' `
            -EstimatedImprovement '+10 to +20 battery score'))
    }

    if ($cycleCount -and $cycleCount -gt 800) {
        [void]$recommendations.Add((New-AnalyzerRecommendation `
            -Priority Low -Category Battery `
            -Problem ("High battery cycle count: $cycleCount") `
            -Reason 'Lithium-ion batteries typically degrade significantly after 500-1000 cycles.' `
            -Risk 'Continued capacity loss is expected.' `
            -SuggestedFix 'Plan for eventual battery replacement.' `
            -EstimatedImprovement 'Awareness — no immediate score change'))
    }

    [pscustomobject]@{
        Score           = [int](Limit-Number -Value $score -Minimum 0 -Maximum 100)
        Present         = $true
        Batteries       = @($batteryReports)
        ChargingHistory = $chargingHistory
        Recommendations = @($recommendations)
    }
}

Export-ModuleMember -Function Get-BatteryReport
