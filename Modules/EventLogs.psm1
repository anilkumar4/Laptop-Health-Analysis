Set-StrictMode -Version Latest

function Get-EventLogReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][scriptblock]$Log)

    $recommendations = New-Object System.Collections.ArrayList
    $since = (Get-Date).AddDays(-30)
    $critical = @(Invoke-SafeCommand -Log $Log -Context 'critical system/application events' -Default @() -ScriptBlock {
        Get-WinEvent -FilterHashtable @{ LogName = @('System','Application'); Level = 1; StartTime = $since } -ErrorAction Stop |
            Select-Object -First 200 TimeCreated, ProviderName, Id, LevelDisplayName, Message, LogName
    })
    $errors = @(Invoke-SafeCommand -Log $Log -Context 'error system/application events' -Default @() -ScriptBlock {
        Get-WinEvent -FilterHashtable @{ LogName = @('System','Application'); Level = 2; StartTime = $since } -ErrorAction Stop |
            Select-Object -First 500 TimeCreated, ProviderName, Id, LevelDisplayName, Message, LogName
    })
    $shutdowns = @(Invoke-SafeCommand -Log $Log -Context 'unexpected shutdowns' -Default @() -ScriptBlock {
        Get-WinEvent -FilterHashtable @{ LogName='System'; Id=@(41,6008); StartTime=$since } -ErrorAction Stop |
            Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message
    })
    $driverFailures = @(Invoke-SafeCommand -Log $Log -Context 'driver failures' -Default @() -ScriptBlock {
        Get-WinEvent -FilterHashtable @{ LogName='System'; Level=2; StartTime=$since } -ErrorAction Stop |
            Where-Object { $_.ProviderName -match 'Driver|Kernel|WHEA|Display|Disk|Ntfs|stor' -or $_.Message -match 'driver|device|disk|controller' } |
            Select-Object -First 100 TimeCreated, ProviderName, Id, LevelDisplayName, Message
    })
    $bsod = @(Invoke-SafeCommand -Log $Log -Context 'BSOD events' -Default @() -ScriptBlock {
        Get-WinEvent -FilterHashtable @{ LogName='System'; Id=@(1001); StartTime=$since } -ErrorAction Stop |
            Where-Object { $_.ProviderName -match 'BugCheck|Windows Error Reporting' -or $_.Message -match 'bugcheck|blue screen' } |
            Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message
    })

    $score = 100
    if ($critical.Count -gt 0) {
        $score -= [math]::Min(30, $critical.Count * 5)
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority High -Category 'Event Logs' -Problem 'Critical events found' -Reason ("{0} critical events were found in the last 30 days." -f $critical.Count) -Risk 'Critical event patterns can indicate driver, hardware, power, or OS instability.' -SuggestedFix 'Review event details and address recurring provider names first.' -EstimatedImprovement '+5 to +20 Windows score'))
    }
    if ($shutdowns.Count -gt 0) {
        $score -= [math]::Min(20, $shutdowns.Count * 4)
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority High -Category 'Event Logs' -Problem 'Unexpected shutdown history' -Reason ("{0} shutdown/power-loss events were found." -f $shutdowns.Count) -Risk 'Unexpected shutdowns can corrupt repos, containers, databases, and package caches.' -SuggestedFix 'Check power, thermals, firmware, and recent driver updates.' -EstimatedImprovement '+10 stability improvement'))
    }
    if ($bsod.Count -gt 0) {
        $score -= 20
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority Critical -Category 'Event Logs' -Problem 'Bugcheck events found' -Reason 'Windows recorded one or more bugcheck events.' -Risk 'BSODs usually indicate kernel, driver, firmware, or hardware faults.' -SuggestedFix 'Analyze memory dumps and update suspect drivers or firmware.' -EstimatedImprovement 'High reliability improvement'))
    }

    $timelineEvents = @($critical) + @($errors)
    $timeline = @()
    if ($timelineEvents.Count -gt 0) {
        $timeline = @($timelineEvents |
            Where-Object { $null -ne $_.TimeCreated } |
            Group-Object { $_.TimeCreated.ToString('yyyy-MM-dd') } |
            Sort-Object Name |
            ForEach-Object { [pscustomobject]@{ Date = $_.Name; Count = $_.Count } })
    }
    [pscustomobject]@{
        Score = [int](Limit-Number -Value $score -Minimum 0 -Maximum 100)
        CriticalEvents = $critical
        ErrorSample = @($errors | Select-Object -First 100)
        UnexpectedShutdowns = $shutdowns
        DriverFailures = $driverFailures
        BsodHistory = $bsod
        EventTimeline = $timeline
        Recommendations = @($recommendations)
    }
}

Export-ModuleMember -Function Get-EventLogReport
