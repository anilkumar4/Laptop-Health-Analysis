Set-StrictMode -Version Latest

function Invoke-AnalyzerLog {
    [CmdletBinding()]
    param(
        [Parameter()][scriptblock]$Log,
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][ValidateSet('DEBUG','INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO'
    )
    if ($Log) { & $Log -Message $Message -Level $Level }
}

function Invoke-SafeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter()]$Default = $null,
        [Parameter()][scriptblock]$Log,
        [Parameter()][string]$Context = 'command'
    )
    try { return & $ScriptBlock }
    catch {
        Invoke-AnalyzerLog -Log $Log -Level 'DEBUG' -Message ("{0} failed: {1}" -f $Context, $_.Exception.Message)
        return $Default
    }
}

function Limit-Number {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][double]$Minimum,
        [Parameter(Mandatory)][double]$Maximum
    )
    return [math]::Max($Minimum, [math]::Min($Maximum, $Value))
}

function ConvertTo-SizeString {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][Nullable[double]]$Bytes)
    if ($null -eq $Bytes) { return 'Unknown' }
    if ($Bytes -ge 1TB) { return ('{0:n2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:n2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:n1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:n0} KB' -f ($Bytes / 1KB)) }
    return ('{0:n0} B' -f $Bytes)
}

function Get-FolderSizeInfo {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][scriptblock]$Log
    )

    $resolved = $null
    try { $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop }
    catch {
        return [pscustomobject]@{ Path = $Path; Exists = $false; SizeBytes = 0L; SizeGB = 0; FileCount = 0; DirectoryCount = 0; Error = $_.Exception.Message }
    }

    $bytes = [int64]0
    $files = 0
    $directories = 0
    try {
        Get-ChildItem -LiteralPath $resolved.Path -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.PSIsContainer) { $directories++ } else { $files++; $bytes += [int64]$_.Length }
        }
        return [pscustomobject]@{ Path = $resolved.Path; Exists = $true; SizeBytes = $bytes; SizeGB = [math]::Round($bytes / 1GB, 3); FileCount = $files; DirectoryCount = $directories; Error = $null }
    }
    catch {
        Invoke-AnalyzerLog -Log $Log -Level 'DEBUG' -Message ("Folder size scan failed for {0}: {1}" -f $Path, $_.Exception.Message)
        return [pscustomobject]@{ Path = $resolved.Path; Exists = $true; SizeBytes = $bytes; SizeGB = [math]::Round($bytes / 1GB, 3); FileCount = $files; DirectoryCount = $directories; Error = $_.Exception.Message }
    }
}

function Get-CommandDetection {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Commands,
        [Parameter()][string]$VersionArgument = '--version',
        [Parameter()][scriptblock]$Log
    )

    foreach ($commandName in $Commands) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            $version = $null
            try {
                $versionText = & $command.Source $VersionArgument 2>$null | Select-Object -First 1
                if ($versionText) { $version = ($versionText | Out-String).Trim() }
            }
            catch { Invoke-AnalyzerLog -Log $Log -Level 'DEBUG' -Message ("Version probe failed for {0}: {1}" -f $Name, $_.Exception.Message) }
            return [pscustomobject]@{ Name = $Name; Installed = $true; Version = $version; Path = $command.Source; Detection = 'PATH' }
        }
    }

    return [pscustomobject]@{ Name = $Name; Installed = $false; Version = $null; Path = $null; Detection = 'Not found' }
}

function New-AnalyzerRecommendation {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidateSet('Critical','High','Medium','Low')][string]$Priority,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Problem,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string]$Risk,
        [Parameter(Mandatory)][string]$SuggestedFix,
        [Parameter(Mandatory)][string]$EstimatedImprovement
    )
    [pscustomobject]@{
        Priority = $Priority
        Category = $Category
        Problem = $Problem
        Reason = $Reason
        Risk = $Risk
        SuggestedFix = $SuggestedFix
        EstimatedImprovement = $EstimatedImprovement
    }
}

function Get-SafeScore {
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter()]$Value, [Parameter()][int]$Default = 50)
    if ($null -eq $Value) { return $Default }
    try { return [int](Limit-Number -Value ([double]$Value) -Minimum 0 -Maximum 100) }
    catch { return $Default }
}

function Get-ObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()]$Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-SkippedReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter()][int]$DefaultScore = 100)
    [pscustomobject]@{ Score = $DefaultScore; Skipped = $true; Name = $Name; Recommendations = @() }
}

function Get-RegistryValueSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name }
    catch { return $null }
}

Export-ModuleMember -Function *
