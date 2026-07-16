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

| Agent | 模型設定 | Reasoning | 職責 |
|---|---|---|---|
| `orchestration_planner` | 預設繼承，不寫入 `model`；可手動指定 | `medium` | 產生以完整交付單元分組的計畫與驗收條件 |
| `orchestration_explorer` | 預設 `gpt-5.6-luna`；可手動指定或改為繼承 | `low` | 快速搜尋、追蹤呼叫鏈、整理現有模式 |
| `orchestration_implementer` | 預設 `gpt-5.6-luna`；可手動指定或改為繼承 | `high` | 完成一個 bounded cohesive delivery unit 並執行窄範圍驗證 |
| `orchestration_verifier` | 預設繼承，不寫入 `model`；可手動指定 | `high` | 獨立檢查完整變更並執行實際測試 |

Codex custom agent 固定使用表中的 `model_reasoning_effort`，避免所有角色繼承父工作階段的高推理強度；安裝器仍只依互動設定轉換 `model`，不擴充 sidecar；使用 `inherit` 時會省略 Codex TOML 與 Copilot front matter 的 `model`；Copilot agent 不加入未確認支援的 reasoning 欄位

非 `-Check` 安裝會依序詢問 planner、explorer、implementer、verifier 的模型。提示中的 `Enter=default` 會採用該角色預設值，輸入 `inherit` 會省略模型欄位，也可以直接輸入自訂模型名稱。安裝器不接受空白模型名稱或包含換行的輸入

模型設定會保存於 sidecar：Project Scope 是目標專案根目錄的 `.codex-orchestration-models.json`，User Scope 是 `$HOME/.codex-orchestration-models.json`。sidecar 只保存非繼承的模型值，重新執行 `-Check` 時會讀取該檔案、不再次詢問模型，也不建立或更新任何檔案

舊 sidecar 中明確保存的 `5.6-luna` 會被視為使用者設定，`-Check` 不會自動遷移；只有重新執行互動安裝並採用新預設時，才會保存完整 ID `gpt-5.6-luna`

## 工作流程

主代理先依風險與協作需求選擇執行 lane：

- `single-agent`：已知路徑、局部修改，或可由確定性工具直接驗證的日常低風險工作，不建立子代理
- `plan-light`：需要短計畫的非高風險工作，預設零子代理；如委派具明確收益，最多從 explorer、implementer、verifier 選一種角色且只派一個
- `orchestrate-heavy`：僅限使用者明確要求完整協作，或工作會修改安全敏感行為或控制、遷移或轉換持久化資料或 schema、改變正式環境狀態、修改核心架構、造成 breaking public contract

檔案數、步驟數、跨模組、跨平台與陌生路徑都不會單獨觸發完整流程；純唯讀的安全、migration、部署或架構分析依一般 delegation gate 使用 `single-agent` 或 `plan-light`；單獨要求獨立驗證時只需增加 verifier，不強制建立其他角色

### 委派閘門

主代理會先做有限探索，且至少符合以下兩項才委派：

- 可獨立完成且不需要頻繁交換上下文
- 會產生大量搜尋結果、log 或中間證據
- 有明確輸入、停止條件與精簡輸出格式
- 主代理同時有其他獨立工作可進行
- 能隔離大量主上下文噪音
- 結果可觀察或能以確定性工具驗證

已知少量修改、主代理已掌握上下文、需要連續設計決策、委派後仍須完整重做，或只是執行既有 build、lint、test 時不委派；有限探索無法快速收斂時，才升級為單一 explorer

### 完成紀錄

每個任務完成時只輸出一筆精簡 JSON，不自動寫入 repository。欄位包含 `lane`、`delegated_agents`、`delegation_reason`、`subagent_count`、`dispatch_status`、`dispatch_error`、`repair_cycles`、`verification_result`、`files_changed`，以及有工具證據時才填值的 `input_tokens`、`output_tokens`、`elapsed_seconds`；`delegated_agents` 使用唯一的 `{ "role": "<role>", "count": <count> }` 項目，planner、explorer、verifier 的 count 固定為 `1`，implementer 可為 `1` 或 `2`，`subagent_count` 必須等於所有 `count` 總和；未委派時使用空陣列與 `0`

`orchestrate-heavy` 流程如下：

1. 派發前確認作業系統，以及 PowerShell、Bash、Python 或 bundled runtime 等驗證工具鏈
2. planner 檢查實際專案，產生 200 字內 Markdown 摘要及恰好一個符合 schema 的 fenced JSON task contract，並按 cohesive delivery unit 分組，不機械拆分產品碼、測試與文件
3. 主代理將 contract 寫入 repository 外的作業系統暫存目錄，Windows 執行 PowerShell validator，macOS／Linux 執行 Bash validator
4. contract 擷取或驗證失敗時立即停止，不進行命令審查、使用者核准或任何派發，並回報 validator 錯誤
5. contract 通過後，parent 才審查結構化驗證命令；未另行核准時拒絕 shell chaining、重導向、套件安裝、網路存取與破壞性操作
6. 主代理向使用者顯示已驗證計畫並等待明確核准
7. explorer 只針對仍不清楚的程式路徑補充證據
8. 主代理檢查可用 slots、風險、相依關係與檔案衝突，使用最少 writers 且最多兩個，高風險工作固定單 writer
9. implementer 各自處理一個完整且已核准的交付單元；`plan-light` implementer 則可處理邊界穩定且驗收條件清楚的 bounded task，不要求 heavy plan
10. 若派發收到 `Selected model is at capacity` 或等效的暫時性子代理可用性錯誤，主代理會在 30 秒、90 秒後，以原角色與未變更的子任務各重派一次
11. 兩次重派仍失敗時，回報原始錯誤與未完成子任務，不臆測可用模型、不自動 fallback，也不變更已核准範圍
12. verifier 前後使用 source-boundary guard 比較 tracked 與 non-ignored untracked 檔案雜湊，只允許已審查的 build/test artifact globs
13. verifier 以單一獨立 context 檢查完整變更並親自執行測試；來源檔案越界時驗證結果失效
14. 驗收失敗時交回原 implementer context，並由同一 verifier context 複驗；每次只重跑失敗檢查，blocker 清除後完整套件只執行一次，最多兩次修正循環
15. 工作流程成功或失敗結束時都清除暫存 contract

子代理協調優先使用介面原生工具與事件式等待，不把等待包進一般 `exec`；介面沒有事件式等待時，每 30 至 60 秒檢查一次，只有狀態變化才回報；測試命名、格式偏好或已有等效覆蓋的追溯性意見列為 non-blocking note

本設定包不新增或設定 `.codex/config.toml`，因此沿用目前介面的 agent thread 上限。若希望限制 Token 峰值，可自行加入以下選配設定，安裝器不會代為修改：

```toml
[agents]
max_threads = 3
max_depth = 1
```

只有 root task 可以派發子代理；任何 spawned agent 都不得再 spawn、delegate 或 invoke 其他 agent。`max_depth = 1` 是第二層遞迴保護，不取代角色本身的禁止委派規則

動態 read 併發與最多兩個 writers 都是工作流程規則，不是服務端容量預查，也不會為提高併發指定模型或修改 thread 上限

## 專案結構

```text
.
├── src/                            安裝器使用的主要設定內容
│   ├── .codex/agents/              Codex App 與 CLI agents
│   ├── .agents/skills/
│   │   ├── orchestrate/            完整協作 workflow、v1.1 contract 與 lane scenario eval
│   │   └── verify/                 獨立驗收 workflow 與 source-boundary guard
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

既有安裝需重新執行安裝器並使用 `-Force`，才會取得新的 lane 政策與 reasoning 預設

Project Scope 安裝 Codex 或 All 時，若 `$CODEX_HOME/AGENTS.md` 或 `$HOME/.codex/AGENTS.md` 已包含本設定包的 managed marker，安裝器會輸出 `WARN  Duplicate managed orchestration instructions ...`；警告不修改全域檔案、不算 drift，也不改變 `-Check` exit code；建議每個 repository 只在 User 或 Project 其中一層保存完整規則

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

planner 新產生的 fenced JSON contract 固定使用 v1.1；`verify_cmds` 的每個項目包含 `command`、`cwd`、`purpose`、`timeout_seconds`、`expected_writes`。`cwd` 與 write globs 必須是 repository-relative，不可使用絕對路徑或 `..` 跳脫。validator 仍接受既有 v1.0 字串命令，但 contract 只作為 declarative input，parent 審查後才會執行

contract 使用 `.agents/skills/orchestrate/references/orchestration-plan.schema.json`，可在 materialize 成 JSON 檔後驗證：

```powershell
pwsh ./.agents/skills/orchestrate/scripts/Test-OrchestrationPlan.ps1 -PlanFile ./plan.json
```

macOS 與 Linux：

```bash
bash ./.agents/skills/orchestrate/scripts/Test-OrchestrationPlan.sh --plan-file ./plan.json
```

執行完整套件測試：

```powershell
pwsh -NoProfile -File ./tests/Test-Package.ps1
```

在 macOS 與 Linux，可執行 Bash installer 與 contract 測試：

```bash
bash ./tests/Test-Installer.sh
bash ./tests/Test-Contract.sh
bash ./tests/Test-LaneScenarios.sh
bash ./tests/Test-SourceBoundary.sh
```

### Lane scenario eval

版本化案例矩陣位於 `.agents/skills/orchestrate/references/lane-scenarios.v1.json`，涵蓋已知 DTO、陌生登入流程、CRUD、CI log、獨立驗證、EF Core migration、authentication policy、多文件機械修改與完整交付單元。日常 deterministic test 只驗證格式、角色集合與 lane invariants，不呼叫模型

lane scenario matrix 使用 v1.1，透過 `delegated_agents` 的 role/count 與 `max_role_counts` 驗證實際 agent instance 數量、高風險單 writer、plan-light 單 agent 與重複角色限制

需要觀察實際分類行為時，可選配執行 live runner；它會在暫存 Git repository 載入 `src/AGENTS.md`，以 `codex exec --sandbox read-only --output-schema` 逐案判斷。預設沿用目前 Codex 模型，也可用 `-Model` 或 `--model` 指定模型。此測試需要 Codex CLI、有效登入及網路，不屬於日常 package tests

```powershell
pwsh -NoProfile -File ./src/.agents/skills/orchestrate/scripts/Invoke-LaneScenariosLive.ps1
```

```bash
bash ./src/.agents/skills/orchestrate/scripts/Invoke-LaneScenariosLive.sh
```

### 獨立驗收

```text
使用 $verify 檢查目前所有未提交變更
```

驗收失敗時只回報需要修正的項目，不會直接修改檔案

獨立驗收前後可使用 boundary guard。snapshot 記錄 tracked 與 non-ignored untracked 檔案，`-AllowedWrite`／`--allow-write` 只接受 parent 已審查的 repository-relative artifact globs；任何其他變更都會使驗證失效

```powershell
pwsh ./.agents/skills/verify/scripts/Test-SourceBoundary.ps1 -Mode Capture -SnapshotFile ./.git/verifier-boundary.json
pwsh ./.agents/skills/verify/scripts/Test-SourceBoundary.ps1 -Mode Verify -SnapshotFile ./.git/verifier-boundary.json -AllowedWrite '**/bin/**','**/obj/**','**/TestResults/**'
```

```bash
bash ./.agents/skills/verify/scripts/Test-SourceBoundary.sh --capture --snapshot-file ./.git/verifier-boundary.json
bash ./.agents/skills/verify/scripts/Test-SourceBoundary.sh --verify --snapshot-file ./.git/verifier-boundary.json --allow-write '**/bin/**' --allow-write '**/obj/**' --allow-write '**/TestResults/**'
```

Codex CLI 與 Copilot CLI 都可以使用 `/agent` 查看或切換 custom agent

## 權限設計

- planner 與 explorer 使用唯讀 sandbox
- implementer 使用 `workspace-write`
- verifier 在 Codex 使用 `workspace-write`，讓建置與測試可以產生正常 artifacts，但其指令禁止編輯原始碼
- Copilot planner、explorer、verifier 不提供 `edit` 工具
- 子代理仍受父工作階段的核准與 sandbox 規則約束

## 模型可用性與容量

安裝器只將完整模型 ID `gpt-5.6-luna` 設為 explorer 與 implementer 的初始預設，不將 GPT-5.6、Spark 或其他具名模型作為全域 fallback。模型是否可用、容量是否足夠，皆由目前工作階段與服務端決定，沒有可在派發前使用的服務端容量預查

容量錯誤的處理方式僅限於工作流程中的兩次原任務重派。若仍無法建立子代理，會保留原始錯誤並回報未完成項目，不會靜默改派其他模型

## 設計依據

- [Codex Subagents](https://developers.openai.com/codex/multi-agent)
- [Codex Build skills](https://developers.openai.com/codex/skills)
- [GPT-5.6 預覽說明](https://help.openai.com/en/articles/20001325-a-preview-of-gpt-5-6-sol-terra-and-luna)
- [GitHub Copilot custom agents 設定](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [GitHub Copilot 支援模型](https://docs.github.com/en/copilot/reference/ai-models/supported-models)
