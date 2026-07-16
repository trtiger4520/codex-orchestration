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
if ($matrix.version -ne '1.1' -or $matrix.scenarios.Count -lt 12) {
    throw 'Scenario matrix must be version 1.1 and contain at least twelve scenarios'
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
    $roleLimits = @{}
    foreach ($property in $scenario.max_role_counts.PSObject.Properties) {
        if ($property.Name -notin $validRoles) { throw "Scenario '$($scenario.id)' has an invalid role limit '$($property.Name)'" }
        if ($property.Name -notin $scenario.allowed_roles) { throw "Scenario '$($scenario.id)' limits a role it does not allow: $($property.Name)" }
        if (($property.Value -isnot [int] -and $property.Value -isnot [long]) -or $property.Value -lt 1) { throw "Scenario '$($scenario.id)' has an invalid role count for '$($property.Name)'" }
        if ($property.Name -eq 'orchestration_implementer' -and $property.Value -gt 2) { throw "Scenario '$($scenario.id)' exceeds the implementer role limit" }
        if ($property.Name -ne 'orchestration_implementer' -and $property.Value -ne 1) { throw "Scenario '$($scenario.id)' must limit '$($property.Name)' to one agent" }
        $roleLimits[$property.Name] = $property.Value
    }
    foreach ($role in $scenario.allowed_roles) {
        if (-not $roleLimits.ContainsKey($role)) { throw "Scenario '$($scenario.id)' has no max role count for '$role'" }
    }
    if ($scenario.max_subagents -lt $scenario.required_roles.Count) { throw "Scenario '$($scenario.id)' has an impossible role limit" }
    if ('plan-light' -in $scenario.allowed_lanes -and $scenario.max_subagents -gt 1) { throw "Scenario '$($scenario.id)' violates the plan-light role limit" }
}

$requiredIds = @('known-dto-field', 'unfamiliar-login-trace', 'known-crud-edits', 'large-ci-log', 'independent-verification-only', 'ef-core-migration', 'authentication-policy', 'ten-doc-wording', 'cohesive-feature-unit', 'security-read-only-analysis', 'architecture-read-only-analysis', 'explicit-two-writer-workflow')
foreach ($id in $requiredIds) { if (-not $ids.Contains($id)) { throw "Missing required scenario: $id" } }

function Get-EvaluationErrors {
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)][string]$ResultJson
    )

    if (-not (Test-Json -Json $ResultJson -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
        Write-Output 'schema'
        return
    }

    $result = $ResultJson | ConvertFrom-Json -Depth 20
    $roleCounts = @{}
    $subagentCount = 0
    foreach ($agent in $result.delegated_agents) {
        if ($roleCounts.ContainsKey($agent.role)) {
            Write-Output 'duplicate-role'
            continue
        }
        $roleCounts[$agent.role] = $agent.count
        $subagentCount += $agent.count
    }
    if ($result.lane -notin $Scenario.allowed_lanes) { Write-Output 'lane' }
    if ($result.approval_required -ne $Scenario.approval_required) { Write-Output 'approval' }
    if ($result.lane -eq 'single-agent' -and $subagentCount -ne 0) { Write-Output 'single-agent-count' }
    if ($result.lane -eq 'plan-light' -and $subagentCount -gt 1) { Write-Output 'plan-light-count' }
    if ($subagentCount -gt $Scenario.max_subagents) { Write-Output 'max-subagents' }
    foreach ($role in $Scenario.required_roles) { if (-not $roleCounts.ContainsKey($role)) { Write-Output 'required-role' } }
    foreach ($role in $roleCounts.Keys) {
        if ($role -notin $Scenario.allowed_roles -or $role -in $Scenario.forbidden_roles) {
            Write-Output 'disallowed-role'
            continue
        }
        $limit = $Scenario.max_role_counts.PSObject.Properties | Where-Object Name -EQ $role | Select-Object -First 1
        if ($null -eq $limit -or $roleCounts[$role] -gt $limit.Value) { Write-Output 'role-limit' }
    }
}

function Assert-EvaluationCase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)][string]$ResultJson,
        [string]$ExpectedError
    )

    $errors = @(Get-EvaluationErrors -Scenario $Scenario -ResultJson $ResultJson)
    if (-not $ExpectedError -and $errors.Count -gt 0) { throw "Evaluation case '$Name' unexpectedly failed: $($errors -join ', ')" }
    if ($ExpectedError -and $ExpectedError -notin $errors) { throw "Evaluation case '$Name' did not report '$ExpectedError': $($errors -join ', ')" }
}

$twoWriterScenario = $matrix.scenarios | Where-Object id -EQ 'explicit-two-writer-workflow' | Select-Object -First 1
$highRiskScenario = $matrix.scenarios | Where-Object id -EQ 'ef-core-migration' | Select-Object -First 1
$planLightScenario = '{"allowed_lanes":["plan-light"],"required_roles":[],"allowed_roles":["orchestration_explorer","orchestration_implementer"],"forbidden_roles":[],"max_role_counts":{"orchestration_explorer":1,"orchestration_implementer":1},"max_subagents":2,"approval_required":false}' | ConvertFrom-Json

Assert-EvaluationCase -Name 'two implementers count as two' -Scenario $twoWriterScenario -ResultJson '{"lane":"orchestrate-heavy","delegated_agents":[{"role":"orchestration_planner","count":1},{"role":"orchestration_implementer","count":2},{"role":"orchestration_verifier","count":1}],"approval_required":true,"rationale":"Two disjoint delivery units"}'
Assert-EvaluationCase -Name 'more than two implementers' -Scenario $twoWriterScenario -ResultJson '{"lane":"orchestrate-heavy","delegated_agents":[{"role":"orchestration_planner","count":1},{"role":"orchestration_implementer","count":3},{"role":"orchestration_verifier","count":1}],"approval_required":true,"rationale":"Too many writers"}' -ExpectedError 'schema'
Assert-EvaluationCase -Name 'high-risk writer limit' -Scenario $highRiskScenario -ResultJson '{"lane":"orchestrate-heavy","delegated_agents":[{"role":"orchestration_planner","count":1},{"role":"orchestration_implementer","count":2},{"role":"orchestration_verifier","count":1}],"approval_required":true,"rationale":"High-risk migration"}' -ExpectedError 'role-limit'
Assert-EvaluationCase -Name 'duplicate role' -Scenario $twoWriterScenario -ResultJson '{"lane":"orchestrate-heavy","delegated_agents":[{"role":"orchestration_planner","count":1},{"role":"orchestration_implementer","count":1},{"role":"orchestration_implementer","count":2},{"role":"orchestration_verifier","count":1}],"approval_required":true,"rationale":"Duplicate role entries"}' -ExpectedError 'duplicate-role'
Assert-EvaluationCase -Name 'plan-light count limit' -Scenario $planLightScenario -ResultJson '{"lane":"plan-light","delegated_agents":[{"role":"orchestration_explorer","count":1},{"role":"orchestration_implementer","count":1}],"approval_required":false,"rationale":"Too many plan-light agents"}' -ExpectedError 'plan-light-count'

Write-Output "PASS: $($matrix.scenarios.Count) lane scenarios"
