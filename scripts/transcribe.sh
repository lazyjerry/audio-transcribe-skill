#!/bin/sh
# transcribe.sh
# 功能：音檔逐字轉錄的固定流程單一進入點。自動偵測執行環境：
#         - 不在 agy／gemini 上（如 Claude Code、Codex、Copilot）：呼叫 `agy -p` 非互動指令，
#           由 Gemini 原生多模態音訊理解轉錄，結果印到 stdout。
#         - 已在 agy／gemini 上（原生具備音訊理解）：不遞迴呼叫 agy，改印出「請直接原生轉錄」
#           指示與 canonical prompt，交由當前代理直接轉錄。
# 用法：sh transcribe.sh <音檔絕對路徑> [模型]
# 參數：
#   音檔絕對路徑  必填，須為存在且可讀的絕對路徑。
#   模型          選填，傳給 agy 的 --model；預設 gemini-3.6-flash-high（或環境變數 AGY_MODEL）。
# 偵測依據：ANTIGRAVITY_CONVERSATION_ID 非空 → 判定「已在 agy／gemini 執行」（實測 agy run_command
#           子行程會帶此變數）。
# 產出：delegate 分支印逐字稿；native 分支印指示 + prompt。
# 環境變數：AGY_MODEL 覆寫預設模型。
# 結束碼：0 成功（delegate 已完成轉錄）；2 參數／檔案錯誤；3 已在 agy 上，需由代理原生轉錄；
#         4 找不到 agy；124 agy 逾時。
set -eu

MODEL_DEFAULT="${AGY_MODEL:-gemini-3.6-flash-high}"

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
	echo "用法：sh transcribe.sh <音檔絕對路徑> [模型]" >&2
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

AUDIO_DIR=$(dirname "$AUDIO")

# canonical prompt：以 printf 帶入路徑（%s 為獨立參數），避免 bash 3.2 變數展開緊接全形字元遺失位元組
build_prompt() {
	printf '%s%s%s' \
		'請直接使用你自己的多模態原生音訊理解能力，完整轉錄以下音檔為逐字稿。不要嘗試呼叫 whisper、ffmpeg 分析或任何外部語音轉文字工具，直接把音檔本身讀進來聽並轉寫。音檔路徑：' \
		"$AUDIO" \
		'。請完整逐字轉錄，不要摘要、不要省略，並在每段開頭標註講者與時間戳 [MM:SS]。'
}

# --- native 分支：已在 agy／gemini 上，交還給代理原生轉錄，不遞迴 ---
if [ -n "${ANTIGRAVITY_CONVERSATION_ID:-}" ]; then
	{
		echo "[native] 偵測到正在 agy／gemini 上執行（ANTIGRAVITY_CONVERSATION_ID 存在）。"
		echo "[native] 不呼叫 agy -p，請直接用你自己的原生音訊理解能力，依下列 prompt 完整轉錄："
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

set +e
agy -p "$PROMPT" \
	--model "$MODEL" \
	--add-dir "$AUDIO_DIR" \
	--dangerously-skip-permissions
STATUS=$?
set -e

exit "$STATUS"
