[CmdletBinding()]
param(
    [string]$ScenarioFile = (Join-Path $PSScriptRoot '..\references\lane-scenarios.v1.json'),
    [string]$ResultSchemaFile = (Join-Path $PSScriptRoot '..\references\lane-evaluation-result.schema.json'),
    [string]$AgentsFile = (Join-Path $PSScriptRoot '..\..\..\..\AGENTS.md'),
    [string]$Model
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { throw 'Codex CLI is required for live lane evaluation' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required for live lane evaluation' }

$matrix = Get-Content -Raw -LiteralPath $ScenarioFile | ConvertFrom-Json -Depth 30
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "codex-lane-eval-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$passed = 0

try {
    foreach ($scenario in $matrix.scenarios) {
        $caseRoot = Join-Path $tempRoot $scenario.id
        New-Item -ItemType Directory -Path $caseRoot | Out-Null
        Copy-Item -LiteralPath $AgentsFile -Destination (Join-Path $caseRoot 'AGENTS.md')
        & git -C $caseRoot init --quiet
        if ($LASTEXITCODE -ne 0) { throw "Unable to initialize live scenario repository: $($scenario.id)" }

        $resultFile = Join-Path $caseRoot 'result.json'
        $prompt = @"
Classify this hypothetical task using AGENTS.md, but do not execute it or modify files
Return only the JSON object required by the output schema

Task: $($scenario.prompt)
"@
        $arguments = @('exec', '-C', $caseRoot, '--sandbox', 'read-only', '--output-schema', $ResultSchemaFile, '--output-last-message', $resultFile)
        if ($Model) { $arguments += @('--model', $Model) }
        $arguments += $prompt
        & codex @arguments
        if ($LASTEXITCODE -ne 0) { throw "Codex live evaluation failed: $($scenario.id)" }

        $resultJson = Get-Content -Raw -LiteralPath $resultFile
        if (-not (Test-Json -Json $resultJson -SchemaFile $ResultSchemaFile -ErrorAction SilentlyContinue)) {
            throw "Invalid result for scenario '$($scenario.id)'"
        }
        $result = $resultJson | ConvertFrom-Json -Depth 20
        if ($result.lane -notin $scenario.allowed_lanes) { throw "Scenario '$($scenario.id)' selected disallowed lane '$($result.lane)'" }
        if ($result.approval_required -ne $scenario.approval_required) { throw "Scenario '$($scenario.id)' selected the wrong approval behavior" }
        if ($result.delegated_roles.Count -gt $scenario.max_subagents) { throw "Scenario '$($scenario.id)' exceeded its subagent limit" }
        foreach ($role in $scenario.required_roles) { if ($role -notin $result.delegated_roles) { throw "Scenario '$($scenario.id)' omitted required role '$role'" } }
        foreach ($role in $result.delegated_roles) {
            if ($role -notin $scenario.allowed_roles -or $role -in $scenario.forbidden_roles) { throw "Scenario '$($scenario.id)' selected disallowed role '$role'" }
        }
        $passed++
        Write-Output "PASS: $($scenario.id)"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Live lane scenarios passed: $passed"
