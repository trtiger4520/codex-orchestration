# Codex 多子任務協作設定包

讓 Codex App、Codex CLI 與 GitHub Copilot 使用一致的「規劃 → 探索 → 實作 → 獨立驗收」工作流程

## 支援範圍

| 功能 | Codex App | Codex CLI | Copilot CLI | VS Code / Copilot cloud agent |
|---|---|---|---|---|
| 專責 custom agents | 支援 | 支援 | 支援 | 支援，依產品可用性而定 |
| `$orchestrate`、`$verify` skills | 支援 | 支援 | 支援 | 支援 Agent Skills 的介面可用 |
| 子代理模型選擇 | 由目前工作階段與 Codex 自動選擇 | 由目前工作階段與 Codex 自動選擇 | 依目前選取的模型或 Auto | 依產品可用性而定 |
| 專案規則 | `AGENTS.md` | `AGENTS.md` | `AGENTS.md` / Copilot instructions | Copilot instructions |

## 角色與模型設定

| Agent | 模型設定 | 職責 |
|---|---|---|
| `orchestration_planner` | 不釘選 `model` 或 `model_reasoning_effort` | 拆解需求、驗證路徑、定義驗收條件與依賴 |
| `orchestration_explorer` | 不釘選 `model` 或 `model_reasoning_effort` | 快速搜尋、追蹤呼叫鏈、整理現有模式 |
| `orchestration_implementer` | 不釘選 `model` 或 `model_reasoning_effort` | 執行單一已核准子任務並自我驗證 |
| `orchestration_verifier` | 不釘選 `model` 或 `model_reasoning_effort` | 獨立檢查完整變更並執行實際測試 |

Codex custom agent 未釘選模型與推理強度時，會使用目前父工作階段的設定，或由 Codex 依任務選擇可用的設定。主代理仍決定角色、子任務與派發時機，但無法預先查詢特定服務端模型是否有容量。Copilot agents 同樣不指定 `model`，會繼承目前選取的模型或 Auto

## 工作流程

1. planner 檢查實際專案並產生含驗收條件的計畫
2. 主代理向使用者顯示計畫並等待明確核准
3. explorer 針對仍不清楚的程式路徑補充證據
4. 主代理先檢查仍在執行的子代理數與子任務相依關係
5. 每批最多派發兩個不共用檔案且無相依的 implementer，額度用完時等待既有工作完成
6. implementer 各自處理一個界線明確的子任務
7. 若派發收到 `Selected model is at capacity` 或等效的暫時性子代理可用性錯誤，主代理會在 30 秒、90 秒後，以原角色與未變更的子任務各重派一次
8. 兩次重派仍失敗時，回報原始錯誤與未完成子任務，不臆測可用模型、不自動 fallback，也不變更已核准範圍
9. verifier 以獨立 context 檢查完整變更並親自執行測試
10. 驗收失敗時只修正阻擋項目，最多進行兩次修正循環

`AGENTS.md` 會在三個以上檔案或三個以上步驟的工作中要求使用這套流程

本設定包不新增或設定 `.codex/config.toml`，因此沿用 Codex 預設的 agent thread 上限。每批兩個 implementer 是工作流程的派發規則，並非服務端模型容量預查

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

## 模型可用性與容量

此設定包不指定 GPT-5.6、Spark 或其他具名模型作為預設或 fallback。模型是否可用、容量是否足夠，皆由目前工作階段與服務端決定，沒有可在派發前使用的服務端容量預查

容量錯誤的處理方式僅限於工作流程中的兩次原任務重派。若仍無法建立子代理，會保留原始錯誤並回報未完成項目，不會靜默改派其他模型

## 設計依據

- [Codex Subagents](https://developers.openai.com/codex/multi-agent)
- [Codex Build skills](https://developers.openai.com/codex/skills)
- [GPT-5.6 預覽說明](https://help.openai.com/en/articles/20001325-a-preview-of-gpt-5-6-sol-terra-and-luna)
- [GitHub Copilot custom agents 設定](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [GitHub Copilot 支援模型](https://docs.github.com/en/copilot/reference/ai-models/supported-models)
