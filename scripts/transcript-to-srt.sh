#!/bin/sh
# transcript-to-srt.sh
# 功能：把 audio-transcribe 產出的逐字稿（每行 `[MM:SS] 講者：內容` 或 `[HH:MM:SS] ...`）轉為 SRT 字幕。
# 用法：sh transcript-to-srt.sh <逐字稿絕對路徑> [輸出 srt 路徑] [媒體總長秒數]
# 參數：
#   逐字稿絕對路徑  必填，須存在且可讀。
#   輸出 srt 路徑   選填，預設 <逐字稿同目錄>/<主檔名去掉 .transcript>.srt。
#   媒體總長秒數    選填，決定最後一句的結束時間；未給則用「最後一句起始 + MAX_CUE」。
# 規則：
#   - 每句結束時間 = min(下一句起始, 起始 + MAX_CUE)，避免長靜音段產生超長字幕。
#   - 逐字稿只有單一講者時移除講者前綴；多講者時保留。
# 環境變數：MAX_CUE 單句最長秒數，預設 15。
# 結束碼：0 成功；2 參數／檔案錯誤；3 逐字稿中找不到任何可解析的時間戳行。
set -eu

MAX_CUE="${MAX_CUE:-15}"

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
	echo "用法：sh transcript-to-srt.sh <逐字稿絕對路徑> [輸出 srt 路徑] [媒體總長秒數]" >&2
	exit 2
fi

SRC="$1"
case "$SRC" in
	/*) : ;;
	*) printf '錯誤：逐字稿路徑須為絕對路徑（收到：%s）\n' "$SRC" >&2; exit 2 ;;
esac
if [ ! -f "$SRC" ] || [ ! -r "$SRC" ]; then
	printf '錯誤：逐字稿不存在或不可讀：%s\n' "$SRC" >&2
	exit 2
fi

SRC_DIR=$(cd "$(dirname "$SRC")" && pwd)
SRC_BASE=$(basename "$SRC")
STEM=${SRC_BASE%.*}
STEM=${STEM%.transcript}

OUT="${2:-}"
if [ -z "$OUT" ]; then
	OUT="$SRC_DIR/$STEM.srt"
fi
case "$OUT" in
	/*) : ;;
	*) OUT="$SRC_DIR/$OUT" ;;
esac
OUT_DIR=$(dirname "$OUT")
if [ ! -d "$OUT_DIR" ]; then
	printf '錯誤：輸出目錄不存在：%s\n' "$OUT_DIR" >&2
	exit 2
fi

TOTAL="${3:-0}"

TMP_OUT="$OUT.partial.$$"
trap 'rm -f "$TMP_OUT"' EXIT

awk -v max_cue="$MAX_CUE" -v total="$TOTAL" '
function to_sec(ts,   p, n) {
	n = split(ts, p, ":")
	if (n == 3) return p[1] * 3600 + p[2] * 60 + p[3]
	return p[1] * 60 + p[2]
}
function fmt(s,   h, m, sec, ms) {
	if (s < 0) s = 0
	ms = int((s - int(s)) * 1000 + 0.5)
	s = int(s)
	h = int(s / 3600); m = int((s % 3600) / 60); sec = s % 60
	return sprintf("%02d:%02d:%02d,%03d", h, m, sec, ms)
}
{
	line = $0
	if (match(line, /^\[[0-9]+:[0-9]+(:[0-9]+)?\][ \t]*/) != 1) next
	stamp = substr(line, 2, RLENGTH - 3)
	gsub(/[\] \t]+$/, "", stamp)
	body = substr(line, RLENGTH + 1)
	# 拆出講者前綴（全形或半形冒號），僅在冒號前不含空白時視為講者
	speaker = ""
	if (match(body, /^[^：:]{1,20}(：|: )/)) {
		cand = substr(body, 1, RLENGTH)
		rest = substr(body, RLENGTH + 1)
		sub(/(：|: )$/, "", cand)
		if (cand !~ /[ \t]/) {
			speaker = cand
			body = rest
		}
	}
	n++
	start[n] = to_sec(stamp)
	text[n] = body
	spk[n] = speaker
	if (speaker != "" && !(speaker in seen)) { seen[speaker] = 1; nspk++ }
}
END {
	if (n == 0) exit 3
	for (i = 1; i <= n; i++) {
		if (i < n) end = start[i+1]
		else if (total > 0) end = total
		else end = start[i] + max_cue
		if (end > start[i] + max_cue) end = start[i] + max_cue
		if (end <= start[i]) end = start[i] + 1
		printf "%d\n%s --> %s\n", i, fmt(start[i]), fmt(end)
		if (nspk > 1 && spk[i] != "") printf "%s：", spk[i]
		printf "%s\n\n", text[i]
	}
}
' "$SRC" > "$TMP_OUT"

mv "$TMP_OUT" "$OUT"
trap - EXIT
printf '%s\n' "$OUT"
