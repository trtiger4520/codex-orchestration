[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$validator = Join-Path $root 'src\.agents\skills\orchestrate\scripts\Test-LaneScenarios.ps1'
& (Get-Process -Id $PID).Path -NoProfile -File $validator
if ($LASTEXITCODE -ne 0) { throw "Lane scenario validation failed with exit code $LASTEXITCODE" }
Write-Output 'All lane scenario tests passed'
