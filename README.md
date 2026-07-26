# audio-transcribe

以 **Gemini 原生多模態音訊理解**把音檔完整轉錄為逐字稿（含講者與 `[MM:SS]` 時間戳）的 Claude Code / Antigravity CLI Skill。不呼叫 whisper／ffmpeg 等外部 STT 工具，直接把音檔讀進模型聽寫。

## 運作方式

單一進入點 `scripts/transcribe.sh` 會自動偵測執行環境：

- **不在 agy／gemini 上**（Claude Code、Codex、Copilot…）：委派給 `agy -p` 非互動指令，由 Gemini 原生音訊理解轉錄。
- **已在 agy／gemini 上**：不遞迴呼叫 agy，改交由當前代理直接用原生音訊理解轉錄。

偵測依據為 `ANTIGRAVITY_CONVERSATION_ID` 環境變數（agy 執行 `run_command` 時的子行程會帶此變數）。

## 安裝

```bash
git clone <repo-url> ~/.claude/skills/audio-transcribe
```

## 使用

```bash
sh ~/.claude/skills/audio-transcribe/scripts/transcribe.sh <音檔絕對路徑> [模型]
```

- 模型預設 `gemini-3.6-flash-high`，可用第二參數或環境變數 `AGY_MODEL` 覆寫。
- 路徑須為絕對路徑。

在 Claude Code 中，說「幫我把這個音檔轉逐字稿」即可觸發此 Skill。

## 依賴

- delegate 分支需已安裝並登入 [Antigravity CLI](https://antigravity.google)（`agy`；`gemini` 多為其 alias）。
- native 分支需執行代理本身具備原生音訊理解。

## 結束碼

| 碼 | 意義 |
|---|---|
| 0 | delegate 成功，stdout 為逐字稿 |
| 2 | 參數／檔案錯誤 |
| 3 | 已在 agy 上，交由代理原生轉錄 |
| 4 | 找不到 agy |
| 124 | agy 逾時 |

## 授權

MIT
