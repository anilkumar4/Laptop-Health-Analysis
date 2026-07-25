# Installation Guide

## Install from source

Clone or download the repository, then run from the project directory:

```powershell
cd DeveloperHealthAnalyzer
.\Run-HealthAnalyzer.ps1
```

No installation step is required.

## Execution policy

If Windows blocks the script, inspect it first, then run one of these from the project directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\Run-HealthAnalyzer.ps1
```

or with PowerShell 7:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Run-HealthAnalyzer.ps1
```

## Administrator mode

Administrator mode is recommended for full BitLocker, firmware, event log, Defender, and security posture checks. Non-admin scans still produce useful results but may mark some data as unavailable.
