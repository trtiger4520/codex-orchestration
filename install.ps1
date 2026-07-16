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
$sourceRoot = Join-Path $packageRoot "src"
$startMarker = "<!-- codex-multi-agent-orchestration:start -->"
$endMarker = "<!-- codex-multi-agent-orchestration:end -->"
$installCodex = $Platform -in @("Codex", "All")
$installCopilot = $Platform -in @("Copilot", "All")
$drift = [System.Collections.Generic.List[object]]::new()
$modelDefaults = [ordered]@{
    planner = $null
    explorer = "gpt-5.6-luna"
    implementer = "gpt-5.6-luna"
    verifier = $null
}
$modelSettings = [ordered]@{}

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
        $role = Get-AgentRole -Source $sourceFile.FullName
        if ($null -eq $role -or (Test-SamePath -Left $sourceFile.FullName -Right $destinationFile)) {
            Copy-ManagedFile -Source $sourceFile.FullName -Destination $destinationFile
            continue
        }

        $temporaryFile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-agent-" + [guid]::NewGuid().ToString("N"))
        try {
            Set-Content -Encoding utf8 -NoNewline -LiteralPath $temporaryFile -Value (Get-ConfiguredAgentContent -Source $sourceFile.FullName -Role $role -Model $modelSettings[$role])
            Copy-ManagedFile -Source $temporaryFile -Destination $destinationFile
        }
        finally {
            Remove-Item -Force -LiteralPath $temporaryFile -ErrorAction SilentlyContinue
        }
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
        $destinationFile = Join-Path $DestinationRoot $relativePath
        $role = Get-AgentRole -Source $sourceFile.FullName
        if ($null -eq $role) {
            Test-ManagedFile -Source $sourceFile.FullName -Destination $destinationFile
            continue
        }

        Test-ManagedAgentFile -Source $sourceFile.FullName -Destination $destinationFile -Role $role -Model $modelSettings[$role]
    }
}

function Get-AgentRole {
    param(
        [Parameter(Mandatory)]
        [string]$Source
    )

    $fileName = [System.IO.Path]::GetFileName($Source)
    if ($fileName.EndsWith(".toml", [System.StringComparison]::OrdinalIgnoreCase)) {
        $name = $fileName.Substring(0, $fileName.Length - 5)
    }
    elseif ($fileName.EndsWith(".agent.md", [System.StringComparison]::OrdinalIgnoreCase)) {
        $name = $fileName.Substring(0, $fileName.Length - 9)
    }
    else {
        return $null
    }

    if ($name.StartsWith("orchestration_", [System.StringComparison]::OrdinalIgnoreCase)) {
        $role = $name.Substring(14).ToLowerInvariant()
        if ($modelDefaults.Contains($role)) {
            return $role
        }
    }

    return $null
}

function Escape-DoubleQuotedValue {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $builder = [System.Text.StringBuilder]::new()
    foreach ($character in $Value.ToCharArray()) {
        $code = [int][char]$character
        if ($character -eq '\') {
            [void]$builder.Append('\\')
        }
        elseif ($character -eq '"') {
            [void]$builder.Append('\"')
        }
        elseif ($character -eq "`b") {
            [void]$builder.Append('\b')
        }
        elseif ($character -eq "`t") {
            [void]$builder.Append('\t')
        }
        elseif ($character -eq "`n") {
            [void]$builder.Append('\n')
        }
        elseif ($character -eq "`f") {
            [void]$builder.Append('\f')
        }
        elseif ($character -eq "`r") {
            [void]$builder.Append('\r')
        }
        elseif ($code -lt 0x20 -or $code -eq 0x7f) {
            [void]$builder.Append(('\u{0:X4}' -f $code))
        }
        else {
            [void]$builder.Append($character)
        }
    }

    return $builder.ToString()
}

function Get-ConfiguredAgentContent {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Role,

        [AllowNull()]
        [string]$Model
    )

    $content = Get-Content -Raw -Encoding utf8 -LiteralPath $Source
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [regex]::Split($content, "\r\n|\n|\r")
    $escapedModel = if ([string]::IsNullOrEmpty($Model)) { $null } else { Escape-DoubleQuotedValue -Value $Model }

    if ($Source.EndsWith(".toml", [System.StringComparison]::OrdinalIgnoreCase)) {
        $lines = @($lines | Where-Object { $_ -notmatch '^\s*model\s*=' })
        if ($null -ne $escapedModel) {
            $nameIndex = -1
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -match '^\s*name\s*=') {
                    $nameIndex = $index
                    break
                }
            }

            if ($nameIndex -lt 0) {
                $lines = @('model = "' + $escapedModel + '"') + $lines
            }
            else {
                $before = @($lines[0..$nameIndex])
                $after = if ($nameIndex + 1 -lt $lines.Count) { @($lines[($nameIndex + 1)..($lines.Count - 1)]) } else { @() }
                $lines = $before + @('model = "' + $escapedModel + '"') + $after
            }
        }
    }
    else {
        if ($lines.Count -lt 2 -or $lines[0].Trim() -ne "---") {
            throw "Malformed Copilot agent front matter: $Source"
        }

        $frontMatterEnd = -1
        for ($index = 1; $index -lt $lines.Count; $index++) {
            if ($lines[$index].Trim() -eq "---") {
                $frontMatterEnd = $index
                break
            }
        }

        if ($frontMatterEnd -lt 0) {
            throw "Malformed Copilot agent front matter: $Source"
        }

        $prefix = @($lines[0])
        $frontMatter = if ($frontMatterEnd -gt 1) { @($lines[1..($frontMatterEnd - 1)] | Where-Object { $_ -notmatch '^\s*model\s*:' }) } else { @() }
        $suffix = @($lines[$frontMatterEnd..($lines.Count - 1)])
        if ($null -ne $escapedModel) {
            $frontMatter = @('model: "' + $escapedModel + '"') + $frontMatter
        }
        $lines = $prefix + $frontMatter + $suffix
    }

    return [string]::Join($newline, $lines)
}

function Test-ManagedAgentFile {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$Role,

        [AllowNull()]
        [string]$Model
    )

    if (Test-SamePath -Left $Source -Right $Destination) {
        return
    }

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        Add-Drift -Kind Missing -Path $Destination
        return
    }

    $sourceBytes = [System.Text.Encoding]::UTF8.GetBytes((Get-ConfiguredAgentContent -Source $Source -Role $Role -Model $Model))
    $sourceHash = [System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create().ComputeHash($sourceBytes))).Replace('-', '')
    $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash
    if (-not $sourceHash.Equals($destinationHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Drift -Kind Different -Path $Destination
    }
}

function Get-ModelSetting {
    param(
        [Parameter(Mandatory)]
        [string]$Role,

        [AllowNull()]
        [string]$Default
    )

    $defaultLabel = if ($null -eq $Default) { "inherit" } else { $Default }
    while ($true) {
        $value = Read-Host "Model for $Role [$defaultLabel] (Enter=default, inherit=inherit)"
        if ([string]::IsNullOrEmpty($value)) {
            return $Default
        }
        if ($value -ieq "inherit") {
            return $null
        }
        if ($value -match '[\r\n]' -or [string]::IsNullOrWhiteSpace($value)) {
            Write-Host "Model must be non-empty and must not contain a newline"
            continue
        }

        return $value
    }
}

function Read-ModelSettings {
    param(
        [Parameter(Mandatory)]
        [string]$SidecarPath,

        [Parameter(Mandatory)]
        [bool]$Interactive
    )

    $settings = [ordered]@{}
    foreach ($role in $modelDefaults.Keys) {
        $settings[$role] = $modelDefaults[$role]
    }

    if ($Interactive) {
        foreach ($role in $modelDefaults.Keys) {
            $settings[$role] = Get-ModelSetting -Role $role -Default $modelDefaults[$role]
        }
        return $settings
    }

    if (-not (Test-Path -LiteralPath $SidecarPath -PathType Leaf)) {
        return $settings
    }

    try {
        $parsed = Get-Content -Raw -Encoding utf8 -LiteralPath $SidecarPath | ConvertFrom-Json -NoEnumerate
    }
    catch {
        throw "Malformed model settings JSON: $SidecarPath"
    }

    if ($null -eq $parsed -or
        $parsed -isnot [System.Management.Automation.PSObject] -or
        $parsed -is [array] -or
        $parsed -is [string] -or
        $parsed -is [System.ValueType]) {
        throw "Malformed model settings JSON: $SidecarPath"
    }

    foreach ($property in $parsed.PSObject.Properties) {
        if (-not $modelDefaults.Contains($property.Name)) {
            throw "Malformed model settings JSON: unknown model role '$($property.Name)' in $SidecarPath"
        }
        if ($null -eq $property.Value) {
            $settings[$property.Name] = $null
            continue
        }
        if ($property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($property.Value) -or $property.Value -match '[\r\n]') {
            throw "Malformed model settings JSON: invalid model for '$($property.Name)' in $SidecarPath"
        }
        $settings[$property.Name] = $property.Value
    }

    return $settings
}

function Save-ModelSettings {
    param(
        [Parameter(Mandatory)]
        [string]$SidecarPath
    )

    $saved = [ordered]@{}
    foreach ($role in $modelDefaults.Keys) {
        if ($null -ne $modelSettings[$role]) {
            $saved[$role] = $modelSettings[$role]
        }
    }

    $parent = Split-Path -Parent $SidecarPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -Encoding utf8 -NoNewline -LiteralPath $SidecarPath -Value ($saved | ConvertTo-Json -Compress)
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

function Write-DuplicateScopeWarning {
    if (-not $installCodex -or $Scope -ne "Project") {
        return
    }

    $userHome = if ([string]::IsNullOrWhiteSpace($env:HOME)) { $HOME } else { $env:HOME }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        if ([string]::IsNullOrWhiteSpace($userHome)) {
            return
        }
        $globalAgentsPath = Join-Path $userHome ".codex/AGENTS.md"
    }
    else {
        $globalAgentsPath = Join-Path $env:CODEX_HOME "AGENTS.md"
    }

    if (-not (Test-Path -LiteralPath $globalAgentsPath -PathType Leaf)) {
        return
    }

    $globalContent = Get-Content -Raw -Encoding utf8 -LiteralPath $globalAgentsPath
    if ($globalContent.Contains($startMarker) -or $globalContent.Contains($endMarker)) {
        Write-Host "WARN  Duplicate managed orchestration instructions found in $globalAgentsPath; keep the complete rules in either User or Project scope"
    }
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
    Write-DuplicateScopeWarning
    $modelSidecar = Join-Path $targetRoot ".codex-orchestration-models.json"
    $modelSettings = Read-ModelSettings -SidecarPath $modelSidecar -Interactive (-not $Check)

    if ($installCodex) {
        if ($Check) {
            Test-ManagedTree -SourceRoot (Join-Path $sourceRoot ".codex/agents") -DestinationRoot (Join-Path $targetRoot ".codex/agents")
            Test-ManagedInstructions -Source (Join-Path $sourceRoot "AGENTS.md") -Destination (Join-Path $targetRoot "AGENTS.md")
        }
        else {
            Copy-ManagedTree -SourceRoot (Join-Path $sourceRoot ".codex/agents") -DestinationRoot (Join-Path $targetRoot ".codex/agents")
            Merge-ManagedInstructions -Source (Join-Path $sourceRoot "AGENTS.md") -Destination (Join-Path $targetRoot "AGENTS.md")
        }
    }

    if ($installCopilot) {
        if ($Check) {
            Test-ManagedTree -SourceRoot (Join-Path $sourceRoot ".github/agents") -DestinationRoot (Join-Path $targetRoot ".github/agents")
            Test-ManagedInstructions -Source (Join-Path $sourceRoot ".github/copilot-instructions.md") -Destination (Join-Path $targetRoot ".github/copilot-instructions.md")
        }
        else {
            Copy-ManagedTree -SourceRoot (Join-Path $sourceRoot ".github/agents") -DestinationRoot (Join-Path $targetRoot ".github/agents")
            Merge-ManagedInstructions -Source (Join-Path $sourceRoot ".github/copilot-instructions.md") -Destination (Join-Path $targetRoot ".github/copilot-instructions.md")
        }
    }

    if ($Check) {
        Test-ManagedTree -SourceRoot (Join-Path $sourceRoot ".agents/skills") -DestinationRoot (Join-Path $targetRoot ".agents/skills")
    }
    else {
        Copy-ManagedTree -SourceRoot (Join-Path $sourceRoot ".agents/skills") -DestinationRoot (Join-Path $targetRoot ".agents/skills")
    }

    if (-not $Check) {
        Save-ModelSettings -SidecarPath $modelSidecar
    }
}
else {
    $userHome = if ([string]::IsNullOrWhiteSpace($env:HOME)) { $HOME } else { $env:HOME }
    if ([string]::IsNullOrWhiteSpace($userHome)) {
        throw "HOME is not available in this PowerShell session"
    }

    $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $userHome ".codex" } else { $env:CODEX_HOME }
    $copilotHome = if ([string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) { Join-Path $userHome ".copilot" } else { $env:COPILOT_HOME }
    $modelSidecar = Join-Path $userHome ".codex-orchestration-models.json"
    $modelSettings = Read-ModelSettings -SidecarPath $modelSidecar -Interactive (-not $Check)

    if ($installCodex) {
        if ($Check) {
            Test-ManagedTree -SourceRoot (Join-Path $sourceRoot ".codex/agents") -DestinationRoot (Join-Path $codexHome "agents")
            Test-ManagedInstructions -Source (Join-Path $sourceRoot "AGENTS.md") -Destination (Join-Path $codexHome "AGENTS.md")
        }
        else {
            Copy-ManagedTree -SourceRoot (Join-Path $sourceRoot ".codex/agents") -DestinationRoot (Join-Path $codexHome "agents")
            Merge-ManagedInstructions -Source (Join-Path $sourceRoot "AGENTS.md") -Destination (Join-Path $codexHome "AGENTS.md")
        }
    }

    if ($installCopilot) {
        $copilotUserInstructions = Join-Path $sourceRoot ".github/copilot-user-instructions.md"
        if ($Check) {
            Test-ManagedTree -SourceRoot (Join-Path $sourceRoot ".github/agents") -DestinationRoot (Join-Path $copilotHome "agents")
            Test-ManagedInstructions -Source $copilotUserInstructions -Destination (Join-Path $copilotHome "copilot-instructions.md")
        }
        else {
            Copy-ManagedTree -SourceRoot (Join-Path $sourceRoot ".github/agents") -DestinationRoot (Join-Path $copilotHome "agents")
            Merge-ManagedInstructions -Source $copilotUserInstructions -Destination (Join-Path $copilotHome "copilot-instructions.md")
        }
    }

    if ($Check) {
        Test-ManagedTree -SourceRoot (Join-Path $sourceRoot ".agents/skills") -DestinationRoot (Join-Path $userHome ".agents/skills")
    }
    else {
        Copy-ManagedTree -SourceRoot (Join-Path $sourceRoot ".agents/skills") -DestinationRoot (Join-Path $userHome ".agents/skills")
    }

    if (-not $Check) {
        Save-ModelSettings -SidecarPath $modelSidecar
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
