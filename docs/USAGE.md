# Usage Guide

## Full scan

```powershell
.\Run-HealthAnalyzer.ps1
```

## Quiet scan

```powershell
.\Run-HealthAnalyzer.ps1 -Quiet
```

## Skip slow or irrelevant sections

```powershell
.\Run-HealthAnalyzer.ps1 -SkipEventLogs
.\Run-HealthAnalyzer.ps1 -SkipBattery
.\Run-HealthAnalyzer.ps1 -SkipBattery -SkipEventLogs -QuickScan
```

## JSON-only style run

```powershell
.\Run-HealthAnalyzer.ps1 -NoHtml -Quiet
```

## Custom output directory

```powershell
.\Run-HealthAnalyzer.ps1 -OutputDirectory C:\Temp\DevHealthReport
```

## Reading recommendations

Open `Reports\Recommendations.json` or the Recommendations section of `HealthReport.html`. Each item includes priority, problem, reason, risk, suggested fix, and estimated improvement.

## Cleanup Advisor

The Cleanup Advisor estimates reclaimable space but never deletes anything. Treat `Review before deleting` as a manual review queue, especially for package caches, Maven local repositories, Downloads, archives, installers, SDKs, and `node_modules` folders.

## Quick scan

Use `-QuickScan` for smoke tests or lightweight checks. Full scans remain the default and perform broader recursive sizing.
