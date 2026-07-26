---
name: audio-transcribe
description: 用 Gemini 原生多模態音訊理解，把音檔完整轉錄為逐字稿（含講者與 [MM:SS] 時間戳），不摘要不省略。若當前代理本身沒有原生音訊理解（如 Claude Code、Codex、Copilot），會自動委派給 `agy -p` 非互動指令；若已在 agy／gemini 上執行則直接原生轉錄。觸發詞：轉錄、逐字稿、轉逐字、聽打、音檔轉文字、transcribe、audio transcript、把錄音轉成文字。
version: 1.0.0
author: LazyJerry
---

# 音檔逐字轉錄（audio-transcribe）

把音檔完整轉錄為逐字稿。核心手法是**直接用模型的原生多模態音訊理解**讀音檔聽寫，而非呼叫 whisper／ffmpeg 等外部 STT 工具。

`<SKILL_DIR>` 為此 skill 安裝目錄（`~/.claude/skills/audio-transcribe`）。

## 設計原則

固定流程由 `scripts/transcribe.sh` 自動完成，代理只負責取得音檔絕對路徑、呼叫腳本、轉述結果。腳本會**自動偵測執行環境**並二選一：

| 執行環境 | 偵測依據 | 行為 |
|---|---|---|
| **不在** agy／gemini（Claude Code、Codex、Copilot…） | `ANTIGRAVITY_CONVERSATION_ID` 不存在 | 腳本呼叫 `agy -p` 非互動指令，由 Gemini 原生音訊理解轉錄，逐字稿印到 stdout（exit 0） |
| **已在** agy／gemini（原生具備音訊理解） | `ANTIGRAVITY_CONVERSATION_ID` 存在（實測 agy run_command 子行程會帶此變數） | 腳本**不遞迴**呼叫 agy，改印出 canonical prompt 與指示（exit 3），交由當前代理直接原生轉錄 |

## 執行流程

### 1. 取得音檔絕對路徑

向使用者確認要轉錄的音檔**絕對路徑**（腳本會拒絕相對路徑）。

### 2. 執行單一進入點

```bash
sh <SKILL_DIR>/scripts/transcribe.sh <音檔絕對路徑> [模型]
```

- 第二參數為選填模型，預設 `gemini-3.6-flash-high`（亦可用環境變數 `AGY_MODEL` 覆寫）。
- `--add-dir` 由腳本自音檔路徑推得，`--dangerously-skip-permissions` 已內建。

### 3. 依結束碼處理

- **exit 0**：delegate 已完成，stdout 即逐字稿。原樣轉述給使用者，勿再摘要或改寫。
- **exit 3**：你正在 agy／gemini 上執行。**改用你自己的原生音訊理解能力**，依 stderr 印出的 canonical prompt 直接把該音檔讀進來聽並完整逐字轉錄，於每段開頭標註講者與 `[MM:SS]`。不要呼叫 whisper／ffmpeg 或任何外部 STT。
- **exit 2**：參數或檔案錯誤（路徑非絕對、檔案不存在／不可讀）。修正後重試。
- **exit 4**：找不到 `agy`。告知使用者需安裝 Antigravity CLI，或改在支援原生音訊的代理上執行。
- **exit 124**：agy 逾時。

## 輸出格式

逐字稿每段開頭標註講者與時間戳，例如：

```
[00:00] Speaker 1: ……
[00:07] Speaker 1: ……
```

完整逐字，不摘要、不省略。
