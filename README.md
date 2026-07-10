# Codex 多子任務協作設定包

讓 Codex App、Codex CLI 與 GitHub Copilot 使用一致的「規劃 → 探索 → 實作 → 獨立驗收」工作流程

## 支援範圍

| 功能 | Codex App | Codex CLI | Copilot CLI | VS Code / Copilot cloud agent |
|---|---|---|---|---|
| 專責 custom agents | 支援 | 支援 | 支援 | 支援，依產品可用性而定 |
| `$orchestrate`、`$verify` skills | 支援 | 支援 | 支援 | 支援 Agent Skills 的介面可用 |
| GPT-5.6 模型分工 | 支援，需具備預覽權限 | 支援，需具備預覽權限 | 不套用 | 不套用 |
| 專案規則 | `AGENTS.md` | `AGENTS.md` | `AGENTS.md` / Copilot instructions | Copilot instructions |

## 角色與模型

| Agent | Codex 模型 | Reasoning | 職責 |
|---|---|---:|---|
| `orchestration_planner` | `gpt-5.6-sol` | `high` | 拆解需求、驗證路徑、定義驗收條件與依賴 |
| `orchestration_explorer` | `gpt-5.6-luna` | `medium` | 快速搜尋、追蹤呼叫鏈、整理現有模式 |
| `orchestration_implementer` | `gpt-5.6-terra` | `high` | 執行單一已核准子任務並自我驗證 |
| `orchestration_verifier` | `gpt-5.6-sol` | `high` | 獨立檢查完整變更並執行實際測試 |

Copilot agents 不指定 `model`，會繼承目前選取的模型或 Auto，不會引用 Copilot 尚未提供的 GPT-5.6 模型 ID

## 工作流程

1. planner 檢查實際專案並產生含驗收條件的計畫
2. 主代理向使用者顯示計畫並等待明確核准
3. explorer 針對仍不清楚的程式路徑補充證據
4. implementer 各自處理一個界線明確的子任務
5. 無相依且不共用檔案的子任務才會平行執行
6. verifier 以獨立 context 檢查完整變更並親自執行測試
7. 驗收失敗時只修正阻擋項目，最多進行兩次修正循環

`AGENTS.md` 會在三個以上檔案或三個以上步驟的工作中要求使用這套流程

## 專案結構

```text
.
├── .codex/agents/                 Codex App 與 CLI agents
├── .agents/skills/
│   ├── orchestrate/               完整協作 workflow
│   └── verify/                    獨立驗收 workflow
├── .github/agents/                GitHub Copilot agents
├── .github/copilot-instructions.md
├── AGENTS.md
├── install.ps1
└── README.md
```

`.agents/skills` 是 Codex 與 GitHub Copilot 都能讀取的共用位置，因此不需要維護兩份 skill

## 安裝

需要 PowerShell 7 以上版本

### 安裝到個人環境

預設同時安裝 Codex、Copilot 與共用 skills

```powershell
pwsh ./install.ps1
```

也可以只安裝指定平台

```powershell
pwsh ./install.ps1 -Scope User -Platform Codex
pwsh ./install.ps1 -Scope User -Platform Copilot
```

個人安裝位置：

- Codex agents：`$CODEX_HOME/agents`，未設定時使用 `$HOME/.codex/agents`
- Copilot agents：`$COPILOT_HOME/agents`，未設定時使用 `$HOME/.copilot/agents`
- 共用 skills：`$HOME/.agents/skills`

### 安裝到其他專案

目標應是已初始化的 Git repository，Codex 會以 repository root 探索專案範圍的 agents 與 skills

```powershell
pwsh ./install.ps1 -Scope Project -Platform All -ProjectPath C:\src\my-project
```

安裝器只管理本設定包的 agent 與 skill 檔案，既有指令檔以標記區塊合併，不會整份覆蓋

遇到同名但內容不同的受管理檔案時會停止，確認後可使用 `-Force` 覆寫受管理檔案或更新受管理區塊

## 使用方式

### 完整協作

在 Codex App、Codex CLI 或支援 Agent Skills 的 Copilot 介面明確指定：

```text
使用 $orchestrate 為訂單模組加入取消功能
```

planner 回報計畫後，流程會等待你核准才開始修改

### 獨立驗收

```text
使用 $verify 檢查目前所有未提交變更
```

驗收失敗時只回報需要修正的項目，不會直接修改檔案

Codex CLI 與 Copilot CLI 都可以使用 `/agent` 查看或切換 custom agent

## 權限設計

- planner 與 explorer 使用唯讀 sandbox
- implementer 使用 `workspace-write`
- verifier 在 Codex 使用 `workspace-write`，讓建置與測試可以產生正常 artifacts，但其指令禁止編輯原始碼
- Copilot planner、explorer、verifier 不提供 `edit` 工具
- 子代理仍受父工作階段的核准與 sandbox 規則約束

## GPT-5.6 權限與替代模型

GPT-5.6 Sol、Terra、Luna 目前屬於限量預覽，沒有權限時 Codex 會回報模型不可用，本設定包不會靜默降級

可依帳號實際支援狀況手動調整 `.codex/agents/*.toml`：

| 原角色 | 建議替代模型 |
|---|---|
| planner、verifier 的 `gpt-5.6-sol` | `gpt-5.4` 或帳號中目前最強的 coding model |
| implementer 的 `gpt-5.6-terra` | `gpt-5.4` 或 `gpt-5.4-mini` |
| explorer 的 `gpt-5.6-luna` | `gpt-5.4-mini`，Pro 帳號也可考慮 `gpt-5.3-codex-spark` |

修改模型後重新啟動 Codex，或開啟新的工作階段確認設定已載入

## 設計依據

- [Codex Subagents](https://developers.openai.com/codex/multi-agent)
- [Codex Build skills](https://developers.openai.com/codex/skills)
- [GPT-5.6 預覽說明](https://help.openai.com/en/articles/20001325-a-preview-of-gpt-5-6-sol-terra-and-luna)
- [GitHub Copilot custom agents 設定](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [GitHub Copilot 支援模型](https://docs.github.com/en/copilot/reference/ai-models/supported-models)
