# Contributing

Thank you for considering contributing to Developer Health Analyzer.

## How to Contribute

1. **Fork** the repository
2. **Create a branch** for your feature or fix: `git checkout -b feature/my-feature`
3. **Make your changes** following the conventions below
4. **Test** on both Windows PowerShell 5.1 and PowerShell 7+
5. **Submit a pull request** with a clear description

## Code Conventions

### PowerShell Style

- All public functions use `[CmdletBinding()]` with typed parameters
- All public functions return `[PSCustomObject]` with documented properties
- Use `Set-StrictMode -Version Latest` at the top of every module
- Use `[void]$list.Add(...)` instead of piping to `$null`
- Prefer `Get-CimInstance` over `Get-WmiObject` for forward compatibility
- Wrap risky calls in `Invoke-SafeCommand` with appropriate context messages

### Naming

- Module functions: `Get-<Category>Report` (e.g., `Get-StorageReport`)
- Helper functions: descriptive verb-noun, not exported
- Variables: `$camelCase` for locals, `$script:PascalCase` for script-scope

### Safety Rules

- **Never delete files**
- **Never modify Windows settings**
- **Never run repair operations** (SFC, DISM, etc.)
- **Never write outside** `Reports/` and `Logs/`
- Temp files must be cleaned up immediately after use

### Error Handling

- Use try/catch for all external calls (WMI, registry, processes)
- Log errors via `Invoke-AnalyzerLog` with appropriate level
- Return sensible defaults on failure (empty arrays, null values, score of 50)
- Never let a single module failure crash the entire analysis

## Adding a New Module

1. Create `Modules/NewCategory.psm1`
2. Export a single function: `Get-NewCategoryReport`
3. Return `[PSCustomObject]` with at minimum: `Score`, `Recommendations`
4. Register the module in `Run-HealthAnalyzer.ps1`:
   - Add to `Import-AnalyzerModules` list
   - Add to `$sections` in `Invoke-HealthAnalysis`
5. Add a section to `HtmlReport.psm1`
6. Update `ARCHITECTURE.md`

## Reporting Bugs

Please include:

- PowerShell version (`$PSVersionTable.PSVersion`)
- Windows version (run `winver`)
- Whether you ran as Administrator
- The log file from `Logs/`
- Steps to reproduce

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
