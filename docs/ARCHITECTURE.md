# Architecture

Developer Health Analyzer uses a thin orchestration script and focused PowerShell modules.

## Flow

1. `Run-HealthAnalyzer.ps1` creates report and log directories.
2. It imports `Modules\Common.psm1` followed by diagnostic modules.
3. Each module returns a structured `pscustomobject` containing collected data, score, and recommendations.
4. The runner computes weighted scores and aggregates recommendations.
5. Reports are exported as HTML, JSON, recommendation JSON, and CSV.

## Design principles

- Read-only by default and by design.
- No cleanup automation.
- Structured objects first; formatting happens only at output boundaries.
- Module failures should degrade one report section, not terminate the entire scan.
- Prefer native Windows APIs, CIM, registry reads, and PowerShell cmdlets.
- Keep scan scope conservative for default runs while still surfacing high-value findings.

## Module contract

Each diagnostic module exposes one public function:

```powershell
Get-<Area>Report -Log $scriptBlock
```

The function returns:

```powershell
[pscustomobject]@{
    Score = 0..100
    Recommendations = @(...)
    # Area-specific properties
}
```

Recommendations use this shape:

```powershell
[pscustomobject]@{
    Priority = 'Critical' | 'High' | 'Medium' | 'Low'
    Category = 'Storage'
    Problem = 'Low free space'
    Reason = 'Only 8 percent remains.'
    Risk = 'Builds and package restore may fail.'
    SuggestedFix = 'Review cleanup findings.'
    EstimatedImprovement = '+10 storage score'
}
```

## Scoring

`Run-HealthAnalyzer.ps1` owns final scoring so modules remain independently testable. Module scores are clamped to 0-100. Event logs are blended into Windows health, and startup is blended into performance.
