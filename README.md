# Codex 多子任務協作設定包

讓 Codex App、Codex CLI 與 GitHub Copilot 使用一致的「規劃 → 探索 → 實作 → 獨立驗收」工作流程

## 支援範圍

| 功能 | Codex App | Codex CLI | Copilot CLI | VS Code / Copilot cloud agent |
|---|---|---|---|---|
| 專責 custom agents | 支援 | 支援 | 支援 | 支援，依產品可用性而定 |
| `$orchestrate`、`$verify` skills | 支援 | 支援 | 支援 | 支援 Agent Skills 的介面可用 |
| 子代理模型選擇 | 由安裝時設定，未指定時繼承 | 由安裝時設定，未指定時繼承 | 由安裝時設定，未指定時繼承 | 依產品可用性而定 |
| 專案規則 | `AGENTS.md` | `AGENTS.md` | `AGENTS.md` / Copilot instructions | Copilot instructions |

## 角色與模型設定

| Agent | 模型設定 | 職責 |
|---|---|---|
| `orchestration_planner` | 預設繼承，不寫入 `model`；可手動指定 | 拆解需求、驗證路徑、定義驗收條件與依賴 |
| `orchestration_explorer` | 預設 `5.6-luna`；可手動指定或改為繼承 | 快速搜尋、追蹤呼叫鏈、整理現有模式 |
| `orchestration_implementer` | 預設 `5.6-luna`；可手動指定或改為繼承 | 執行單一已核准子任務並自我驗證 |
| `orchestration_verifier` | 預設繼承，不寫入 `model`；可手動指定 | 獨立檢查完整變更並執行實際測試 |

Codex custom agent 的 `model_reasoning_effort` 始終不由本設定包釘選。模型欄位由安裝器依互動設定寫入，使用 `inherit` 時會省略 Codex TOML 的 `model` 與 Copilot agent front matter 的 `model`，交由目前父工作階段、目前選取的模型或產品設定處理

非 `-Check` 安裝會依序詢問 planner、explorer、implementer、verifier 的模型。提示中的 `Enter=default` 會採用該角色預設值，輸入 `inherit` 會省略模型欄位，也可以直接輸入自訂模型名稱。安裝器不接受空白模型名稱或包含換行的輸入

模型設定會保存於 sidecar：Project Scope 是目標專案根目錄的 `.codex-orchestration-models.json`，User Scope 是 `$HOME/.codex-orchestration-models.json`。sidecar 只保存非繼承的模型值，重新執行 `-Check` 時會讀取該檔案、不再次詢問模型，也不建立或更新任何檔案

## 工作流程

主代理先依風險與協作需求選擇執行 lane：

- `single-agent`：熟悉路徑中的日常低風險工作
- `plan-light`：需要簡短規劃，但不需要完整角色分離
- `orchestrate-heavy`：高風險、跨模組、陌生路徑、需要獨立驗收，或使用者明確要求完整協作

檔案數與步驟數只作為評估訊號，不會單獨觸發完整流程。若目前介面明確提供原生動態委派且未指定 `$orchestrate`，主代理可優先使用原生能力；本設定包不偵測或假設特定 Ultra 模式

### 子代理使用回報

任務分類後、開始工作前，主代理必須回報是否使用子代理與模式：

```text
子代理使用：<是|否>｜模式：<single-agent|plan-light|orchestrate-heavy>｜不使用原因：<...>
```

任務完成時，主代理必須回報實際派發結果，讓使用者能區分已派發、未使用與派發失敗：

```text
子代理結果：<已派發，角色與任務：... | 未派發，未使用或派發失敗原因：...>
```

未使用子代理時，須填寫原因。派發失敗時，需填寫觀察到的錯誤與重派結果

`orchestrate-heavy` 流程如下：

1. planner 檢查實際專案，產生 200 字內 Markdown 摘要及符合 schema 的 JSON task contract
2. 主代理向使用者顯示計畫並等待明確核准
3. explorer 針對仍不清楚的程式路徑補充證據
4. 主代理檢查可用 slots、task mode、風險、相依關係與檔案衝突
5. 無相依的唯讀工作使用當下可用 slots；寫入工作最多兩個，高風險工作固定單 writer，同一 conflict cluster 依序執行
6. implementer 各自處理一個界線明確且已核准的子任務
7. 若派發收到 `Selected model is at capacity` 或等效的暫時性子代理可用性錯誤，主代理會在 30 秒、90 秒後，以原角色與未變更的子任務各重派一次
8. 兩次重派仍失敗時，回報原始錯誤與未完成子任務，不臆測可用模型、不自動 fallback，也不變更已核准範圍
9. verifier 以獨立 context 檢查完整變更並親自執行測試
10. 驗收失敗時只修正阻擋項目，最多進行兩次修正循環

本設定包不新增或設定 `.codex/config.toml`，因此沿用目前介面的 agent thread 上限。動態 read 併發與最多兩個 writers 都是工作流程規則，不是服務端容量預查，也不會為提高併發指定模型或修改 thread 上限

## 專案結構

```text
.
├── src/                            安裝器使用的主要設定內容
│   ├── .codex/agents/              Codex App 與 CLI agents
│   ├── .agents/skills/
│   │   ├── orchestrate/            完整協作 workflow、contract schema 與 validator
│   │   └── verify/                 獨立驗收 workflow
│   ├── .github/agents/              GitHub Copilot agents
│   ├── .github/copilot-instructions.md
│   ├── .github/copilot-user-instructions.md
│   └── AGENTS.md
├── tests/                          PowerShell 與 Bash 的安裝器及 contract 測試
├── install.ps1                     Windows 安裝器
├── install.sh                      macOS 與 Linux 安裝器
└── README.md
```

安裝器位於專案根目錄，但所有受管理的 agents、skills、instructions 與 `AGENTS.md` 都從 `src` 讀取，避免執行時把套件根目錄的文件誤當成目標專案規則重複載入

`.agents/skills` 是 Codex 與 GitHub Copilot 都能讀取的共用位置，因此不需要維護兩份 skill

## 安裝

Windows 需要 PowerShell 7 以上版本

macOS 與 Linux 需要 Bash 3.2 以上版本，以及 `shasum` 或 `sha256sum`。macOS 內建 Bash 可直接使用

在 Bash 環境驗證 orchestration plan 時，另需 Python 3；validator 僅使用 Python 標準函式庫，不需要安裝套件

Bash 安裝器在模型設定、agent 內容轉換與 sidecar 保存或讀取時需要 `python3`。`tests/Test-Installer.sh` 在找不到 `python3` 時會明確略過相依模型的測試，仍執行不涉及 sidecar 的檢查

### 安裝到個人環境

預設同時安裝 Codex、Copilot 與共用 skills

```powershell
pwsh ./install.ps1
```

macOS 與 Linux：

```bash
bash ./install.sh
```

也可以只安裝指定平台

```powershell
pwsh ./install.ps1 -Scope User -Platform Codex
pwsh ./install.ps1 -Scope User -Platform Copilot
```

```bash
bash ./install.sh --scope user --platform codex
bash ./install.sh --scope user --platform copilot
```

個人安裝位置：

- Codex agents：`$CODEX_HOME/agents`，未設定時使用 `$HOME/.codex/agents`
- Copilot agents：`$COPILOT_HOME/agents`，未設定時使用 `$HOME/.copilot/agents`
- 共用 skills：`$HOME/.agents/skills`

User Scope 的 Copilot instructions 會安裝完整自包含規則，不依賴專案相對路徑；Project Scope 仍透過專案內的 `AGENTS.md` 共用規則

### 安裝到其他專案

目標應是已初始化的 Git repository，Codex 會以 repository root 探索專案範圍的 agents 與 skills

```powershell
pwsh ./install.ps1 -Scope Project -Platform All -ProjectPath C:\src\my-project
```

```bash
bash ./install.sh --scope project --platform all --project-path ~/src/my-project
```

安裝器只管理本設定包的 agent 與 skill 檔案，既有指令檔以標記區塊合併，不會整份覆蓋

遇到同名但內容不同的受管理檔案時會停止，確認後可使用 `-Force` 覆寫受管理檔案或更新受管理區塊

使用 `-Check` 可唯讀檢查受管理 agent、skill、schema、validator 與 instruction block 是否缺少、不同或標記損壞。檢查會列出所有 drift 並以非零 exit code 結束，不會建立或更新檔案；`-Check` 不可與 `-Force` 同時使用

```powershell
pwsh ./install.ps1 -Scope Project -Platform All -ProjectPath C:\src\my-project -Check
```

```bash
bash ./install.sh --scope project --platform all --project-path ~/src/my-project --check
```

## 使用方式

### 完整協作

在 Codex App、Codex CLI 或支援 Agent Skills 的 Copilot 介面明確指定：

```text
使用 $orchestrate 為訂單模組加入取消功能
```

planner 回報計畫後，流程會等待你核准才開始修改

planner 的 fenced JSON contract 使用 `.agents/skills/orchestrate/references/orchestration-plan.schema.json`，可在 materialize 成 JSON 檔後驗證：

```powershell
pwsh ./.agents/skills/orchestrate/scripts/Test-OrchestrationPlan.ps1 -PlanFile ./plan.json
```

macOS 與 Linux：

```bash
bash ./.agents/skills/orchestrate/scripts/Test-OrchestrationPlan.sh --plan-file ./plan.json
```

執行完整套件測試：

```powershell
pwsh ./tests/Test-Package.ps1
```

在 macOS 與 Linux，可執行 Bash installer 與 contract 測試：

```bash
bash ./tests/Test-Installer.sh
bash ./tests/Test-Contract.sh
```

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

安裝器只將 `5.6-luna` 設為 explorer 與 implementer 的初始預設，不將 GPT-5.6、Spark 或其他具名模型作為全域 fallback。模型是否可用、容量是否足夠，皆由目前工作階段與服務端決定，沒有可在派發前使用的服務端容量預查

容量錯誤的處理方式僅限於工作流程中的兩次原任務重派。若仍無法建立子代理，會保留原始錯誤並回報未完成項目，不會靜默改派其他模型

## 設計依據

- [Codex Subagents](https://developers.openai.com/codex/multi-agent)
- [Codex Build skills](https://developers.openai.com/codex/skills)
- [GPT-5.6 預覽說明](https://help.openai.com/en/articles/20001325-a-preview-of-gpt-5-6-sol-terra-and-luna)
- [GitHub Copilot custom agents 設定](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [GitHub Copilot 支援模型](https://docs.github.com/en/copilot/reference/ai-models/supported-models)
