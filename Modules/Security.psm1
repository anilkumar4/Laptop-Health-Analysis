Set-StrictMode -Version Latest

function Get-SecurityReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][scriptblock]$Log)

    $recommendations = New-Object System.Collections.ArrayList
    $score = 100
    $firewall = Invoke-SafeCommand -Log $Log -Context 'firewall profiles' -Default @() -ScriptBlock { Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction }
    $tpm = Invoke-SafeCommand -Log $Log -Context 'TPM' -ScriptBlock { Get-Tpm }
    $secureBoot = Invoke-SafeCommand -Log $Log -Context 'Secure Boot' -ScriptBlock { Confirm-SecureBootUEFI }
    $defender = Invoke-SafeCommand -Log $Log -Context 'Defender' -ScriptBlock { Get-MpComputerStatus }
    $bitLocker = Invoke-SafeCommand -Log $Log -Context 'BitLocker' -Default @() -ScriptBlock { Get-BitLockerVolume | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage, EncryptionMethod }
    $uac = Get-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA'
    $credentialGuard = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LsaCfgFlags'
    $memoryIntegrity = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled'
    $coreIsolation = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity'
    $virtualization = Invoke-SafeCommand -Log $Log -Context 'virtualization' -ScriptBlock { (Get-CimInstance Win32_ComputerSystem).HypervisorPresent }
    $bitdefenderServices = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'bd|bitdefender' -or $_.DisplayName -match 'Bitdefender' } | Select-Object Name, DisplayName, Status)

    if (@($firewall | Where-Object { -not $_.Enabled }).Count -gt 0) {
        $score -= 20
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority High -Category Security -Problem 'One or more firewall profiles are disabled' -Reason 'Windows Firewall is not enabled for every network profile.' -Risk 'Developer machines often expose local services, containers, databases, and test endpoints.' -SuggestedFix 'Enable firewall profiles or confirm equivalent enterprise controls.' -EstimatedImprovement '+10 to +20 security score'))
    }
    if ($defender -and -not $defender.RealTimeProtectionEnabled) {
        $score -= 20
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority High -Category Security -Problem 'Defender real-time protection is disabled' -Reason 'Real-time malware scanning is currently off.' -Risk 'Package managers and cloned repositories increase exposure to malicious artifacts.' -SuggestedFix 'Enable Defender real-time protection or verify managed endpoint protection.' -EstimatedImprovement '+15 security score'))
    }
    if ($uac -ne 1) {
        $score -= 15
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority Medium -Category Security -Problem 'UAC appears disabled' -Reason 'EnableLUA is not set to 1.' -Risk 'Administrative prompts and app isolation are weakened.' -SuggestedFix 'Enable UAC unless intentionally controlled by policy.' -EstimatedImprovement '+5 to +10 security score'))
    }
    if ($secureBoot -eq $false) {
        $score -= 10
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority Medium -Category Security -Problem 'Secure Boot is disabled' -Reason 'Firmware is not enforcing trusted boot.' -Risk 'Boot-chain compromise protections are reduced.' -SuggestedFix 'Enable Secure Boot in firmware if compatible with your boot configuration.' -EstimatedImprovement '+5 security score'))
    }
    if ($memoryIntegrity -ne 1) {
        $score -= 5
        [void]$recommendations.Add((New-AnalyzerRecommendation -Priority Low -Category Security -Problem 'Memory Integrity is not enabled' -Reason 'Hypervisor-protected code integrity is off or unavailable.' -Risk 'Kernel-mode exploit resistance is lower.' -SuggestedFix 'Review Windows Security > Device security > Core isolation.' -EstimatedImprovement '+3 security score'))
    }

    [pscustomobject]@{
        Score = [int](Limit-Number -Value $score -Minimum 0 -Maximum 100)
        Firewall = @($firewall)
        TPM = $tpm
        SecureBoot = $secureBoot
        Defender = if ($defender) { $defender | Select-Object AMServiceEnabled, AntivirusEnabled, AntispywareEnabled, RealTimeProtectionEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, NISEnabled, QuickScanAge, FullScanAge, AntivirusSignatureLastUpdated } else { $null }
        Bitdefender = [pscustomobject]@{ Installed = ($bitdefenderServices.Count -gt 0); Services = $bitdefenderServices }
        UAC = [pscustomobject]@{ EnableLUA = $uac; Enabled = ($uac -eq 1) }
        CredentialGuard = [pscustomobject]@{ RawValue = $credentialGuard; Enabled = ($credentialGuard -gt 0) }
        CoreIsolation = [pscustomobject]@{ VirtualizationBasedSecurity = $coreIsolation; MemoryIntegrity = $memoryIntegrity }
        BitLocker = @($bitLocker)
        Virtualization = [pscustomobject]@{ HypervisorPresent = $virtualization }
        StorageSpaces = Invoke-SafeCommand -Log $Log -Context 'Storage Spaces' -Default @() -ScriptBlock { Get-StoragePool -ErrorAction Stop | Select-Object FriendlyName, HealthStatus, OperationalStatus, IsPrimordial }
        Recommendations = @($recommendations)
    }
}

Export-ModuleMember -Function Get-SecurityReport
