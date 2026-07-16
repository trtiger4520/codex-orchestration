[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Capture', 'Verify')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$SnapshotFile,

    [string]$Repository = '.',

    [string[]]$AllowedWrite = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepositorySnapshot {
    param([Parameter(Mandatory)][string]$Root)

    $LASTEXITCODE = 0
    $resolvedRoot = (& git -C $Root rev-parse --show-toplevel 2>&1 | Select-Object -First 1).ToString().Trim()
    if ($LASTEXITCODE -ne 0 -or -not $resolvedRoot) {
        throw "Not a Git repository: $Root"
    }

    $files = [ordered]@{}
    $LASTEXITCODE = 0
    $trackedAndUntracked = @(& git -C $resolvedRoot -c core.quotepath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to list repository files: $resolvedRoot"
    }

    foreach ($relativePath in ($trackedAndUntracked | Sort-Object -Unique)) {
        if (-not $relativePath) {
            continue
        }
        $normalized = $relativePath.Replace('\', '/')
        $absolutePath = Join-Path $resolvedRoot $relativePath
        if (Test-Path -LiteralPath $absolutePath -PathType Leaf) {
            $files[$normalized] = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath).Hash.ToLowerInvariant()
        }
    }

    return [ordered]@{
        version = '1.0'
        repository_root = $resolvedRoot
        files = $files
    }
}

function Test-AllowedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ([System.IO.Path]::IsPathRooted($pattern) -or ($pattern -split '[\\/]') -contains '..') {
            throw "Allowed write pattern must be repository-relative: $pattern"
        }
        $escaped = [regex]::Escape($pattern.Replace('\', '/'))
        $expression = '^' + $escaped.Replace('\*\*/', '(?:.*/)?').Replace('\*\*', '.*').Replace('\*', '[^/]*').Replace('\?', '[^/]') + '$'
        if ($Path -match $expression) {
            return $true
        }
    }
    return $false
}

$snapshotPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SnapshotFile)

if ($Mode -eq 'Capture') {
    $snapshot = Get-RepositorySnapshot -Root $Repository
    $parent = Split-Path -Parent $snapshotPath
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $snapshotPath -Encoding utf8NoBOM
    Write-Output "CAPTURED: $snapshotPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
    throw "Snapshot file not found: $snapshotPath"
}

$before = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json -Depth 20 -AsHashtable
$after = Get-RepositorySnapshot -Root $Repository
$changes = [System.Collections.Generic.List[string]]::new()
$allPaths = @($before.files.Keys) + @($after.files.Keys) | Sort-Object -Unique

foreach ($path in $allPaths) {
    $beforeHash = if ($before.files.Contains($path)) { $before.files[$path] } else { $null }
    $afterHash = if ($after.files.Contains($path)) { $after.files[$path] } else { $null }
    if ($beforeHash -ne $afterHash -and -not (Test-AllowedPath -Path $path -Patterns $AllowedWrite)) {
        $changes.Add($path)
    }
}

if ($changes.Count -gt 0) {
    foreach ($path in $changes) {
        Write-Error "Source boundary violation: $path"
    }
    exit 1
}

Write-Output 'PASS: source boundary preserved'
