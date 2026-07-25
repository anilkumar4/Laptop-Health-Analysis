# Developer Health Analyzer

<p align="center">
  <strong>Production-quality, read-only Windows diagnostics for software developers</strong>
</p>

<p align="center">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell">
  <img alt="Windows 10/11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows11">
  <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-green">
  <img alt="Read-only" src="https://img.shields.io/badge/Mode-Read--only-orange">
</p>

---

Developer Health Analyzer scans your Windows workstation across **10 categories** — Windows health, storage, performance, developer tooling, security, battery, event logs, startup impact, network, and cleanup opportunities — then produces an **interactive HTML dashboard**, **JSON report**, **CSV exports**, and **prioritized recommendations**.

It follows the design philosophy of Microsoft Sysinternals, CrystalDiskInfo, and Dell SupportAssist: thorough diagnostics with zero system modification.

## 🔒 Safety Model

> **This tool is completely read-only.**

- ❌ Never deletes files
- ❌ Never cleans automatically
- ❌ Never changes Windows settings
- ❌ Never repairs system components
- ✅ Only scans and reports

Cleanup findings are advisory only. Items are categorized as `Safe to delete`, `Review before deleting`, or `Never delete`.

## 📋 Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Windows 10 or Windows 11 |
| **PowerShell** | Windows PowerShell 5.1 or PowerShell 7+ |
| **Privileges** | Standard user (Administrator recommended for full results) |
| **Dependencies** | None — pure PowerShell, no external modules needed |

**Administrator** unlocks: BitLocker status, TPM details, full event logs, storage reliability counters, and Windows Update pending count.

## 🚀 Quick Start

```powershell
# Clone or download the repository
cd .\DeveloperHealthAnalyzer

# Full scan (recommended — run as Administrator)
.\Run-HealthAnalyzer.ps1

# Quick scan — faster, skips large folder enumeration
.\Run-HealthAnalyzer.ps1 -QuickScan

# Desktop — skip battery analysis
.\Run-HealthAnalyzer.ps1 -SkipBattery

# Custom output location
.\Run-HealthAnalyzer.ps1 -OutputDirectory C:\Temp\DevHealth

# Silent mode — no console output
.\Run-HealthAnalyzer.ps1 -Quiet

# JSON only — skip HTML generation
.\Run-HealthAnalyzer.ps1 -NoHtml
```

## 📊 Output Files

| File | Description |
|------|-------------|
| `Reports/HealthReport.html` | Interactive Bootstrap 5 dashboard with charts |
| `Reports/HealthReport.json` | Complete structured report data |
| `Reports/Recommendations.json` | Prioritized action items |
| `Reports/LargestFolders.csv` | Top folders by size |
| `Reports/LargestFiles.csv` | Top files by size |
| `Logs/HealthAnalyzer_*.log` | Timestamped diagnostic log |

## 🖥️ Dashboard Features

The HTML dashboard is a **self-contained file** that works offline.

- **Overall Health Score** (0–100) with category breakdown
- **Dark / Light mode** toggle (persisted in localStorage)
- **Interactive charts**: Disk usage doughnut, process memory bars, event timeline, security radar, dev folder sizes, battery health gauge
- **Sortable and searchable tables** with CSV export buttons
- **Collapsible sections** for each analysis category
- **Folder treemap** visualization
- **Health badges** with color-coded pass/fail indicators
- **Prioritized recommendations** with Problem, Reason, Risk, Fix, and Estimated Improvement
- **Print-friendly** styles
- **Responsive** layout — desktop, tablet, mobile

## 📐 Health Scoring

| Category | Weight | Description |
|----------|--------|-------------|
| Windows Health | 25% | Updates, reboot state, reliability, SFC/DISM |
| Performance | 20% | CPU, RAM, disk I/O, boot time |
| Storage | 20% | Free space, SMART health, temperature |
| Security | 15% | Firewall, Defender, TPM, Secure Boot, BitLocker, UAC |
| Battery | 10% | Capacity, wear level, cycle count (100 for desktops) |
| Developer Env | 10% | Tool detection, cache sizes |

Event log findings blend into Windows Health (30%). Startup findings blend into Performance (30%).

## 🔍 What It Scans

### System
Computer model, CPU, RAM, motherboard, BIOS, Windows edition, build, install date, uptime

### Storage
Every drive (free space, SSD/HDD), SMART health, temperature, wear level, NVMe detection, largest folders, largest files, folder treemap, disk usage pie chart, folders by threshold (500MB/1GB/5GB/10GB/20GB), Recycle Bin

### Developer Tools Detected
Java, Python, Node.js, npm, pnpm, yarn, Maven, Gradle, Git, Docker, WSL, VS Code, Cursor, Claude Code, Codex CLI, Gemini CLI, LM Studio, Ollama, Aider, OpenCode, Trae, Conda, Anaconda, Android Studio, Eclipse, IntelliJ IDEA, PyCharm, Visual Studio

### Developer Folders Analyzed
`.m2`, `.gradle`, `.vscode`, `.cursor`, `.codex`, `.trae`, `.claude`, `.gemini`, `.lmstudio`, `.conda`, `.anaconda`, Android SDK, Eclipse `.p2`, JetBrains, VS Code cache, Cursor cache, IntelliJ cache, PyCharm cache, Downloads, Desktop, Documents, OneDrive, AppData Local, AppData Roaming

### Performance
CPU usage (sampled), RAM usage, page file, disk I/O queue, top 15 CPU processes, top 15 memory processes, background process count

### Network
Physical adapters, WiFi/Ethernet, driver versions, DNS servers, proxy settings, VPN adapter detection

### Security
Firewall profiles, TPM, Secure Boot, Windows Defender, Bitdefender, UAC, Credential Guard, Core Isolation / Memory Integrity, Virtualization-Based Security, BitLocker, Storage Spaces

### Windows Health
Pending reboot detection, Windows Update status, SFC last result (from CBS.log), DISM status (from DISM.log), reliability records

### Event Logs
Critical events (30 days), error events, BSOD history, unexpected shutdowns, driver failures, application crashes, event timeline

### Boot & Startup
Average boot time, Fast Startup status, startup applications, auto-start services, scheduled tasks

### Battery
Design capacity, full charge capacity, wear level, cycle count (via powercfg), charging history, chemistry type

### Cleanup Advisor
Temp folders, npm/pip/NuGet/Gradle/Maven caches, VS Code and Cursor caches, browser caches, Recycle Bin, large ISOs/ZIPs, old installers, duplicate node_modules — each classified as Safe/Review/NeverDelete

## 🏗️ Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for full technical details.

```
DeveloperHealthAnalyzer/
├── Run-HealthAnalyzer.ps1          # Entry point
├── Modules/
│   ├── Common.psm1                 # Shared utilities
│   ├── WindowsHealth.psm1          # System + Windows health
│   ├── Storage.psm1                # Drives + SMART + folders
│   ├── Performance.psm1            # CPU + RAM + processes + network
│   ├── DeveloperEnvironment.psm1   # Tool detection + folder sizing
│   ├── Security.psm1               # Security posture
│   ├── Battery.psm1                # Battery health + powercfg
│   ├── EventLogs.psm1              # Event analysis
│   ├── Startup.psm1                # Boot + startup impact
│   ├── CleanupAdvisor.psm1         # Cleanup recommendations
│   └── HtmlReport.psm1             # Dashboard generator
├── Assets/
│   ├── css/style.css               # Dark/light theme styles
│   ├── js/dashboard.js             # Charts + interactivity
│   └── icons/                      # Reserved for SVG icons
├── Reports/                        # Output directory
├── Logs/                           # Diagnostic logs
├── README.md
├── ARCHITECTURE.md
├── CONTRIBUTING.md
├── CHANGELOG.md
└── LICENSE
```

## 🛠️ Troubleshooting

### "Running scripts is disabled on this system"
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Limited results without Administrator
Some checks require elevation:
- BitLocker volume status
- TPM details
- Full event log access
- Storage reliability counters
- Windows Update pending count

Run PowerShell as Administrator for the most complete report.

### HTML report doesn't load charts
Charts require an internet connection on first load (Bootstrap and Chart.js CDN). Once the page loads, it works offline via browser cache.

### Scan takes too long
Use `-QuickScan` to skip deep folder enumeration and large file scanning:
```powershell
.\Run-HealthAnalyzer.ps1 -QuickScan
```

### PowerShell 7 compatibility
The analyzer is designed for both Windows PowerShell 5.1 and PowerShell 7+. If you encounter issues, check:
```powershell
$PSVersionTable
```

## 📄 License

[MIT](LICENSE)

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
