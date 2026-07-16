[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent

function Read-RepoFile([string]$Path) { Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $repositoryRoot $Path) }
function Assert-Contains([string]$Content, [string]$Expected, [string]$Context) {
    if (-not $Content.Contains($Expected)) { throw "$Context is missing '$Expected'" }
}

$sourceRoot = Join-Path $repositoryRoot 'src'
$agents = Read-RepoFile 'src\AGENTS.md'
$skill = Read-RepoFile 'src\.agents\skills\orchestrate\SKILL.md'
$verifySkill = Read-RepoFile 'src\.agents\skills\verify\SKILL.md'
$readme = Read-RepoFile 'README.md'
$copilotUser = Read-RepoFile 'src\.github\copilot-user-instructions.md'
$planner = Read-RepoFile 'src\.codex\agents\orchestration_planner.toml'
$implementer = Read-RepoFile 'src\.codex\agents\orchestration_implementer.toml'
$openAiMetadata = Read-RepoFile 'src\.agents\skills\orchestrate\agents\openai.yaml'

foreach ($lane in @('single-agent', 'plan-light', 'orchestrate-heavy')) {
    foreach ($item in @($agents, $readme, $copilotUser)) { Assert-Contains $item $lane 'Lane policy' }
}
foreach ($expected in @(
    'defaults to zero subagents',
    'at most one of `orchestration_explorer`, `orchestration_implementer`, or `orchestration_verifier`',
    'at least two of these signals',
    'limited local exploration first',
    'Never combine planner, explorer, implementer, and verifier roles within `plan-light`',
    'security, data migration, production deployment, core architecture, or a breaking public contract',
    'must not trigger `orchestrate-heavy` by themselves',
    'Review every declarative verification command',
    'source boundary',
    'exactly one compact JSON object',
    'input_tokens',
    'event-driven waiting',
    'original implementer context',
    'same independent verifier context',
    'Stop after two failed repair cycles',
    '30 seconds',
    '90 seconds'
)) { Assert-Contains $agents $expected 'Optimized orchestration policy' }

foreach ($legacy in @('子代理使用：', '子代理結果：')) {
    if ($agents.Contains($legacy) -or $skill.Contains($legacy) -or $copilotUser.Contains($legacy) -or $readme.Contains($legacy)) {
        throw "Legacy subagent report remains: $legacy"
    }
}

Assert-Contains $planner 'Always produce contract version 1.1' 'Planner contract policy'
Assert-Contains $planner 'timeout_seconds' 'Planner contract policy'
Assert-Contains $planner 'expected_writes' 'Planner contract policy'
Assert-Contains $implementer 'assigned bounded subtask' 'Plan-light implementer policy'
if ($implementer.Contains('approved plan')) { throw 'Implementer still requires an approved heavy plan' }
Assert-Contains $verifySkill 'Test-SourceBoundary.ps1' 'Verifier boundary policy'
Assert-Contains $skill 'structured `verify_cmds`' 'Orchestrate v1.1 policy'
Assert-Contains $openAiMetadata 'allow_implicit_invocation: false' 'Orchestrate metadata'

$reasoningByRole = @{ planner = 'medium'; explorer = 'low'; implementer = 'high'; verifier = 'high' }
foreach ($agentFile in Get-ChildItem -LiteralPath (Join-Path $sourceRoot '.codex\agents') -Filter '*.toml' -File) {
    $content = Get-Content -Raw -LiteralPath $agentFile.FullName
    if ($content -match '(?m)^\s*model\s*=.*\r?$') { throw "Codex agent pins a source model: $($agentFile.FullName)" }
    $role = $agentFile.BaseName.Substring('orchestration_'.Length)
    Assert-Contains $content ('model_reasoning_effort = "' + $reasoningByRole[$role] + '"') "Codex $role reasoning effort"
}
foreach ($agentFile in Get-ChildItem -LiteralPath (Join-Path $sourceRoot '.github\agents') -Filter '*.agent.md' -File) {
    if ((Get-Content -Raw -LiteralPath $agentFile.FullName) -match '(?m)^model\s*:.*\r?$') { throw "Copilot agent pins a source model: $($agentFile.FullName)" }
}

Assert-Contains $readme 'gpt-5.6-luna' 'README model defaults'
Assert-Contains $readme 'max_threads = 3' 'README thread throttle'
Assert-Contains $readme 'max_depth = 1' 'README recursion throttle'
Assert-Contains $readme 'lane-scenarios.v1.json' 'README scenario evaluation'
Assert-Contains $readme 'Invoke-LaneScenariosLive' 'README live evaluation'
Assert-Contains $readme '.codex-orchestration-models.json' 'README model sidecar'
Assert-Contains $readme '不會自動遷移' 'README legacy sidecar behavior'

Write-Output 'All orchestration policy tests passed'
