Set-StrictMode -Version Latest

function Get-StartupReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][scriptblock]$Log)

    $recommendations = New-Object System.Collections.ArrayList
    $startupCommands = @(Invoke-SafeCommand -Log $Log -Context 'startup commands' -Default @() -ScriptBlock { Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User })
    $autoServices = @(Invoke-SafeCommand -Log $Log -Context 'automatic services' -Default @() -ScriptBlock { Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' } | Select-Object Name, DisplayName, State, StartMode, StartName, PathName })
    $scheduledTasks = @(Invoke-SafeCommand -Log $Log -Context 'scheduled tasks' -Default @() -ScriptBlock {
        Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and $_.Triggers } | Select-Object -First 300 TaskName, TaskPath, State, Author
    })
    $bootEvents = @(Invoke-SafeCommand -Log $Log -Context 'boot performance events' -Default @() -ScriptBlock {
        Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-Diagnostics-Performance/Operational'; Id=100; StartTime=(Get-Date).AddDays(-30) } -ErrorAction Stop |
            Select-Object -First 20 TimeCreated, Id, Message
    })
    $fastStartup = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled'

    $bootDurations = New-Object System.Collections.ArrayList
    foreach ($event in $bootEvents) {
        $duration = $null
        if ($event.Message -match 'Boot Duration\s*:\s*(\d+)') { $duration = [int]$matches[1] }
        [void]$bootDurations.Add([pscustomobject]@{ TimeCreated = $event.TimeCreated; BootDurationMs = $duration; BootDurationSeconds = if ($duration) { [math]::Round($duration / 1000, 1) } else { $null } })
    }
    $measuredBoot = @($bootDurations | Where-Object { $null -ne $_.BootDurationMs })
    $averageBootSeconds = $null
    if ($measuredBoot.Count -gt 0) {
        $measured = $measuredBoot | Measure-Object -Property BootDurationMs -Average
        if ($null -ne $measured -and $null -ne $measured.Average) {
            $averageBootSeconds = [math]::Round($measured.Average / 1000, 1)
        }
    }

    $score = 100
    if ($startupCommands.Count -gt 20) {
        $score -= 10
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority Medium -Category Startup -Problem 'Many startup applications are registered' -Reason ("{0} startup commands were found." -f $startupCommands.Count) -Risk 'Login and boot responsiveness can suffer.' -SuggestedFix 'Review Startup Apps and disable nonessential launchers.' -EstimatedImprovement '+5 startup score'))
    }
    if ($averageBootSeconds -gt 90) {
        $score -= 20
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority Medium -Category Startup -Problem 'Slow boot performance' -Reason ("Average boot duration is about {0:n1} seconds." -f $averageBootSeconds) -Risk 'Slow boot can indicate driver, service, or disk issues.' -SuggestedFix 'Review boot performance events, startup commands, and delayed services.' -EstimatedImprovement '+10 performance score'))
    }

    [pscustomobject]@{
        Score = [int](Limit-Number -Value $score -Minimum 0 -Maximum 100)
        BootTimeSecondsAverage = $averageBootSeconds
        BootEvents = @($bootDurations)
        FastStartup = [pscustomobject]@{ RegistryValue = $fastStartup; Enabled = ($fastStartup -eq 1) }
        StartupApplications = $startupCommands
        Services = $autoServices
        ScheduledTasks = $scheduledTasks
        DelayedStartup = @($autoServices | Where-Object { $_.PathName -match 'delayed|DelayedAutoStart' })
        StartupImpact = 'Windows exposes detailed startup impact primarily through shell telemetry. This report lists launch points for manual review.'
        Recommendations = @($recommendations)
    }
}

Export-ModuleMember -Function Get-StartupReport
