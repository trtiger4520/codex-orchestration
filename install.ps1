[CmdletBinding()]
param(
    [ValidateSet("User", "Project")]
    [string]$Scope = "User",

    [ValidateSet("Codex", "Copilot", "All")]
    [string]$Platform = "All",

    [string]$ProjectPath,

    [switch]$Force,

    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$packageRoot = Split-Path -Parent $PSCommandPath
$startMarker = "<!-- codex-multi-agent-orchestration:start -->"
$endMarker = "<!-- codex-multi-agent-orchestration:end -->"
$installCodex = $Platform -in @("Codex", "All")
$installCopilot = $Platform -in @("Copilot", "All")
$drift = [System.Collections.Generic.List[object]]::new()

if ($Check -and $Force) {
    throw "-Check and -Force cannot be used together"
}

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

function Add-Drift {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Missing", "Different", "MalformedMarker")]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $drift.Add([pscustomobject]@{ Kind = $Kind; Path = $Path })
}

function Test-ManagedFile {
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
        return
    }

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        Add-Drift -Kind Missing -Path $Destination
        return
    }

    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash
    $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash
    if ($sourceHash -ne $destinationHash) {
        Add-Drift -Kind Different -Path $Destination
    }
}

function Test-ManagedTree {
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
        Test-ManagedFile -Source $sourceFile.FullName -Destination (Join-Path $DestinationRoot $relativePath)
    }
}

function Get-MarkerState {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $startMatches = [regex]::Matches($Content, [regex]::Escape($startMarker))
    $endMatches = [regex]::Matches($Content, [regex]::Escape($endMarker))
    if ($startMatches.Count -eq 0 -and $endMatches.Count -eq 0) {
        return "Absent"
    }

    if ($startMatches.Count -ne 1 -or $endMatches.Count -ne 1 -or $startMatches[0].Index -gt $endMatches[0].Index) {
        return "Malformed"
    }

    return "Valid"
}

function Get-ManagedBlock {
    param(
        [Parameter(Mandatory)]
        [string]$Source
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Source file not found: $Source"
    }

    $sourceContent = (Get-Content -Raw -Encoding utf8 -LiteralPath $Source).Trim()
    return "$startMarker`n$sourceContent`n$endMarker"
}

function Test-ManagedInstructions {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (Test-SamePath -Left $Source -Right $Destination) {
        return
    }

    $managedBlock = Get-ManagedBlock -Source $Source
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        Add-Drift -Kind Missing -Path $Destination
        return
    }

    $existing = Get-Content -Raw -Encoding utf8 -LiteralPath $Destination
    switch (Get-MarkerState -Content $existing) {
        "Absent" {
            Add-Drift -Kind Missing -Path $Destination
            return
        }
        "Malformed" {
            Add-Drift -Kind MalformedMarker -Path $Destination
            return
        }
    }

    $pattern = "(?s)$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))"
    if ([regex]::Match($existing, $pattern).Value -ne $managedBlock) {
        Add-Drift -Kind Different -Path $Destination
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

    $managedBlock = Get-ManagedBlock -Source $Source
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        Set-Content -Encoding utf8 -NoNewline -LiteralPath $Destination -Value $managedBlock
        Write-Host "MERGE $Destination"
        return
    }

    $existing = Get-Content -Raw -Encoding utf8 -LiteralPath $Destination
    $markerState = Get-MarkerState -Content $existing
    if ($markerState -eq "Malformed") {
        throw "Malformed managed instruction markers: $Destination"
    }

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
        if ($Check) {
            Test-ManagedTree -SourceRoot (Join-Path $packageRoot ".codex/agents") -DestinationRoot (Join-Path $targetRoot ".codex/agents")
            Test-ManagedInstructions -Source (Join-Path $packageRoot "AGENTS.md") -Destination (Join-Path $targetRoot "AGENTS.md")
        }
        else {
            Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".codex/agents") -DestinationRoot (Join-Path $targetRoot ".codex/agents")
            Merge-ManagedInstructions -Source (Join-Path $packageRoot "AGENTS.md") -Destination (Join-Path $targetRoot "AGENTS.md")
        }
    }

    if ($installCopilot) {
        if ($Check) {
            Test-ManagedTree -SourceRoot (Join-Path $packageRoot ".github/agents") -DestinationRoot (Join-Path $targetRoot ".github/agents")
            Test-ManagedInstructions -Source (Join-Path $packageRoot ".github/copilot-instructions.md") -Destination (Join-Path $targetRoot ".github/copilot-instructions.md")
        }
        else {
            Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".github/agents") -DestinationRoot (Join-Path $targetRoot ".github/agents")
            Merge-ManagedInstructions -Source (Join-Path $packageRoot ".github/copilot-instructions.md") -Destination (Join-Path $targetRoot ".github/copilot-instructions.md")
        }
    }

    if ($Check) {
        Test-ManagedTree -SourceRoot (Join-Path $packageRoot ".agents/skills") -DestinationRoot (Join-Path $targetRoot ".agents/skills")
    }
    else {
        Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".agents/skills") -DestinationRoot (Join-Path $targetRoot ".agents/skills")
    }
}
else {
    $userHome = if ([string]::IsNullOrWhiteSpace($env:HOME)) { $HOME } else { $env:HOME }
    if ([string]::IsNullOrWhiteSpace($userHome)) {
        throw "HOME is not available in this PowerShell session"
    }

    $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $userHome ".codex" } else { $env:CODEX_HOME }
    $copilotHome = if ([string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) { Join-Path $userHome ".copilot" } else { $env:COPILOT_HOME }

    if ($installCodex) {
        if ($Check) {
            Test-ManagedTree -SourceRoot (Join-Path $packageRoot ".codex/agents") -DestinationRoot (Join-Path $codexHome "agents")
            Test-ManagedInstructions -Source (Join-Path $packageRoot "AGENTS.md") -Destination (Join-Path $codexHome "AGENTS.md")
        }
        else {
            Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".codex/agents") -DestinationRoot (Join-Path $codexHome "agents")
            Merge-ManagedInstructions -Source (Join-Path $packageRoot "AGENTS.md") -Destination (Join-Path $codexHome "AGENTS.md")
        }
    }

    if ($installCopilot) {
        $copilotUserInstructions = Join-Path $packageRoot ".github/copilot-user-instructions.md"
        if ($Check) {
            Test-ManagedTree -SourceRoot (Join-Path $packageRoot ".github/agents") -DestinationRoot (Join-Path $copilotHome "agents")
            Test-ManagedInstructions -Source $copilotUserInstructions -Destination (Join-Path $copilotHome "copilot-instructions.md")
        }
        else {
            Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".github/agents") -DestinationRoot (Join-Path $copilotHome "agents")
            Merge-ManagedInstructions -Source $copilotUserInstructions -Destination (Join-Path $copilotHome "copilot-instructions.md")
        }
    }

    if ($Check) {
        Test-ManagedTree -SourceRoot (Join-Path $packageRoot ".agents/skills") -DestinationRoot (Join-Path $userHome ".agents/skills")
    }
    else {
        Copy-ManagedTree -SourceRoot (Join-Path $packageRoot ".agents/skills") -DestinationRoot (Join-Path $userHome ".agents/skills")
    }
}

if ($Check) {
    if ($drift.Count -gt 0) {
        foreach ($item in $drift) {
            Write-Host "DRIFT [$($item.Kind)] $($item.Path)"
        }
        Write-Host "Check completed with $($drift.Count) drift item(s) for scope $Scope and platform $Platform"
        exit 1
    }

    Write-Host "Check completed with no drift for scope $Scope and platform $Platform"
}
else {
    Write-Host "Installation completed for scope $Scope and platform $Platform"
}
