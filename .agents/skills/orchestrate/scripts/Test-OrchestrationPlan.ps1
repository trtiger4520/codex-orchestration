[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PlanFile,

    [string]$SchemaFile = (Join-Path $PSScriptRoot '..\references\orchestration-plan.schema.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-ValidationError {
    param([Parameter(Mandatory)][string]$Message)

    $script:validationErrors.Add($Message)
}

$PlanFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PlanFile)
$SchemaFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SchemaFile)

if (-not (Test-Path -LiteralPath $PlanFile -PathType Leaf)) {
    Write-Error "Plan file not found: $PlanFile"
    exit 1
}

if (-not (Test-Path -LiteralPath $SchemaFile -PathType Leaf)) {
    Write-Error "Schema file not found: $SchemaFile"
    exit 1
}

$json = Get-Content -LiteralPath $PlanFile -Raw

try {
    $plan = $json | ConvertFrom-Json -Depth 100
}
catch {
    Write-Error "Plan is not valid JSON: $($_.Exception.Message)"
    exit 1
}

$schemaValid = Test-Json -Json $json -SchemaFile $SchemaFile -ErrorAction SilentlyContinue
if (-not $schemaValid) {
    Write-Error "Plan does not match schema: $SchemaFile"
    exit 1
}

$validationErrors = [System.Collections.Generic.List[string]]::new()
$tasksById = @{}

foreach ($task in $plan.tasks) {
    if ($tasksById.ContainsKey($task.id)) {
        Add-ValidationError "Duplicate task id: $($task.id)"
        continue
    }

    $tasksById[$task.id] = $task
}

foreach ($task in $plan.tasks) {
    foreach ($dependency in $task.depends_on) {
        if ($dependency -eq $task.id) {
            Add-ValidationError "Task '$($task.id)' cannot depend on itself"
        }
        elseif (-not $tasksById.ContainsKey($dependency)) {
            Add-ValidationError "Task '$($task.id)' has unknown dependency '$dependency'"
        }
    }

    if ($task.mode -eq 'write') {
        if ($task.files.Count -eq 0) {
            Add-ValidationError "Write task '$($task.id)' must declare at least one file"
        }

        if ($task.verify_cmds.Count -eq 0) {
            Add-ValidationError "Write task '$($task.id)' must declare at least one verification command"
        }
    }
}

$visitState = @{}

function Visit-Task {
    param([Parameter(Mandatory)][string]$TaskId)

    if ($visitState[$TaskId] -eq 'visiting') {
        Add-ValidationError "Dependency cycle detected at task '$TaskId'"
        return
    }

    if ($visitState[$TaskId] -eq 'visited') {
        return
    }

    $visitState[$TaskId] = 'visiting'
    foreach ($dependency in $tasksById[$TaskId].depends_on) {
        if ($tasksById.ContainsKey($dependency) -and $dependency -ne $TaskId) {
            Visit-Task -TaskId $dependency
        }
    }
    $visitState[$TaskId] = 'visited'
}

foreach ($taskId in $tasksById.Keys) {
    Visit-Task -TaskId $taskId
}

if ($validationErrors.Count -gt 0) {
    foreach ($validationError in $validationErrors) {
        Write-Error $validationError
    }
    exit 1
}

Write-Output "PASS: $PlanFile"
