# Architecture

## Overview

Developer Health Analyzer is a modular, read-only Windows diagnostics utility built in PowerShell. It follows a pipeline architecture: **scan → score → report**.

```
┌─────────────────────────────────────────────────────────────┐
│                    Run-HealthAnalyzer.ps1                    │
│                       (Orchestrator)                        │
├──────────┬──────────┬──────────┬──────────┬─────────────────┤
│  Import  │  Scan    │  Score   │  Report  │  Export         │
│  Modules │  Engine  │  Engine  │  Engine  │  Engine         │
└──────────┴────┬─────┴────┬─────┴────┬─────┴────┬────────────┘
                │          │          │          │
     ┌──────────▼──────────▼──┐  ┌────▼──────────▼────────┐
     │      9 Scan Modules    │  │    Report Generators    │
     │  (Parallel-capable)    │  │                         │
     │                        │  │  HtmlReport.psm1        │
     │  WindowsHealth.psm1    │  │  JSON serialization     │
     │  Storage.psm1          │  │  CSV export             │
     │  Performance.psm1      │  │                         │
     │  DeveloperEnv.psm1     │  │  Assets/                │
     │  Security.psm1         │  │    css/style.css        │
     │  Battery.psm1          │  │    js/dashboard.js      │
     │  EventLogs.psm1        │  │                         │
     │  Startup.psm1          │  └─────────────────────────┘
     │  CleanupAdvisor.psm1   │
     │                        │
     │  Common.psm1 (shared)  │
     └────────────────────────┘
```

## Module Contracts

Every scan module exports a single public function that returns a `[PSCustomObject]` with:

| Property | Type | Description |
|----------|------|-------------|
| `Score` | `[int]` | 0–100 health score for this category |
| `Recommendations` | `[array]` | Prioritized action items |
| `...` | varies | Category-specific data |

Each recommendation follows this schema:

```powershell
[PSCustomObject]@{
    Priority            = 'Critical' | 'High' | 'Medium' | 'Low'
    Category            = 'Storage' | 'Windows' | 'Performance' | ...
    Problem             = 'Human-readable problem description'
    Reason              = 'Why this was flagged'
    Risk                = 'What could go wrong'
    SuggestedFix        = 'Actionable remediation step'
    EstimatedImprovement = 'Expected score or stability gain'
}
```

## Scoring Engine

The orchestrator computes a weighted overall score:

| Category | Weight | Composite |
|----------|--------|-----------|
| Windows Health | 25% | 70% WindowsHealth + 30% EventLogs |
| Performance | 20% | 70% Performance + 30% Startup |
| Storage | 20% | Direct from Storage module |
| Security | 15% | Direct from Security module |
| Battery | 10% | Direct from Battery module (100 if desktop) |
| Developer Env | 10% | Direct from DeveloperEnvironment module |

All scores are clamped to 0–100 before weighting.

## Common Module

`Common.psm1` provides shared utilities used by all modules:

- `Invoke-SafeCommand` — try/catch wrapper with logging
- `Invoke-AnalyzerLog` — structured logging via callback scriptblock
- `Get-FolderSizeInfo` — recursive folder size calculation
- `Get-CommandDetection` — CLI tool detection with version probing
- `New-AnalyzerRecommendation` — typed recommendation factory
- `ConvertTo-SizeString` — bytes to human-readable format
- `Limit-Number` — clamp value to min/max range
- `Get-RegistryValueSafe` — safe registry read with null fallback

## Data Flow

```
1. Run-HealthAnalyzer.ps1
   ├── Import Common.psm1 (shared utilities)
   ├── Import all scan modules
   ├── Run each scan sequentially with progress
   │   └── Each module returns [PSCustomObject] with Score + Data + Recommendations
   ├── Calculate weighted health scores
   ├── Aggregate and sort all recommendations
   ├── Export:
   │   ├── HealthReport.json (complete data)
   │   ├── Recommendations.json (action items)
   │   ├── LargestFolders.csv
   │   ├── LargestFiles.csv
   │   └── HealthReport.html (self-contained dashboard)
   └── Display console summary
```

## HTML Report Architecture

The HTML report is a **single self-contained file** with:

- CSS inlined from `Assets/css/style.css`
- JavaScript inlined from `Assets/js/dashboard.js`
- Full report data embedded as JSON in a `<script type="application/json">` tag
- CDN references for Bootstrap 5.3, Chart.js 4, and Lucide icons

The JavaScript reads the embedded JSON and renders:
- Chart.js doughnut, bar, line, and radar charts
- Sortable tables with search
- Theme toggle (dark/light) with localStorage persistence
- CSV export buttons
- Score counter animations

## Safety Model

The analyzer is designed to be **completely read-only**:

1. **No file deletion** — even temp files are scoped to `$env:TEMP` and cleaned up
2. **No system modification** — no registry writes, no service changes
3. **No repair operations** — SFC/DISM results are read from existing logs
4. **No network modification** — DNS, proxy, and VPN are observed only
5. **Cleanup Advisor is advisory only** — classifies items but never acts

## Compatibility

- **PowerShell 5.1** (Windows PowerShell) — full support
- **PowerShell 7+** — full support
- **Windows 10** — all features
- **Windows 11** — all features
- **Non-admin** — most features work; some security, BitLocker, and event log queries may be limited

## Directory Structure

```
DeveloperHealthAnalyzer/
├── Run-HealthAnalyzer.ps1     # Entry point
├── Modules/
│   ├── Common.psm1            # Shared utilities
│   ├── WindowsHealth.psm1     # System info, updates, reboot, reliability
│   ├── Storage.psm1           # Drives, SMART, folders, files
│   ├── Performance.psm1       # CPU, RAM, processes, network
│   ├── DeveloperEnvironment.psm1  # Dev tools, folder sizes
│   ├── Security.psm1          # Firewall, TPM, Defender, BitLocker
│   ├── Battery.psm1           # Capacity, wear, cycles
│   ├── EventLogs.psm1         # Critical events, BSODs, shutdowns
│   ├── Startup.psm1           # Boot time, startup apps, services
│   ├── CleanupAdvisor.psm1    # Reclaimable space estimates
│   └── HtmlReport.psm1        # HTML dashboard generator
├── Assets/
│   ├── css/style.css           # Dark/light theme styles
│   ├── js/dashboard.js         # Charts, tables, interactivity
│   └── icons/                  # Reserved for future SVG icons
├── Reports/                    # Generated output (auto-created)
├── Logs/                       # Timestamped scan logs (auto-created)
├── README.md
├── LICENSE
├── CHANGELOG.md
└── ARCHITECTURE.md             # This file
```
