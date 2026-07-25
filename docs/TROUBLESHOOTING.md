# Troubleshooting

## Some sections show no data

Run PowerShell as Administrator. Certain checks need elevated rights or enterprise policy access.

## Windows Update query is unavailable

The analyzer uses the Windows Update COM API in read-only mode. Managed or offline systems may block this query. The report will continue with an explanatory error.

## Event log scan is slow

Use:

```powershell
.\Run-HealthAnalyzer.ps1 -SkipEventLogs
```

## Folder sizing is slow

Folder sizing walks files to calculate exact sizes for requested developer locations. Large `AppData`, package caches, or project trees can take time on the first run.

## HTML charts do not render

The dashboard references Bootstrap, Chart.js, and Lucide from CDNs. If the machine is offline, the raw tables and report content still render, but charts/icons may not load. Enterprises can vendor these assets into `Assets` and update `HtmlReport.psm1`.

## Access denied messages

Access denied is expected for some protected folders, event logs, or security APIs. The analyzer logs the failure and continues.
