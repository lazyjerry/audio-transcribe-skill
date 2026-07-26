#!/bin/sh
# transcribe.sh
# 功能：音檔逐字轉錄的固定流程單一進入點。自動偵測執行環境：
#         - 不在 agy／gemini 上（如 Claude Code、Codex、Copilot）：呼叫 `agy -p` 非互動指令，
#           由 Gemini 原生多模態音訊理解轉錄，逐字稿寫入輸出檔，stdout 只印該檔絕對路徑。
#         - 已在 agy／gemini 上（原生具備音訊理解）：不遞迴呼叫 agy，改印出「請直接原生轉錄並寫檔」
#           指示、canonical prompt 與目標輸出檔路徑，交由當前代理轉錄後寫檔、只回傳路徑。
# 用法：sh transcribe.sh <音檔絕對路徑> [模型] [輸出檔路徑]
# 參數：
#   音檔絕對路徑  必填，須為存在且可讀的絕對路徑。
#   模型          選填，傳給 agy 的 --model；預設 gemini-3.6-flash-high（或環境變數 AGY_MODEL）。
#   輸出檔路徑    選填，逐字稿寫入位置；預設 <音檔同目錄>/<音檔主檔名>.transcript.md
#                 （或環境變數 TRANSCRIPT_OUT）。相對路徑會相對音檔目錄解析。
# 偵測依據：ANTIGRAVITY_CONVERSATION_ID 非空 → 判定「已在 agy／gemini 執行」（實測 agy run_command
#           子行程會帶此變數）。
# 產出：delegate 分支寫輸出檔並在 stdout 印其絕對路徑；native 分支於 stderr 印指示 + prompt + 目標路徑。
# 環境變數：AGY_MODEL 覆寫預設模型；TRANSCRIPT_OUT 覆寫預設輸出檔。
# 結束碼：0 成功（delegate 已寫檔）；2 參數／檔案錯誤；3 已在 agy 上，需由代理原生轉錄並寫檔；
#         4 找不到 agy；其他為 agy 的結束碼（如 124 逾時；此時不寫輸出檔）。
set -eu

MODEL_DEFAULT="${AGY_MODEL:-gemini-3.6-flash-high}"

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
	echo "用法：sh transcribe.sh <音檔絕對路徑> [模型] [輸出檔路徑]" >&2
	exit 2
fi

AUDIO="$1"
MODEL="${2:-$MODEL_DEFAULT}"

case "$AUDIO" in
	/*) : ;;
	*) printf '錯誤：音檔路徑須為絕對路徑（收到：%s）\n' "$AUDIO" >&2; exit 2 ;;
esac

if [ ! -f "$AUDIO" ] || [ ! -r "$AUDIO" ]; then
	echo "錯誤：音檔不存在或不可讀：$AUDIO" >&2
	exit 2
fi

AUDIO_DIR=$(cd "$(dirname "$AUDIO")" && pwd)
AUDIO_BASE=$(basename "$AUDIO")
AUDIO_STEM=${AUDIO_BASE%.*}

# 解析輸出檔路徑：參數 3 > TRANSCRIPT_OUT > 預設；相對路徑相對音檔目錄
OUT="${3:-${TRANSCRIPT_OUT:-}}"
if [ -z "$OUT" ]; then
	OUT="$AUDIO_DIR/$AUDIO_STEM.transcript.md"
fi
case "$OUT" in
	/*) : ;;
	*) OUT="$AUDIO_DIR/$OUT" ;;
esac
OUT_DIR=$(dirname "$OUT")
if [ ! -d "$OUT_DIR" ]; then
	printf '錯誤：輸出目錄不存在：%s\n' "$OUT_DIR" >&2
	exit 2
fi

# canonical prompt：以 printf 帶入路徑（%s 為獨立參數），避免 bash 3.2 變數展開緊接全形字元遺失位元組
build_prompt() {
	printf '%s%s%s' \
		'請直接使用你自己的多模態原生音訊理解能力，完整轉錄以下音檔為逐字稿。不要嘗試呼叫 whisper、ffmpeg 分析或任何外部語音轉文字工具，直接把音檔本身讀進來聽並轉寫。音檔路徑：' \
		"$AUDIO" \
		'。請完整逐字轉錄，不要摘要、不要省略，並在每段開頭標註講者與時間戳 [MM:SS]。'
}

# --- native 分支：已在 agy／gemini 上，交還給代理原生轉錄並寫檔，不遞迴 ---
if [ -n "${ANTIGRAVITY_CONVERSATION_ID:-}" ]; then
	{
		echo "[native] 偵測到正在 agy／gemini 上執行（ANTIGRAVITY_CONVERSATION_ID 存在）。"
		echo "[native] 不呼叫 agy -p，請直接用你自己的原生音訊理解能力，依下列 prompt 完整轉錄，"
		printf '[native] 將逐字稿寫入檔案：%s，完成後只回傳此路徑，不要回傳全部內容。\n' "$OUT"
		echo "---8<--- PROMPT ---8<---"
		build_prompt
		echo
		echo "---8<--- END ---8<---"
	} >&2
	exit 3
fi

# --- delegate 分支：不在 agy 上，呼叫 agy -p ---
if ! command -v agy >/dev/null 2>&1; then
	echo "錯誤：找不到 agy 指令，無法委派轉錄。請安裝 Antigravity CLI 或在支援原生音訊的代理上執行。" >&2
	exit 4
fi

PROMPT=$(build_prompt)
TMP_OUT="$OUT.partial.$$"

set +e
agy -p "$PROMPT" \
	--model "$MODEL" \
	--add-dir "$AUDIO_DIR" \
	--dangerously-skip-permissions \
	> "$TMP_OUT"
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
	rm -f "$TMP_OUT"
	printf 'agy 轉錄失敗（結束碼 %s），未寫輸出檔。\n' "$STATUS" >&2
	exit "$STATUS"
fi

mv "$TMP_OUT" "$OUT"
printf '%s\n' "$OUT"
