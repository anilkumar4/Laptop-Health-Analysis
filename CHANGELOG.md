# Changelog

All notable changes to Developer Health Analyzer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.0.0] - 2026-07-25

### Added
- **Core Framework**
  - Modular architecture with 10 scan modules + 1 shared Common module
  - Weighted health scoring engine (0–100 scale)
  - Prioritized recommendation system (Critical / High / Medium / Low)
  - Professional structured logging with timestamped log files
  - Console summary with progress bars and color-coded scores
  - QuickScan mode for faster desktop scans

- **System Analysis**
  - Computer model, CPU, RAM, motherboard, BIOS detection
  - Windows edition, build number, display version, install date
  - Uptime tracking and high-uptime warnings
  - Pending reboot detection (CBS, Windows Update, File Rename, SCCM)
  - Windows Update status via COM API
  - SFC results from CBS.log parsing
  - DISM status from DISM.log parsing
  - Reliability records from WMI (14-day window)

- **Storage Analysis**
  - Logical and physical disk enumeration
  - SMART health via StorageReliabilityCounter (temperature, wear, power-on hours)
  - NVMe detection
  - Recycle Bin sizing via COM Shell
  - Largest folders scan (top 100, threshold at 500MB+)
  - Largest files scan (top 200, threshold at 50MB+)
  - Folder threshold breakdown (500MB / 1GB / 5GB / 10GB / 20GB)
  - Disk usage summary for pie chart visualization
  - Folder treemap data

- **Performance Analysis**
  - Dual-sample CPU load measurement
  - Memory usage with module inventory (banks, speed, capacity)
  - Page file usage tracking
  - Disk I/O queue length monitoring
  - Top 15 CPU and memory processes
  - Background process count
  - Low RAM warning for developer workstations (<8GB)

- **Developer Environment**
  - Detection of 26 developer tools: Java, Python, Node.js, npm, pnpm, yarn, Maven, Gradle, Git, Docker, WSL, VS Code, Cursor, Claude Code, Codex CLI, Gemini CLI, LM Studio, Ollama, Aider, OpenCode, Trae, Conda, Anaconda, Android Studio, Eclipse, IntelliJ IDEA, PyCharm, Visual Studio
  - Version detection via CLI and registry fallback
  - Install path and disk usage measurement
  - Developer folder sizing: .m2, .gradle, .vscode, .cursor, .codex, .trae, .claude, .gemini, .lmstudio, .conda, .anaconda, Android SDK, Eclipse .p2, JetBrains, VS Code cache, Cursor cache, IntelliJ cache, PyCharm cache, Downloads, Desktop, Documents, OneDrive, AppData

- **Security Assessment**
  - Firewall profile status (Domain, Private, Public)
  - TPM presence and readiness
  - Secure Boot status
  - Windows Defender real-time protection and definition freshness
  - Bitdefender detection via services
  - UAC status and level
  - Credential Guard status
  - Core Isolation / Memory Integrity
  - Virtualization-Based Security
  - BitLocker volume encryption status
  - Storage Spaces health

- **Battery Health**
  - Design and full-charge capacity from WMI
  - Wear level percentage calculation
  - Cycle count from powercfg /batteryreport XML parsing
  - Charging history extraction
  - Chemistry and status text mapping
  - Desktop detection (auto-skip with Score=100)

- **Event Log Analysis**
  - Critical events (30-day window, System + Application logs)
  - Error event sampling
  - BSOD history (BugCheck Event ID 1001)
  - Unexpected shutdowns (Event IDs 41, 6008)
  - Driver failures
  - Event timeline aggregation by date (for charts)

- **Boot & Startup**
  - Boot duration from Diagnostics-Performance log (Event ID 100)
  - Fast Startup status from registry
  - Startup applications from Run keys and startup folders
  - Auto-start services inventory
  - Scheduled task enumeration

- **Cleanup Advisor**
  - Reclaimable space estimation across 13+ categories
  - Three-tier classification: Safe to delete / Review before deleting / Never delete
  - Scans: Windows Temp, npm cache, pip cache, NuGet, Gradle, Maven, VS Code cache, Cursor cache, browser caches, Downloads, Recycle Bin
  - Large archive/installer detection (>500MB ISO/ZIP/MSI/EXE)
  - Duplicate node_modules finder across project roots
  - Protected categories: Documents, OneDrive, Git repos, source code

- **HTML Dashboard**
  - Self-contained single-file report (CSS + JS inlined)
  - Bootstrap 5.3 responsive layout
  - Chart.js 4 interactive charts: disk usage doughnut, memory process bars, event timeline, security radar, dev folder sizes, battery health gauge
  - Dark/light mode toggle with localStorage persistence
  - Sortable tables with column indicators
  - Per-table search filtering
  - CSV export buttons on key tables
  - Score counter animations on page load
  - Folder treemap visualization
  - Health badges with color-coded pass/fail indicators
  - Collapsible sections
  - Print-friendly styles
  - Lucide icons

- **Output Formats**
  - `HealthReport.html` — interactive dashboard
  - `HealthReport.json` — complete structured data
  - `Recommendations.json` — prioritized action list
  - `LargestFolders.csv` — folder size export
  - `LargestFiles.csv` — file size export
  - `HealthAnalyzer_*.log` — timestamped diagnostic log

- **Documentation**
  - README.md with installation, usage, troubleshooting
  - ARCHITECTURE.md with module contracts and data flow
  - CONTRIBUTING.md with code conventions
  - CHANGELOG.md
  - MIT LICENSE
