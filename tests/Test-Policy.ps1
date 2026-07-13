[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path $PSScriptRoot -Parent

function Get-RepositoryContent {
    param([Parameter(Mandatory)][string]$Path)

    return Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $repositoryRoot $Path)
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Context
    )

    if (-not $Content.Contains($Expected)) {
        throw "$Context is missing '$Expected'"
    }
}

$agents = Get-RepositoryContent "AGENTS.md"
$skill = Get-RepositoryContent ".agents\skills\orchestrate\SKILL.md"
$readme = Get-RepositoryContent "README.md"
$copilotUser = Get-RepositoryContent ".github\copilot-user-instructions.md"
$openAiMetadata = Get-RepositoryContent ".agents\skills\orchestrate\agents\openai.yaml"

foreach ($lane in @("single-agent", "plan-light", "orchestrate-heavy")) {
    Assert-Contains -Content $agents -Expected $lane -Context "AGENTS.md"
    Assert-Contains -Content $readme -Expected $lane -Context "README.md"
    Assert-Contains -Content $copilotUser -Expected $lane -Context "Copilot user instructions"
}

foreach ($content in @($agents, $skill, $copilotUser)) {
    Assert-Contains -Content $content -Expected "available slots" -Context "Concurrency policy"
    Assert-Contains -Content $content -Expected "at most two" -Context "Writer limit"
    Assert-Contains -Content $content -Expected "30 seconds" -Context "Capacity retry"
    Assert-Contains -Content $content -Expected "90 seconds" -Context "Capacity retry"
    Assert-Contains -Content $content -Expected "子代理使用" -Context "Subagent usage plan"
    Assert-Contains -Content $content -Expected "模式" -Context "Subagent usage plan"
    Assert-Contains -Content $content -Expected "不使用原因" -Context "Subagent usage plan"
    Assert-Contains -Content $content -Expected "子代理結果" -Context "Subagent usage outcome"
    Assert-Contains -Content $content -Expected "已派發，角色與任務" -Context "Subagent usage outcome"
    Assert-Contains -Content $content -Expected "未使用或派發失敗原因" -Context "Subagent usage outcome"
}

Assert-Contains -Content $readme -Expected "可用 slots" -Context "README concurrency policy"
Assert-Contains -Content $readme -Expected "最多兩個" -Context "README writer limit"
Assert-Contains -Content $readme -Expected "30 秒" -Context "README capacity retry"
Assert-Contains -Content $readme -Expected "90 秒" -Context "README capacity retry"
Assert-Contains -Content $readme -Expected "子代理使用" -Context "README subagent usage plan"
Assert-Contains -Content $readme -Expected "子代理結果" -Context "README subagent usage outcome"
Assert-Contains -Content $readme -Expected "已派發，角色與任務" -Context "README dispatched roles and tasks"
Assert-Contains -Content $readme -Expected "未使用或派發失敗原因" -Context "README no-use or dispatch failure reason"

Assert-Contains -Content $agents -Expected "Stop after two failed repair cycles" -Context "AGENTS.md"
Assert-Contains -Content $skill -Expected "Stop after two failed repair cycles" -Context "orchestrate skill"
Assert-Contains -Content $openAiMetadata -Expected "allow_implicit_invocation: false" -Context "orchestrate metadata"
Assert-Contains -Content $copilotUser -Expected "Do not use the same agent context" -Context "Copilot user instructions"

$codexAgentFiles = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot ".codex\agents") -Filter "*.toml" -File
foreach ($agentFile in $codexAgentFiles) {
    $content = Get-Content -Raw -LiteralPath $agentFile.FullName
    if ($content -match '(?m)^\s*(model|model_reasoning_effort)\s*=') {
        throw "Codex agent pins a model setting: $($agentFile.FullName)"
    }
}

$copilotAgentFiles = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot ".github\agents") -Filter "*.agent.md" -File
foreach ($agentFile in $copilotAgentFiles) {
    $content = Get-Content -Raw -LiteralPath $agentFile.FullName
    if ($content -match '(?m)^model\s*:') {
        throw "Copilot agent pins a model: $($agentFile.FullName)"
    }
}

Assert-Contains -Content $readme -Expected "5.6-luna" -Context "README model defaults"
Assert-Contains -Content $readme -Expected ".codex-orchestration-models.json" -Context "README model sidecar"
Assert-Contains -Content $readme -Expected "inherit" -Context "README manual model input"
Assert-Contains -Content $readme -Expected "-Check" -Context "README non-interactive check"
Assert-Contains -Content $readme -Expected "不再次詢問模型" -Context "README non-interactive check"

Write-Output "All orchestration policy tests passed"
