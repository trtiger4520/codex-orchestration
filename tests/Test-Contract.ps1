[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $repositoryRoot 'src'
$validator = Join-Path $sourceRoot '.agents\skills\orchestrate\scripts\Test-OrchestrationPlan.ps1'
$schema = Join-Path $sourceRoot '.agents\skills\orchestrate\references\orchestration-plan.schema.json'
$pwsh = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $pwsh)) {
    $pwsh = Join-Path $PSHOME 'pwsh'
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "codex-orchestration-contract-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $tempRoot | Out-Null

function New-Task {
    param(
        [string]$Id = 'inspect',
        [string]$Mode = 'read',
        [string[]]$Files = @(),
        [string[]]$DependsOn = @(),
        [string[]]$VerifyCommands = @()
    )

    [ordered]@{
        id                  = $Id
        mode                = $Mode
        goal                = "Complete $Id"
        files               = $Files
        depends_on          = $DependsOn
        risk                = 'low'
        acceptance_criteria = @("$Id is complete")
        verify_cmds         = $VerifyCommands
    }
}

function New-Plan {
    param(
        [string]$Lane,
        [object[]]$Tasks
    )

    [ordered]@{
        version = '1.0'
        lane    = $Lane
        summary = "Validate $Lane planning"
        tasks   = $Tasks
    }
}

function Invoke-ContractCase {
    param(
        [string]$Name,
        [object]$Plan,
        [bool]$ShouldPass
    )

    $planPath = Join-Path $tempRoot "$Name.json"
    $Plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $planPath -Encoding utf8NoBOM

    $output = & $pwsh -NoProfile -File $validator -PlanFile $planPath -SchemaFile $schema 2>&1
    $passed = $LASTEXITCODE -eq 0
    if ($passed -ne $ShouldPass) {
        throw "Case '$Name' expected pass=$ShouldPass but got pass=$passed`n$($output -join [Environment]::NewLine)"
    }

    Write-Output "PASS: $Name"
}

try {
    Invoke-ContractCase -Name 'valid-single-agent' -ShouldPass $true -Plan (New-Plan -Lane 'single-agent' -Tasks @(
            New-Task -Id 'inspect'
        ))

    Invoke-ContractCase -Name 'valid-plan-light' -ShouldPass $true -Plan (New-Plan -Lane 'plan-light' -Tasks @(
            New-Task -Id 'inspect'
            New-Task -Id 'change' -Mode 'write' -Files @('README.md') -DependsOn @('inspect') -VerifyCommands @('git diff --check')
        ))

    Invoke-ContractCase -Name 'valid-orchestrate-heavy' -ShouldPass $true -Plan (New-Plan -Lane 'orchestrate-heavy' -Tasks @(
            New-Task -Id 'inspect'
            New-Task -Id 'change' -Mode 'write' -Files @('src/**') -DependsOn @('inspect') -VerifyCommands @('dotnet test')
            New-Task -Id 'review' -Mode 'review' -DependsOn @('change') -VerifyCommands @('dotnet test')
        ))

    $missingField = New-Plan -Lane 'single-agent' -Tasks @((New-Task))
    $missingField.Remove('summary')
    Invoke-ContractCase -Name 'invalid-missing-field' -ShouldPass $false -Plan $missingField

    Invoke-ContractCase -Name 'invalid-duplicate-id' -ShouldPass $false -Plan (New-Plan -Lane 'plan-light' -Tasks @(
            New-Task -Id 'same'
            New-Task -Id 'same'
        ))

    Invoke-ContractCase -Name 'invalid-unknown-dependency' -ShouldPass $false -Plan (New-Plan -Lane 'plan-light' -Tasks @(
            New-Task -Id 'change' -Mode 'write' -Files @('README.md') -DependsOn @('missing') -VerifyCommands @('git diff --check')
        ))

    Invoke-ContractCase -Name 'invalid-write-without-files' -ShouldPass $false -Plan (New-Plan -Lane 'plan-light' -Tasks @(
            New-Task -Id 'change' -Mode 'write' -VerifyCommands @('git diff --check')
        ))

    Invoke-ContractCase -Name 'invalid-write-without-verification' -ShouldPass $false -Plan (New-Plan -Lane 'plan-light' -Tasks @(
            New-Task -Id 'change' -Mode 'write' -Files @('README.md')
        ))

    Invoke-ContractCase -Name 'invalid-self-dependency' -ShouldPass $false -Plan (New-Plan -Lane 'plan-light' -Tasks @(
            New-Task -Id 'inspect' -DependsOn @('inspect')
        ))

    Invoke-ContractCase -Name 'invalid-cycle' -ShouldPass $false -Plan (New-Plan -Lane 'orchestrate-heavy' -Tasks @(
            New-Task -Id 'first' -DependsOn @('second')
            New-Task -Id 'second' -DependsOn @('first')
        ))
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Write-Output 'All orchestration contract tests passed'
