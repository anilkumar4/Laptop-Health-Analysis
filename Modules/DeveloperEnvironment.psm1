Set-StrictMode -Version Latest

function Get-InstalledApplicationMatches {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Pattern)

    $roots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $roots) {
        Get-ItemProperty $root -ErrorAction SilentlyContinue |
            Where-Object { $null -ne $_.PSObject.Properties['DisplayName'] -and $_.PSObject.Properties['DisplayName'].Value -match $Pattern } |
            Select-Object @{N='DisplayName';E={$_.DisplayName}}, @{N='DisplayVersion';E={$_.DisplayVersion}}, @{N='InstallLocation';E={$_.InstallLocation}}, @{N='Publisher';E={$_.Publisher}}
    }
}

function New-DeveloperFolderTarget {
    param([string]$Name, [string]$Path, [string]$Category)
    [pscustomobject]@{ Name = $Name; Path = $Path; Category = $Category }
}

function Get-DeveloperEnvironmentReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][scriptblock]$Log, [Parameter()][switch]$QuickScan)

    $recommendations = New-Object System.Collections.ArrayList
    $home = $env:USERPROFILE
    $local = $env:LOCALAPPDATA
    $roaming = $env:APPDATA
    $programFiles = ${env:ProgramFiles}
    $programFilesX86 = ${env:ProgramFiles(x86)}

    $tools = @(
        @{ Name='Java'; Commands=@('java'); Arg='-version'; Registry='Java|JDK|OpenJDK' },
        @{ Name='Python'; Commands=@('python','py'); Arg='--version'; Registry='Python' },
        @{ Name='Node'; Commands=@('node'); Arg='--version'; Registry='Node.js' },
        @{ Name='npm'; Commands=@('npm'); Arg='--version'; Registry='npm' },
        @{ Name='pnpm'; Commands=@('pnpm'); Arg='--version'; Registry='pnpm' },
        @{ Name='yarn'; Commands=@('yarn'); Arg='--version'; Registry='Yarn' },
        @{ Name='Maven'; Commands=@('mvn'); Arg='--version'; Registry='Maven' },
        @{ Name='Gradle'; Commands=@('gradle'); Arg='--version'; Registry='Gradle' },
        @{ Name='Git'; Commands=@('git'); Arg='--version'; Registry='Git' },
        @{ Name='Docker'; Commands=@('docker'); Arg='--version'; Registry='Docker' },
        @{ Name='WSL'; Commands=@('wsl'); Arg='--version'; Registry='Windows Subsystem for Linux' },
        @{ Name='VS Code'; Commands=@('code'); Arg='--version'; Registry='Visual Studio Code' },
        @{ Name='Cursor'; Commands=@('cursor'); Arg='--version'; Registry='Cursor' },
        @{ Name='Claude Code'; Commands=@('claude'); Arg='--version'; Registry='Claude' },
        @{ Name='Codex CLI'; Commands=@('codex'); Arg='--version'; Registry='Codex' },
        @{ Name='Gemini CLI'; Commands=@('gemini'); Arg='--version'; Registry='Gemini' },
        @{ Name='LM Studio'; Commands=@('lms'); Arg='--version'; Registry='LM Studio' },
        @{ Name='Ollama'; Commands=@('ollama'); Arg='--version'; Registry='Ollama' },
        @{ Name='Aider'; Commands=@('aider'); Arg='--version'; Registry='Aider' },
        @{ Name='OpenCode'; Commands=@('opencode'); Arg='--version'; Registry='OpenCode' },
        @{ Name='Trae'; Commands=@('trae'); Arg='--version'; Registry='Trae' },
        @{ Name='Conda'; Commands=@('conda'); Arg='--version'; Registry='Anaconda|Miniconda|Conda' },
        @{ Name='Anaconda'; Commands=@('anaconda-navigator'); Arg='--version'; Registry='Anaconda' },
        @{ Name='Android Studio'; Commands=@('studio64'); Arg='--version'; Registry='Android Studio' },
        @{ Name='Eclipse'; Commands=@('eclipse'); Arg='--version'; Registry='Eclipse' },
        @{ Name='IntelliJ IDEA'; Commands=@('idea64'); Arg='--version'; Registry='IntelliJ' },
        @{ Name='PyCharm'; Commands=@('pycharm64'); Arg='--version'; Registry='PyCharm' },
        @{ Name='Visual Studio'; Commands=@('devenv'); Arg='/SafeMode'; Registry='Visual Studio' }
    )

    $detections = New-Object System.Collections.ArrayList
    foreach ($tool in $tools) {
        $detected = Get-CommandDetection -Name $tool.Name -Commands $tool.Commands -VersionArgument $tool.Arg -Log $Log
        $registry = @(Get-InstalledApplicationMatches -Pattern $tool.Registry | Select-Object -First 3)
        if (-not $detected.Installed -and $registry.Count -gt 0) {
            $detected = [pscustomobject]@{ Name=$tool.Name; Installed=$true; Version=$registry[0].DisplayVersion; Path=$registry[0].InstallLocation; Detection='Registry' }
        }
        $diskUsage = 0L
        if ((-not $QuickScan) -and $detected.Path -and (Test-Path -LiteralPath $detected.Path)) {
            $pathForSize = if ((Get-Item -LiteralPath $detected.Path -ErrorAction SilentlyContinue).PSIsContainer) { $detected.Path } else { Split-Path -Parent $detected.Path }
            if ($pathForSize -and (Test-Path -LiteralPath $pathForSize)) { $diskUsage = (Get-FolderSizeInfo -Path $pathForSize -Log $Log).SizeBytes }
        }
        [void]$detections.Add([pscustomobject]@{
            Name = $detected.Name
            Installed = $detected.Installed
            Version = $detected.Version
            Path = $detected.Path
            Detection = $detected.Detection
            DiskUsageBytes = $diskUsage
            DiskUsage = ConvertTo-SizeString $diskUsage
            RegistryMatches = $registry
        })
    }

    $folderTargets = @(
        New-DeveloperFolderTarget '.m2' (Join-Path $home '.m2') 'Maven',
        New-DeveloperFolderTarget '.gradle' (Join-Path $home '.gradle') 'Gradle',
        New-DeveloperFolderTarget '.vscode' (Join-Path $home '.vscode') 'VS Code',
        New-DeveloperFolderTarget '.cursor' (Join-Path $home '.cursor') 'Cursor',
        New-DeveloperFolderTarget '.codex' (Join-Path $home '.codex') 'AI Tools',
        New-DeveloperFolderTarget '.trae' (Join-Path $home '.trae') 'AI Tools',
        New-DeveloperFolderTarget '.claude' (Join-Path $home '.claude') 'AI Tools',
        New-DeveloperFolderTarget '.gemini' (Join-Path $home '.gemini') 'AI Tools',
        New-DeveloperFolderTarget '.lmstudio' (Join-Path $home '.lmstudio') 'AI Tools',
        New-DeveloperFolderTarget '.conda' (Join-Path $home '.conda') 'Python',
        New-DeveloperFolderTarget '.anaconda' (Join-Path $home '.anaconda') 'Python',
        New-DeveloperFolderTarget 'Android SDK' (Join-Path $local 'Android\Sdk') 'Android',
        New-DeveloperFolderTarget 'Eclipse' (Join-Path $home 'eclipse') 'Java',
        New-DeveloperFolderTarget '.p2' (Join-Path $home '.p2') 'Eclipse',
        New-DeveloperFolderTarget 'JetBrains' (Join-Path $roaming 'JetBrains') 'JetBrains',
        New-DeveloperFolderTarget 'VS Code cache' (Join-Path $roaming 'Code\Cache') 'Cache',
        New-DeveloperFolderTarget 'Cursor cache' (Join-Path $roaming 'Cursor\Cache') 'Cache',
        New-DeveloperFolderTarget 'IntelliJ cache' (Join-Path $local 'JetBrains\IntelliJIdea*') 'Cache',
        New-DeveloperFolderTarget 'PyCharm cache' (Join-Path $local 'JetBrains\PyCharm*') 'Cache',
        New-DeveloperFolderTarget 'Downloads' (Join-Path $home 'Downloads') 'User',
        New-DeveloperFolderTarget 'Desktop' (Join-Path $home 'Desktop') 'User',
        New-DeveloperFolderTarget 'Documents' (Join-Path $home 'Documents') 'User',
        New-DeveloperFolderTarget 'OneDrive' (Join-Path $home 'OneDrive') 'User',
        New-DeveloperFolderTarget 'AppData Local' $local 'AppData',
        New-DeveloperFolderTarget 'AppData Roaming' $roaming 'AppData'
    )

    if ($QuickScan) {
        $folderTargets = @($folderTargets | Where-Object { $_.Category -notin @('AppData','User') -or $_.Name -in @('Downloads','Desktop') })
    }

    $folders = New-Object System.Collections.ArrayList
    foreach ($target in $folderTargets) {
        $paths = @(Resolve-Path -Path $target.Path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path)
        if ($paths.Count -eq 0) { $paths = @($target.Path) }
        foreach ($path in $paths) {
            $size = Get-FolderSizeInfo -Path $path -Log $Log
            [void]$folders.Add([pscustomobject]@{ Name=$target.Name; Category=$target.Category; Path=$size.Path; Exists=$size.Exists; SizeBytes=$size.SizeBytes; SizeGB=$size.SizeGB; FileCount=$size.FileCount; DirectoryCount=$size.DirectoryCount })
        }
    }

    $installedCount = @($detections | Where-Object Installed).Count
    $score = [math]::Min(100, 50 + ($installedCount * 2))
    $hugeCaches = @($folders | Where-Object { $_.Category -eq 'Cache' -and $_.SizeBytes -gt 5GB })
    if ($hugeCaches.Count -gt 0) {
        $score -= 10
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority Medium -Category 'Developer Environment' -Problem 'Large developer caches detected' -Reason 'One or more editor or IDE caches exceed 5 GB.' -Risk 'Large caches can consume SSD space and slow backup/indexing workflows.' -SuggestedFix 'Review cache folders in Cleanup Advisor before deleting anything.' -EstimatedImprovement '+5 storage/developer score'))
    }

    $wslDistros = @(Invoke-SafeCommand -Log $Log -Context 'WSL distributions' -Default @() -ScriptBlock {
        $wslOutput = & wsl --list --quiet 2>$null
        if ($wslOutput) {
            @($wslOutput | Where-Object { $_ -and $_.Trim() }) | ForEach-Object {
                [pscustomobject]@{ Name = $_.Trim(); Source = 'WSL' }
            }
        }
    })

    [pscustomobject]@{
        Score = [int](Limit-Number -Value $score -Minimum 0 -Maximum 100)
        Tools = @($detections)
        Folders = @($folders | Sort-Object SizeBytes -Descending)
        InstalledToolCount = $installedCount
        WSL = @($wslDistros)
        Recommendations = @($recommendations)
    }
}

Export-ModuleMember -Function Get-DeveloperEnvironmentReport

