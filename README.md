# audio-transcribe

以 **Gemini 原生多模態音訊理解**把音檔完整轉錄為逐字稿（含講者與 `[MM:SS]` 時間戳）的 Claude Code / Antigravity CLI Skill。不呼叫 whisper／ffmpeg 等外部 STT 工具，直接把音檔讀進模型聽寫。

## 運作方式

單一進入點 `scripts/transcribe.sh` 會自動偵測執行環境：

- **不在 agy／gemini 上**（Claude Code、Codex、Copilot…）：委派給 `agy -p` 非互動指令，由 Gemini 原生音訊理解轉錄，並要求 agy **自行把逐字稿寫入輸出檔、回覆只給路徑一行**（逐字稿內容不經 agy 回覆與 stdout，省 token）。腳本會驗證輸出檔確實由本次執行產生且非空。
- **已在 agy／gemini 上**：不遞迴呼叫 agy，改交由當前代理直接用原生音訊理解轉錄。

偵測依據為 `ANTIGRAVITY_CONVERSATION_ID` 環境變數（agy 執行 `run_command` 時的子行程會帶此變數）。

## 安裝

```bash
git clone <repo-url> ~/.claude/skills/audio-transcribe
```

## 使用

```bash
sh ~/.claude/skills/audio-transcribe/scripts/transcribe.sh <音檔絕對路徑> [模型] [輸出檔路徑]
```

- 模型預設 `gemini-3.6-flash-high`，可用第二參數或環境變數 `AGY_MODEL` 覆寫。
- 輸出檔預設 `<音檔同目錄>/<音檔主檔名>.transcript.md`，可用第三參數或環境變數 `TRANSCRIPT_OUT` 覆寫。
- 音檔路徑須為絕對路徑。
- **逐字稿寫入輸出檔，stdout 只回傳該檔絕對路徑**，不印全部內容。

在 Claude Code 中，說「幫我把這個音檔轉逐字稿」即可觸發此 Skill。

### 轉 SRT 字幕（選用）

```bash
sh ~/.claude/skills/audio-transcribe/scripts/transcript-to-srt.sh <逐字稿絕對路徑> [輸出 srt 路徑] [媒體總長秒數]
```

- 輸出預設 `<逐字稿同目錄>/<主檔名去掉 .transcript>.srt`，stdout 只印該檔絕對路徑。
- 每句結束時間 = min(下一句起始, 起始 + `MAX_CUE`)，`MAX_CUE` 預設 15 秒，避免長靜音段變成超長字幕。
- 第三參數給媒體總長秒數，可讓最後一句結束在實際片尾。
- 單一講者自動移除講者前綴，多講者保留。
- 結束碼：0 成功；2 參數／檔案錯誤；3 找不到可解析的時間戳行。

## 依賴

- delegate 分支需已安裝並登入 [Antigravity CLI](https://antigravity.google)（`agy`；`gemini` 多為其 alias）。
- native 分支需執行代理本身具備原生音訊理解。

## 結束碼

| 碼 | 意義 |
|---|---|
| 0 | delegate 成功，逐字稿已由 agy 寫入輸出檔，stdout 為該檔絕對路徑 |
| 2 | 參數／檔案錯誤 |
| 3 | 已在 agy 上，交由代理原生轉錄並寫檔、只回傳路徑 |
| 4 | 找不到 agy |
| 5 | agy 結束但未寫出逐字稿（或內容為空）；保留 `<輸出檔>.agy.<pid>.log` 供查，舊逐字稿會還原 |
| 其他 | agy 的結束碼（如 124 逾時）；此時保留舊輸出檔與 agy 日誌 |

## 授權

MIT
