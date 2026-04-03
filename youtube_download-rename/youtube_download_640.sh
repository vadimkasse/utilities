#!/usr/bin/env bash
# youtube_download_640.sh — исправленный загрузчик YouTube → MP4 ≤ 640p
# Требуется: yt-dlp, ffmpeg  (brew install yt-dlp ffmpeg)

set -euo pipefail
IFS=$'\n\t'

RED="\033[31m"; GRN="\033[32m"; YLW="\033[33m"; BLD="\033[1m"; RST="\033[0m"

# Используем brew-версию yt-dlp явно
if [[ -f "/opt/homebrew/bin/yt-dlp" ]]; then
  YTDLP="/opt/homebrew/bin/yt-dlp"
elif [[ -f "/usr/local/bin/yt-dlp" ]]; then
  YTDLP="/usr/local/bin/yt-dlp"
else
  YTDLP="yt-dlp"
fi

command -v ffmpeg >/dev/null 2>&1 || { echo -e "${RED}Нужно установить: ffmpeg${RST}"; exit 1; }

echo -e "${YLW}Используется: $($YTDLP --version) из $YTDLP${RST}"

# ----- опционально: --cookies-file путь / --cookies-browser chrome|safari / --max N -----
COOKIE_FILE="$HOME/youtube_cookies.txt"
USE_BROWSER=""
MAX_DOWNLOADS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cookies-file)
      [[ -n "${2:-}" ]] || { echo "Использование: --cookies-file /path/to/cookies.txt"; exit 2; }
      COOKIE_FILE="$2"; shift 2;;
    --cookies-browser)
      [[ -n "${2:-}" && "$2" =~ ^(chrome|safari|firefox)$ ]] || { echo "Использование: --cookies-browser chrome|safari|firefox"; exit 2; }
      USE_BROWSER="$2"; COOKIE_FILE=""; shift 2;;
    --max)
      [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]] || { echo "Использование: --max 100"; exit 2; }
      MAX_DOWNLOADS="$2"; shift 2;;
    --no-cookies) 
      COOKIE_FILE=""; USE_BROWSER=""; shift;;
    *) echo "Неизвестный флаг: $1"; exit 2;;
  esac
done

echo -e "${BLD}Вставьте ссылку на видео/плейлист/канал YouTube:${RST}"
read -r URL
[[ -z "$URL" ]] && { echo -e "${RED}Пустая ссылка. Выход.${RST}"; exit 1; }

DEFAULT_DIR="$HOME/YouTubeArchive"
echo -e "${BLD}Куда сохранить? (Enter = ${DEFAULT_DIR})${RST}"
read -r DEST
DEST="${DEST:-$DEFAULT_DIR}"
DEST="${DEST%/}"

echo -e "→ Сохраняю в: ${GRN}${DEST}${RST}"
echo -e "→ Анализирую: ${YLW}${URL}${RST}"

# ------------ вспомогалки ------------
sanitize_dir() {
  local s="$1"
  s="${s//\\/-}"; s="${s//\//-}"; s="${s//:/ -}"; s="${s//\*/·}"
  s="${s//\?/}"; s="${s//\"/}"; s="${s//\|/-}"; s="${s//</(}"; s="${s//>/(}"
  s="$(printf "%s" "$s" | tr '\r\n' '  ' | awk '{gsub(/[[:space:]]+/, " "); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print}')"
  printf "%s" "$s"
}

# КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: используем массив вместо строки
COOKIE_OPTS=()
if [[ -n "$COOKIE_FILE" && -f "$COOKIE_FILE" ]]; then
  echo -e "${GRN}✓ Используется файл cookies: $COOKIE_FILE${RST}"
  COOKIE_OPTS=(--cookies "$COOKIE_FILE")
elif [[ -n "$USE_BROWSER" ]]; then
  echo -e "${YLW}⚠ Попытка извлечь cookies из браузера: $USE_BROWSER${RST}"
  echo -e "${YLW}  (Может потребоваться разрешение Keychain)${RST}"
  COOKIE_OPTS=(--cookies-from-browser "$USE_BROWSER")
else
  echo -e "${RED}⚠ ВНИМАНИЕ: Cookies не используются!${RST}"
  echo -e "${YLW}  Рекомендуется экспортировать cookies:${RST}"
  echo -e "  1. Установите: https://chromewebstore.google.com/detail/cclelndahbckbenkjhflpdbgdldlbecc"
  echo -e "  2. Откройте YouTube → Export → сохраните как ~/youtube_cookies.txt"
  echo -e "  3. Запустите скрипт без флагов (автоматически использует файл)${RST}"
  echo ""
  read -p "Продолжить без cookies? (y/N): " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

yt_field_android() {
  $YTDLP --skip-download --print "$1" --playlist-items 1 \
         --extractor-args "youtube:player_client=android" \
         "${COOKIE_OPTS[@]}" "$URL" 2>/dev/null | head -n1 || true
}
yt_field_web() {
  $YTDLP --skip-download --print "$1" --playlist-items 1 \
         --extractor-args "youtube:player_client=web" \
         "${COOKIE_OPTS[@]}" "$URL" 2>/dev/null | head -n1 || true
}

# Название канала/плейлиста
CHANNEL="$(yt_field_android "%(uploader)s")"
[[ -z "$CHANNEL" || "$CHANNEL" == "NA" ]] && CHANNEL="$(yt_field_android "%(channel)s")"
[[ -z "$CHANNEL" || "$CHANNEL" == "NA" ]] && CHANNEL="$(yt_field_web "%(uploader)s")"
[[ -z "$CHANNEL" || "$CHANNEL" == "NA" ]] && CHANNEL="$(yt_field_web "%(channel)s")"

# Фолбэк: handle из URL (любой @handle)
if [[ -z "$CHANNEL" || "$CHANNEL" == "NA" ]]; then
  if [[ "$URL" =~ @([A-Za-z0-9._-]+) ]]; then
    CHANNEL="${BASH_REMATCH[1]}"
  else
    CHANNEL="Unknown Channel"
  fi
fi

PLAYLIST="$(yt_field_android "%(playlist)s")"
[[ -z "$PLAYLIST" || "$PLAYLIST" == "NA" ]] && PLAYLIST="$(yt_field_web "%(playlist)s")"

CHANNEL_SAFE="$(sanitize_dir "$CHANNEL")"
PLAYLIST_SAFE="$(sanitize_dir "$PLAYLIST")"

# Итоговая папка: DEST/Channel  или  DEST/Channel - Playlist
if [[ -n "$PLAYLIST_SAFE" ]]; then
  FINAL_DIR="${DEST}/${CHANNEL_SAFE} - ${PLAYLIST_SAFE}"
else
  FINAL_DIR="${DEST}/${CHANNEL_SAFE}"
fi
mkdir -p "$FINAL_DIR"

# ЕДИНЫЙ файл архива в корне DEST (не в папке канала!)
ARCHIVE_FILE="${DEST}/downloaded.txt"
touch "$ARCHIVE_FILE"

echo -e "→ Папка назначения: ${GRN}${FINAL_DIR}${RST}"
echo -e "→ Файл истории: ${GRN}${ARCHIVE_FILE}${RST}"
[[ -f "$ARCHIVE_FILE" ]] && echo -e "→ Уже скачано: ${YLW}$(wc -l < "$ARCHIVE_FILE" | tr -d ' ')${RST} видео"
[[ -n "$COOKIE_FILE" && -f "$COOKIE_FILE" ]] && echo -e "→ Cookies: ${GRN}файл${RST}"
[[ -n "$USE_BROWSER" ]] && echo -e "→ Cookies: ${YLW}браузер $USE_BROWSER${RST}"
echo -e "→ Режим: $( [[ "$URL" == *"playlist"* || "$URL" == *"list="* ]] && echo "плейлист" || { [[ "$URL" == *"/videos"* || "$URL" == *"@*"* ]] && echo "канал" || echo "одно видео"; } )"
echo -e "→ Начинаю загрузку в MP4 ≤ 640p…"

# Формат ≤640p + сортировка по убыванию
FORMAT_SEL="bestvideo[height<=640]+bestaudio/best[height<=640]/best"
SORT_SEL="res:desc,fps:desc,br:desc,filesize:desc"
PP_ARGS="VideoReencoder:-vf scale='min(640,iw)':-2 -c:v libx264 -preset veryfast -crf 22 -c:a aac -b:a 160k"

# Общие флаги (улучшенные для борьбы с bot detection)
COMMON=(
  -P "$FINAL_DIR"
  -o "%(title)s.%(ext)s"
  -f "$FORMAT_SEL"
  -S "$SORT_SEL"
  --yes-playlist
  --ignore-errors
  --no-continue --no-part
  --concurrent-fragments 2
  --retries 15 --fragment-retries 15
  --sleep-requests 5 --sleep-interval 8 --max-sleep-interval 20
  --throttled-rate 300K
  --download-archive "$ARCHIVE_FILE"
  --recode-video mp4
  --postprocessor-args "$PP_ARGS"
  --extractor-retries 5
  --file-access-retries 5
)

# Добавляем ограничение если указано
[[ -n "$MAX_DOWNLOADS" ]] && COMMON+=(--max-downloads "$MAX_DOWNLOADS")

echo -e "${YLW}⚠ Используются увеличенные задержки для предотвращения блокировки${RST}"

# 1) android-клиент (лучше переживает SABR/«only images»)
$YTDLP "${COMMON[@]}" \
  --extractor-args "youtube:tab=videos,player_client=android" \
  "${COOKIE_OPTS[@]}" \
  "$URL" || {
  # 2) фолбэк — web
  echo -e "${YLW}↻ Повтор через web-клиент…${RST}"
  $YTDLP "${COMMON[@]}" \
    --extractor-args "youtube:tab=videos,player_client=web" \
    "${COOKIE_OPTS[@]}" \
    "$URL"
}

echo -e "${GRN}✔ Готово.${RST}"
echo -e "Файлы: ${BLD}${FINAL_DIR}${RST}"