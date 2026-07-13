[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repositoryRoot "install.ps1"
$pwsh = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "codex-orchestration-installer-$([guid]::NewGuid().ToString('N'))"
$passed = 0

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Installer {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [AllowNull()]
        [string[]]$ModelInputs = @("inherit", "", "", "inherit")
    )

    if ($null -eq $ModelInputs) {
        $output = & $pwsh -NoProfile -File $installer @Arguments 2>&1
    }
    else {
        $inputText = ($ModelInputs -join "`n") + "`n"
        $output = $inputText | & $pwsh -NoProfile -File $installer @Arguments 2>&1
    }
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output | Out-String)
    }
}

function Get-TreeSnapshot {
    param([Parameter(Mandatory)][string]$Path)

    $snapshot = [ordered]@{}
    if (Test-Path -LiteralPath $Path -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName) {
            $relative = [System.IO.Path]::GetRelativePath($Path, $file.FullName)
            $snapshot[$relative] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
        }
    }
    return ($snapshot | ConvertTo-Json -Compress)
}

function Invoke-Test {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Body
    )

    & $Body
    $script:passed++
    Write-Host "PASS  $Name"
}

New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

try {
    foreach ($platform in @("Codex", "Copilot", "All")) {
        Invoke-Test "fresh Project install and read-only check for $platform" {
            $project = Join-Path $testRoot "project-$platform"
            New-Item -ItemType Directory -Force -Path $project | Out-Null

            $install = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", $platform, "-ProjectPath", $project)
            Assert-True ($install.ExitCode -eq 0) "Install failed for ${platform}: $($install.Output)"

            $before = Get-TreeSnapshot -Path $project
            $check = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", $platform, "-ProjectPath", $project, "-Check")
            $after = Get-TreeSnapshot -Path $project
            Assert-True ($check.ExitCode -eq 0) "Check failed for ${platform}: $($check.Output)"
            Assert-True ($before -eq $after) "Check changed files for $platform"
        }
    }

    Invoke-Test "model defaults, inheritance, and generated agent settings" {
        $project = Join-Path $testRoot "model-defaults"
        New-Item -ItemType Directory -Force -Path $project | Out-Null
        $install = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $project) -ModelInputs @("inherit", "", "", "inherit")
        Assert-True ($install.ExitCode -eq 0) $install.Output

        $sidecar = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $project ".codex-orchestration-models.json") | ConvertFrom-Json
        Assert-True (-not ($sidecar.PSObject.Properties.Name -contains "planner")) "Planner default was not inherited"
        Assert-True ($sidecar.explorer -eq "5.6-luna") "Explorer default was not saved"
        Assert-True ($sidecar.implementer -eq "5.6-luna") "Implementer default was not saved"
        Assert-True (-not ($sidecar.PSObject.Properties.Name -contains "verifier")) "Verifier default was not inherited"

        foreach ($role in @("planner", "verifier")) {
            $codex = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $project ".codex/agents/orchestration_$role.toml")
            $copilot = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $project ".github/agents/orchestration_$role.agent.md")
            Assert-True ($codex -notmatch '(?m)^\s*model\s*=') "Inherited Codex model was written for $role"
            Assert-True ($copilot -notmatch '(?m)^model\s*:') "Inherited Copilot model was written for $role"
        }

        foreach ($role in @("explorer", "implementer")) {
            $codex = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $project ".codex/agents/orchestration_$role.toml")
            $copilot = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $project ".github/agents/orchestration_$role.agent.md")
            Assert-True ($codex.Contains('model = "5.6-luna"')) "Explorer or implementer Codex default was not written for $role"
            Assert-True ($copilot.Contains('model: "5.6-luna"')) "Explorer or implementer Copilot default was not written for $role"
        }
    }

    Invoke-Test "custom models are saved and Check is non-interactive and read-only" {
        $project = Join-Path $testRoot "model-custom"
        New-Item -ItemType Directory -Force -Path $project | Out-Null
        $models = @("custom-planner", "custom-explorer", "custom-implementer", "custom-verifier")
        $install = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $project) -ModelInputs $models
        Assert-True ($install.ExitCode -eq 0) $install.Output

        $sidecar = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $project ".codex-orchestration-models.json") | ConvertFrom-Json
        foreach ($role in @("planner", "explorer", "implementer", "verifier")) {
            Assert-True ($sidecar.$role -eq "custom-$role") "Custom model was not saved for $role"
            $codex = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $project ".codex/agents/orchestration_$role.toml")
            $copilot = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $project ".github/agents/orchestration_$role.agent.md")
            $expectedCodex = 'model = "' + "custom-$role" + '"'
            $expectedCopilot = 'model: "' + "custom-$role" + '"'
            Assert-True ($codex.Contains($expectedCodex)) "Custom Codex model was not written for $role"
            Assert-True ($copilot.Contains($expectedCopilot)) "Custom Copilot model was not written for $role"
        }

        $before = Get-TreeSnapshot -Path $project
        $check = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $project, "-Check") -ModelInputs $null
        $after = Get-TreeSnapshot -Path $project
        Assert-True ($check.ExitCode -eq 0) "Custom model check failed: $($check.Output)"
        Assert-True (-not $check.Output.Contains("Model for ")) "Check prompted for model input"
        Assert-True ($before -eq $after) "Check changed files or sidecar"
    }

    Invoke-Test "malformed and invalid model sidecars are rejected" {
        $cases = @(
            [pscustomobject]@{ Name = "malformed"; Content = '{"explorer":'; Expected = "Malformed model settings JSON" },
            [pscustomobject]@{ Name = "invalid"; Content = '{"explorer":42}'; Expected = "invalid model for 'explorer'" },
            [pscustomobject]@{ Name = "unknown-role"; Content = '{"unknown":"model"}'; Expected = "unknown model role" }
        )

        foreach ($case in $cases) {
            $project = Join-Path $testRoot "sidecar-$($case.Name)"
            New-Item -ItemType Directory -Force -Path $project | Out-Null
            $install = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $project) -ModelInputs @("inherit", "", "", "inherit")
            Assert-True ($install.ExitCode -eq 0) $install.Output
            Set-Content -Encoding utf8 -NoNewline -LiteralPath (Join-Path $project ".codex-orchestration-models.json") -Value $case.Content

            $check = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $project, "-Check") -ModelInputs $null
            Assert-True ($check.ExitCode -ne 0) "$($case.Name) sidecar was accepted"
            Assert-True ($check.Output.Contains($case.Expected)) "$($case.Name) sidecar error was not reported: $($check.Output)"
        }
    }

    Invoke-Test "check ignores content outside the managed block" {
        $project = Join-Path $testRoot "outside-block"
        New-Item -ItemType Directory -Force -Path $project | Out-Null
        $install = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $project)
        Assert-True ($install.ExitCode -eq 0) $install.Output

        Add-Content -Encoding utf8 -LiteralPath (Join-Path $project "AGENTS.md") -Value "`nuser content"
        Add-Content -Encoding utf8 -LiteralPath (Join-Path $project ".github/copilot-instructions.md") -Value "`nuser content"
        $check = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $project, "-Check")
        Assert-True ($check.ExitCode -eq 0) "Outside content caused drift: $($check.Output)"
    }

    Invoke-Test "check aggregates agent skill and instruction drift" {
        $project = Join-Path $testRoot "aggregate-drift"
        New-Item -ItemType Directory -Force -Path $project | Out-Null
        $install = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $project)
        Assert-True ($install.ExitCode -eq 0) $install.Output

        $agent = Get-ChildItem -LiteralPath (Join-Path $project ".codex/agents") -File | Select-Object -First 1
        $skill = Get-ChildItem -LiteralPath (Join-Path $project ".agents/skills") -Recurse -File | Select-Object -First 1
        Add-Content -Encoding utf8 -LiteralPath $agent.FullName -Value "drift"
        Add-Content -Encoding utf8 -LiteralPath $skill.FullName -Value "drift"
        $agentsPath = Join-Path $project "AGENTS.md"
        $agentsContent = Get-Content -Raw -Encoding utf8 -LiteralPath $agentsPath
        $agentsContent = $agentsContent.Replace("# Multi-agent orchestration rules", "# changed managed rules")
        Set-Content -NoNewline -Encoding utf8 -LiteralPath $agentsPath -Value $agentsContent

        $check = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $project, "-Check")
        Assert-True ($check.ExitCode -ne 0) "Drift check unexpectedly succeeded"
        Assert-True (($check.Output | Select-String -SimpleMatch "DRIFT [Different]" -Quiet)) "Different drift was not reported"
        Assert-True (($check.Output | Select-String -SimpleMatch $agent.Name -Quiet)) "Agent drift was not reported"
        Assert-True (($check.Output | Select-String -SimpleMatch $skill.Name -Quiet)) "Skill drift was not reported"
        Assert-True (($check.Output | Select-String -SimpleMatch "AGENTS.md" -Quiet)) "Instruction drift was not reported"
    }

    Invoke-Test "check reports missing targets without creating files" {
        $project = Join-Path $testRoot "missing"
        New-Item -ItemType Directory -Force -Path $project | Out-Null
        $before = Get-TreeSnapshot -Path $project
        $check = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $project, "-Check")
        $after = Get-TreeSnapshot -Path $project
        Assert-True ($check.ExitCode -ne 0) "Missing target check unexpectedly succeeded"
        Assert-True (($check.Output | Select-String -SimpleMatch "DRIFT [Missing]" -Quiet)) "Missing drift was not reported"
        Assert-True ($before -eq $after) "Missing target check created or changed files"
        Assert-True (@(Get-ChildItem -LiteralPath $project -Force).Count -eq 0) "Missing target check created directories"
    }

    Invoke-Test "check reports malformed duplicate markers" {
        $project = Join-Path $testRoot "malformed-marker"
        New-Item -ItemType Directory -Force -Path $project | Out-Null
        $install = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "Codex", "-ProjectPath", $project)
        Assert-True ($install.ExitCode -eq 0) $install.Output
        Add-Content -Encoding utf8 -LiteralPath (Join-Path $project "AGENTS.md") -Value "`n<!-- codex-multi-agent-orchestration:start -->`nduplicate`n<!-- codex-multi-agent-orchestration:end -->"

        $check = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "Codex", "-ProjectPath", $project, "-Check")
        Assert-True ($check.ExitCode -ne 0) "Malformed marker check unexpectedly succeeded"
        Assert-True (($check.Output | Select-String -SimpleMatch "DRIFT [MalformedMarker]" -Quiet)) "Malformed marker drift was not reported"
    }

    Invoke-Test "User scope isolates homes and installs self-contained Copilot instructions" {
        $userHomePath = Join-Path $testRoot "user-home"
        $codexHome = Join-Path $testRoot "custom-codex"
        $copilotHome = Join-Path $testRoot "custom-copilot"
        New-Item -ItemType Directory -Force -Path $userHomePath | Out-Null
        $oldHomeEnvironment = $env:HOME
        $oldCodexHome = $env:CODEX_HOME
        $oldCopilotHome = $env:COPILOT_HOME
        try {
            $env:HOME = $userHomePath
            $env:CODEX_HOME = $codexHome
            $env:COPILOT_HOME = $copilotHome
            $install = Invoke-Installer -Arguments @("-Scope", "User", "-Platform", "All")
            Assert-True ($install.ExitCode -eq 0) $install.Output
            $copilotInstructions = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $copilotHome "copilot-instructions.md")
            Assert-True ($copilotInstructions.Contains("# Multi-agent orchestration rules")) "User Copilot instructions are not self-contained"
            Assert-True (-not $copilotInstructions.Contains("../AGENTS.md")) "User Copilot instructions contain a project-relative link"
            Assert-True (Test-Path -LiteralPath (Join-Path $codexHome "agents") -PathType Container) "CODEX_HOME was not honored"
            Assert-True (Test-Path -LiteralPath (Join-Path $copilotHome "agents") -PathType Container) "COPILOT_HOME was not honored"
            Assert-True (Test-Path -LiteralPath (Join-Path $userHomePath ".agents/skills") -PathType Container) "HOME was not honored for shared skills"

            $before = Get-TreeSnapshot -Path $testRoot
            $check = Invoke-Installer -Arguments @("-Scope", "User", "-Platform", "All", "-Check")
            $after = Get-TreeSnapshot -Path $testRoot
            Assert-True ($check.ExitCode -eq 0) $check.Output
            Assert-True ($before -eq $after) "User check changed files"
        }
        finally {
            $env:HOME = $oldHomeEnvironment
            $env:CODEX_HOME = $oldCodexHome
            $env:COPILOT_HOME = $oldCopilotHome
        }
    }

    Invoke-Test "Check rejects Force and accepts source-equals-destination" {
        $conflict = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $repositoryRoot, "-Check", "-Force")
        Assert-True ($conflict.ExitCode -ne 0) "-Check with -Force unexpectedly succeeded"
        Assert-True (($conflict.Output | Select-String -SimpleMatch "cannot be used together" -Quiet)) "-Check with -Force did not explain the conflict"

        $samePath = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $repositoryRoot, "-Check")
        Assert-True ($samePath.ExitCode -eq 0) "Source-equals-destination check failed: $($samePath.Output)"
    }

    Invoke-Test "Project scope rejects a missing project directory" {
        $missingProject = Join-Path $testRoot "does-not-exist"
        $check = Invoke-Installer -Arguments @("-Scope", "Project", "-Platform", "All", "-ProjectPath", $missingProject, "-Check")
        Assert-True ($check.ExitCode -ne 0) "Missing project directory unexpectedly succeeded"
        Assert-True (($check.Output | Select-String -SimpleMatch "Project path not found" -Quiet)) "Missing project directory was not explained"
        Assert-True (-not (Test-Path -LiteralPath $missingProject)) "Missing project directory was created"
    }

    Write-Host "Installer tests passed: $passed"
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
