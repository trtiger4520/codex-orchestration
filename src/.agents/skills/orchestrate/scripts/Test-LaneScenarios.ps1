[CmdletBinding()]
param(
    [string]$ScenarioFile = (Join-Path $PSScriptRoot '..\references\lane-scenarios.v1.json'),
    [string]$ResultSchemaFile = (Join-Path $PSScriptRoot '..\references\lane-evaluation-result.schema.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scenarioPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScenarioFile)
$schemaPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultSchemaFile)
$matrix = Get-Content -Raw -LiteralPath $scenarioPath | ConvertFrom-Json -Depth 30
$schema = Get-Content -Raw -LiteralPath $schemaPath
if (-not (Test-Json -Json $schema -ErrorAction SilentlyContinue)) {
    throw "Result schema is not valid JSON: $schemaPath"
}
if ($matrix.version -ne '1.0' -or $matrix.scenarios.Count -lt 9) {
    throw 'Scenario matrix must be version 1.0 and contain at least nine scenarios'
}

$validLanes = @('single-agent', 'plan-light', 'orchestrate-heavy')
$validRoles = @('orchestration_planner', 'orchestration_explorer', 'orchestration_implementer', 'orchestration_verifier')
$ids = [System.Collections.Generic.HashSet[string]]::new()
foreach ($scenario in $matrix.scenarios) {
    if (-not $ids.Add($scenario.id)) { throw "Duplicate scenario id: $($scenario.id)" }
    if (-not $scenario.prompt -or $scenario.allowed_lanes.Count -eq 0) { throw "Scenario '$($scenario.id)' is incomplete" }
    foreach ($lane in $scenario.allowed_lanes) { if ($lane -notin $validLanes) { throw "Invalid lane '$lane'" } }
    foreach ($role in @($scenario.required_roles) + @($scenario.allowed_roles) + @($scenario.forbidden_roles)) {
        if ($role -notin $validRoles) { throw "Invalid role '$role'" }
    }
    if (@($scenario.required_roles | Where-Object { $_ -notin $scenario.allowed_roles }).Count -gt 0) {
        throw "Scenario '$($scenario.id)' requires a role it does not allow"
    }
    if (@($scenario.allowed_roles | Where-Object { $_ -in $scenario.forbidden_roles }).Count -gt 0) {
        throw "Scenario '$($scenario.id)' both allows and forbids a role"
    }
    if ($scenario.max_subagents -lt $scenario.required_roles.Count) { throw "Scenario '$($scenario.id)' has an impossible role limit" }
    if ('plan-light' -in $scenario.allowed_lanes -and $scenario.max_subagents -gt 1) { throw "Scenario '$($scenario.id)' violates the plan-light role limit" }
}

$requiredIds = @('known-dto-field', 'unfamiliar-login-trace', 'known-crud-edits', 'large-ci-log', 'independent-verification-only', 'ef-core-migration', 'authentication-policy', 'ten-doc-wording', 'cohesive-feature-unit')
foreach ($id in $requiredIds) { if (-not $ids.Contains($id)) { throw "Missing required scenario: $id" } }

Write-Output "PASS: $($matrix.scenarios.Count) lane scenarios"
