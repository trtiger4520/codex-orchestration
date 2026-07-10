[CmdletBinding()]
param(
    [ValidateSet("User", "Project")]
    [string]$Scope = "User",

    [ValidateSet("Codex", "Copilot", "All")]
    [string]$Platform = "All",

    [string]$ProjectPath,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$packageRoot = Split-Path -Parent $PSCommandPath
$startMarker = "<!-- codex-multi-agent-orchestration:start -->"
$endMarker = "<!-- codex-multi-agent-orchestration:end -->"
$installCodex = $Platform -in @("Codex", "All")
$installCopilot = $Platform -in @("Copilot", "All")

function Test-SamePath {
    param(
        [Parameter(Mandatory)]
        [string]$Left,

        [Parameter(Mandatory)]
        [string]$Right
    )

    $leftPath = [System.IO.Path]::GetFullPath($Left).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $rightPath = [System.IO.Path]::GetFullPath($Right).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    return $leftPath.Equals($rightPath, [System.StringComparison]::OrdinalIgnoreCase)
}

function Copy-ManagedFile {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Source file not found: $Source"
    }

    if (Test-SamePath -Left $Source -Right $Destination) {
        Write-Host "SKIP  $Destination"
        return
    }

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash
        $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash

        if ($sourceHash -eq $destinationHash) {
            Write-Host "SKIP  $Destination"
            return
        }

        if (-not $Force) {
            throw "Managed file conflict: $Destination`nRe-run with -Force to overwrite this managed file"
        }
    }

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item -Force -LiteralPath $Source -Destination $Destination
    Write-Host "COPY  $Destination"
}

function Copy-ManagedTree {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$DestinationRoot
    )

    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        throw "Source directory not found: $SourceRoot"
    }

    foreach ($sourceFile in Get-ChildItem -LiteralPath $SourceRoot -Recurse -File) {
        $relativePath = [System.IO.Path]::GetRelativePath($SourceRoot, $sourceFile.FullName)
        $destinationFile = Join-Path $DestinationRoot $relativePath
        Copy-ManagedFile -Source $sourceFile.FullName -Destination $destinationFile
    }
}

function Merge-ManagedInstructions {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (Test-SamePath -Left $Source -Right $Destination) {
        Write-Host "SKIP  $Destination"
        return
    }

    $sourceContent = (Get-Content -Raw -Encoding utf8 -LiteralPath $Source).Trim()
    $managedBlock = "$startMarker`n$sourceContent`n$endMarker"
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        Set-Content -Encoding utf8 -NoNewline -LiteralPath $Destination -Value $managedBlock
        Write-Host "MERGE $Destination"
        return
    }

    $existing = Get-Content -Raw -Encoding utf8 -LiteralPath $Destination
    $pattern = "(?s)$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))"
    $match = [regex]::Match($existing, $pattern)

    if ($match.Success) {
        if ($match.Value -eq $managedBlock) {
            Write-Host "SKIP  $Destination"
            return
        }

        if (-not $Force) {
            throw "Managed instruction block conflict: $Destination`nRe-run with -Force to update only the marked block"
        }

        $replacement = [System.Text.RegularExpressions.MatchEvaluator]{ param($ignored) $managedBlock }
        $managedRegex = [regex]::new($pattern)
        $updated = $managedRegex.Replace($existing, $replacement, 1)
    }
    else {
        $separator = if ([string]::IsNullOrWhiteSpace($existing)) { "" } else { "`n`n" }
        $updated = "$($existing.TrimEnd())$separator$managedBlock"
    }

    Set-Content -Encoding utf8 -NoNewline -LiteralPath $Destination -Value $updated
    Write-Host "MERGE $Destination"
}

if ($Scope -eq "Project") {
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        throw "-ProjectPath is required when -Scope Project is selected"
    }

    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
        throw "Project path not found: $ProjectPath"
    }

    $targetRoot = (Resolve-Path -LiteralPath $ProjectPath).Path

    if ($installCodex) {
        Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".codex/agents") -DestinationRoot (Join-Path $targetRoot ".codex/agents")
        Merge-ManagedInstructions -Source (Join-Path $packageRoot "AGENTS.md") -Destination (Join-Path $targetRoot "AGENTS.md")
    }

    if ($installCopilot) {
        Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".github/agents") -DestinationRoot (Join-Path $targetRoot ".github/agents")
        Merge-ManagedInstructions -Source (Join-Path $packageRoot ".github/copilot-instructions.md") -Destination (Join-Path $targetRoot ".github/copilot-instructions.md")
    }

    Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".agents/skills") -DestinationRoot (Join-Path $targetRoot ".agents/skills")
}
else {
    if ([string]::IsNullOrWhiteSpace($HOME)) {
        throw "HOME is not available in this PowerShell session"
    }

    $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $HOME ".codex" } else { $env:CODEX_HOME }
    $copilotHome = if ([string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) { Join-Path $HOME ".copilot" } else { $env:COPILOT_HOME }

    if ($installCodex) {
        Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".codex/agents") -DestinationRoot (Join-Path $codexHome "agents")
        Merge-ManagedInstructions -Source (Join-Path $packageRoot "AGENTS.md") -Destination (Join-Path $codexHome "AGENTS.md")
    }

    if ($installCopilot) {
        Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".github/agents") -DestinationRoot (Join-Path $copilotHome "agents")
        Merge-ManagedInstructions -Source (Join-Path $packageRoot ".github/copilot-instructions.md") -Destination (Join-Path $copilotHome "copilot-instructions.md")
    }

    Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".agents/skills") -DestinationRoot (Join-Path $HOME ".agents/skills")
}

Write-Host "Installation completed for scope $Scope and platform $Platform"
