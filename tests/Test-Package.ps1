[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pwsh = (Get-Process -Id $PID).Path
$testScripts = @(
    "Test-Contract.ps1",
    "Test-LaneScenarios.ps1",
    "Test-SourceBoundary.ps1",
    "Test-Installer.ps1",
    "Test-Policy.ps1"
)

foreach ($testScript in $testScripts) {
    $path = Join-Path $PSScriptRoot $testScript
    Write-Host "RUN   $testScript"
    & $pwsh -NoProfile -File $path
    if ($LASTEXITCODE -ne 0) {
        throw "$testScript failed with exit code $LASTEXITCODE"
    }
}

Write-Output "All package tests passed"
