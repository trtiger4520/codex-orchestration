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
$copilotInstructions = Read-RepoFile 'src\.github\copilot-instructions.md'
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
    'modifies security-sensitive behavior or controls',
    'Keep read-only security, migration, deployment, and architecture analysis',
    'must not trigger `orchestrate-heavy` by themselves',
    'Only the root task may dispatch subagents',
    'exactly one fenced JSON contract',
    'before command review, user approval, or dispatch',
    'Review every declarative verification command only after contract validation',
    'source boundary',
    'exactly one compact JSON object',
    'delegated_agents',
    'subagent_count` must equal the sum',
    'count: 1` for planner, explorer, and verifier',
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
Assert-Contains $planner 'Emit exactly one fenced json block and no other fenced blocks' 'Planner contract cardinality policy'
Assert-Contains $planner 'timeout_seconds' 'Planner contract policy'
Assert-Contains $planner 'expected_writes' 'Planner contract policy'
Assert-Contains $implementer 'assigned bounded subtask' 'Plan-light implementer policy'
if ($implementer.Contains('approved plan')) { throw 'Implementer still requires an approved heavy plan' }
Assert-Contains $verifySkill 'Test-SourceBoundary.ps1' 'Verifier boundary policy'
Assert-Contains $verifySkill 'Only the parent task may dispatch the verifier' 'Verifier recursion policy'
Assert-Contains $skill 'structured `verify_cmds`' 'Orchestrate v1.1 policy'
Assert-Contains $skill 'exactly one fenced JSON task contract' 'Mandatory contract extraction policy'
Assert-Contains $skill 'operating-system temporary directory outside the repository' 'Temporary contract policy'
Assert-Contains $skill 'stop without command review, user approval, or dispatch' 'Invalid contract stop policy'
Assert-Contains $skill 'Only the parent task may dispatch' 'Orchestrate recursion policy'
Assert-Contains $openAiMetadata 'allow_implicit_invocation: false' 'Orchestrate metadata'
Assert-Contains $copilotUser 'modifies security-sensitive behavior or controls' 'Copilot high-risk change policy'
Assert-Contains $copilotUser 'Keep read-only security, migration, deployment, and architecture analysis' 'Copilot read-only heavy exclusion'
Assert-Contains $copilotUser 'Only the root task may dispatch subagents' 'Copilot root-only dispatch policy'
Assert-Contains $copilotUser 'before command review, user approval, or dispatch' 'Copilot mandatory contract validation policy'
Assert-Contains $copilotUser 'delegated_agents' 'Copilot delegated agent count format'
Assert-Contains $copilotInstructions 'spawned custom agent must never spawn, delegate to, or invoke another agent' 'Copilot custom agent recursion policy'

$reasoningByRole = @{ planner = 'medium'; explorer = 'low'; implementer = 'high'; verifier = 'high' }
foreach ($agentFile in Get-ChildItem -LiteralPath (Join-Path $sourceRoot '.codex\agents') -Filter '*.toml' -File) {
    $content = Get-Content -Raw -LiteralPath $agentFile.FullName
    if ($content -match '(?m)^\s*model\s*=.*\r?$') { throw "Codex agent pins a source model: $($agentFile.FullName)" }
    Assert-Contains $content 'Never spawn, delegate to, or invoke another agent' "Codex recursion policy for $($agentFile.Name)"
    $role = $agentFile.BaseName.Substring('orchestration_'.Length)
    Assert-Contains $content ('model_reasoning_effort = "' + $reasoningByRole[$role] + '"') "Codex $role reasoning effort"
}
foreach ($agentFile in Get-ChildItem -LiteralPath (Join-Path $sourceRoot '.github\agents') -Filter '*.agent.md' -File) {
    $content = Get-Content -Raw -LiteralPath $agentFile.FullName
    if ($content -match '(?m)^model\s*:.*\r?$') { throw "Copilot agent pins a source model: $($agentFile.FullName)" }
    Assert-Contains $content 'Never spawn, delegate to, or invoke another agent' "Copilot recursion policy for $($agentFile.Name)"
}

Assert-Contains $readme 'gpt-5.6-luna' 'README model defaults'
Assert-Contains $readme 'max_threads = 3' 'README thread throttle'
Assert-Contains $readme 'max_depth = 1' 'README recursion throttle'
Assert-Contains $readme '第二層遞迴保護' 'README recursion defense explanation'
Assert-Contains $readme 'delegated_agents' 'README delegated agent count format'
Assert-Contains $readme 'lane scenario matrix 使用 v1.1' 'README lane scenario version'
Assert-Contains $readme 'lane-scenarios.v1.json' 'README scenario evaluation'
Assert-Contains $readme 'Invoke-LaneScenariosLive' 'README live evaluation'
Assert-Contains $readme '.codex-orchestration-models.json' 'README model sidecar'
Assert-Contains $readme '不會自動遷移' 'README legacy sidecar behavior'

Write-Output 'All orchestration policy tests passed'
