# Developer Guide

## Adding a new check

1. Pick the module that owns the domain.
2. Keep the check read-only.
3. Return structured data, not formatted strings.
4. Add a recommendation only when the finding is actionable.
5. Prefer `Invoke-SafeCommand` for APIs that may fail under non-admin sessions.
6. Keep score deductions explainable and bounded.

## Adding a module

1. Create `Modules\YourModule.psm1`.
2. Import it in `Run-HealthAnalyzer.ps1` after `Common.psm1`.
3. Return an object with `Score` and `Recommendations`.
4. Add the section to the HTML generator if it should be visible in the dashboard.

## Validation

Parse all PowerShell files:

```powershell
$files = Get-ChildItem -Path .\DeveloperHealthAnalyzer -Include *.ps1,*.psm1 -Recurse
foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) { $errors }
}
```

Run a quick scan:

```powershell
.\Run-HealthAnalyzer.ps1 -SkipEventLogs -SkipBattery -Quiet
```

## Coding conventions

- Use approved verbs where practical.
- Use `[CmdletBinding()]` for public functions.
- Avoid modifying system state.
- Avoid global mutable state inside modules.
- Avoid writing directly to host from modules; return data and use the logger script block.
