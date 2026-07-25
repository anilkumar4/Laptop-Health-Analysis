Set-StrictMode -Version Latest

function New-CleanupFinding {
    param([string]$Name, [string]$Path, [string]$Category, [string]$Safety, [string]$Reason, [scriptblock]$Log)
    $size = Get-FolderSizeInfo -Path $Path -Log $Log
    [pscustomobject]@{
        Name = $Name
        Path = $size.Path
        Exists = $size.Exists
        SizeBytes = $size.SizeBytes
        SizeGB = $size.SizeGB
        ReclaimableBytes = if ($Safety -eq 'Never delete') { 0L } else { $size.SizeBytes }
        Reclaimable = if ($Safety -eq 'Never delete') { '0 B' } else { ConvertTo-SizeString $size.SizeBytes }
        Category = $Category
        Safety = $Safety
        Reason = $Reason
    }
}

function Get-CleanupReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]$DeveloperEnvironment,
        [Parameter()]$Storage,
        [Parameter()][scriptblock]$Log,
        [Parameter()][switch]$QuickScan
    )

    $home = $env:USERPROFILE
    $local = $env:LOCALAPPDATA
    $roaming = $env:APPDATA
    $findings = New-Object System.Collections.ArrayList

    $targets = @(
        @{ Name='User temp'; Path=$env:TEMP; Category='Temp'; Safety='Safe to delete'; Reason='Usually disposable application temp files. Close apps first.' },
        @{ Name='Windows temp'; Path=(Join-Path $env:WINDIR 'Temp'); Category='Temp'; Safety='Review before deleting'; Reason='Windows and installers may hold active temp files.' },
        @{ Name='npm cache'; Path=(Join-Path $roaming 'npm-cache'); Category='Package cache'; Safety='Safe to delete'; Reason='npm can rebuild this cache.' },
        @{ Name='pip cache'; Path=(Join-Path $local 'pip\Cache'); Category='Package cache'; Safety='Safe to delete'; Reason='pip can redownload cached wheels.' },
        @{ Name='NuGet cache'; Path=(Join-Path $home '.nuget\packages'); Category='Package cache'; Safety='Review before deleting'; Reason='Projects may restore packages later; deleting saves space but costs network/time.' },
        @{ Name='Gradle cache'; Path=(Join-Path $home '.gradle\caches'); Category='Package cache'; Safety='Review before deleting'; Reason='Gradle can rebuild caches, but first build after deletion is slower.' },
        @{ Name='Maven repository'; Path=(Join-Path $home '.m2\repository'); Category='Package cache'; Safety='Review before deleting'; Reason='Maven dependencies can be restored, but local snapshots may matter.' },
        @{ Name='VS Code cache'; Path=(Join-Path $roaming 'Code\Cache'); Category='Editor cache'; Safety='Safe to delete'; Reason='Editor cache can be rebuilt.' },
        @{ Name='Cursor cache'; Path=(Join-Path $roaming 'Cursor\Cache'); Category='Editor cache'; Safety='Safe to delete'; Reason='Editor cache can be rebuilt.' },
        @{ Name='Browser cache'; Path=(Join-Path $local 'Google\Chrome\User Data\Default\Cache'); Category='Browser cache'; Safety='Safe to delete'; Reason='Browser cache is disposable.' },
        @{ Name='Downloads'; Path=(Join-Path $home 'Downloads'); Category='User files'; Safety='Review before deleting'; Reason='Downloads often contains installers, archives, and personal files.' },
        @{ Name='Documents'; Path=(Join-Path $home 'Documents'); Category='Protected'; Safety='Never delete'; Reason='Personal documents and source-adjacent files must not be recommended for deletion.' },
        @{ Name='OneDrive'; Path=(Join-Path $home 'OneDrive'); Category='Protected'; Safety='Never delete'; Reason='Cloud-synced files may be user data or business records.' }
    )

    foreach ($target in $targets) {
        [void]$findings.Add((New-CleanupFinding -Name $target.Name -Path $target.Path -Category $target.Category -Safety $target.Safety -Reason $target.Reason -Log $Log))
    }

    $largeInstallers = @()
    $nodeModules = @()
    if (-not $QuickScan) {
        foreach ($folder in @((Join-Path $home 'Downloads'), (Join-Path $home 'Desktop'))) {
            if (Test-Path -LiteralPath $folder) {
                $largeInstallers += @(Get-ChildItem -LiteralPath $folder -File -Force -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -gt 500MB -and $_.Extension -match '\.(iso|zip|7z|msi|exe)$' } |
                    Select-Object FullName, Extension, @{N='SizeBytes';E={[int64]$_.Length}}, @{N='SizeGB';E={[math]::Round($_.Length / 1GB, 3)}}, LastWriteTime)
            }
        }

        foreach ($root in @((Join-Path $home 'source'), (Join-Path $home 'repos'), (Join-Path $home 'Projects'), (Join-Path $home 'Documents'))) {
            if (Test-Path -LiteralPath $root) {
                $nodeModules += @(Get-ChildItem -LiteralPath $root -Directory -Filter node_modules -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 100)
            }
        }
    }
    $nodeFindings = @($nodeModules | ForEach-Object { Get-FolderSizeInfo -Path $_.FullName -Log $Log } | Sort-Object SizeBytes -Descending)

    $findingsSum = $findings | Where-Object { $_.Safety -ne 'Never delete' } | Measure-Object -Property ReclaimableBytes -Sum
    $installersSum = $largeInstallers | Measure-Object -Property SizeBytes -Sum
    $nodeSum = $nodeFindings | Measure-Object -Property SizeBytes -Sum
    $reclaimable = 0L
    if ($null -ne $findingsSum -and $null -ne $findingsSum.Sum) { $reclaimable += [int64]$findingsSum.Sum }
    if ($null -ne $installersSum -and $null -ne $installersSum.Sum) { $reclaimable += [int64]$installersSum.Sum }
    if ($null -ne $nodeSum -and $null -ne $nodeSum.Sum) { $reclaimable += [int64]$nodeSum.Sum }

    $recommendations = New-Object System.Collections.ArrayList
    if ($reclaimable -gt 10GB) {
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority Medium -Category 'Cleanup Advisor' -Problem 'Large reclaimable space estimate' -Reason ("Estimated reviewable reclaimable space is {0}." -f (ConvertTo-SizeString $reclaimable)) -Risk 'Low free space can disrupt builds, package managers, Docker, and Windows Update.' -SuggestedFix 'Review safe and review-before-delete categories. The analyzer will not delete anything automatically.' -EstimatedImprovement '+5 to +15 storage score'))
    }
    if ($nodeFindings.Count -gt 5) {
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority Low -Category 'Cleanup Advisor' -Problem 'Multiple node_modules folders found' -Reason ("{0} node_modules directories were found under common project roots." -f $nodeFindings.Count) -Risk 'Dependency trees can consume substantial SSD space.' -SuggestedFix 'Review inactive projects manually before removing dependencies.' -EstimatedImprovement 'Potentially large storage recovery'))
    }

    [pscustomobject]@{
        Score = 100
        EstimatedReclaimableBytes = [int64]$reclaimable
        EstimatedReclaimable = ConvertTo-SizeString $reclaimable
        Findings = @($findings | Sort-Object ReclaimableBytes -Descending)
        LargeArchivesAndInstallers = @($largeInstallers | Sort-Object SizeBytes -Descending)
        DuplicateNodeModules = @($nodeFindings)
        SafetyRules = [pscustomobject]@{
            SafeToDelete = 'Disposable caches and temp locations after applications are closed.'
            ReviewBeforeDeleting = 'Regenerable content that may cost time/network or contain useful artifacts.'
            NeverDelete = 'Documents, projects, source code, Git repositories, OneDrive files, and developer project folders.'
        }
        Recommendations = @($recommendations)
    }
}

Export-ModuleMember -Function Get-CleanupReport



