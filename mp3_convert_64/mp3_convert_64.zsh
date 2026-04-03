#!/usr/bin/env zsh

DIR="/Users/vadimkasse/Downloads/спик/mp3"
cd "$DIR" || { echo "Ошибка: Не удалось зайти в папку $DIR"; exit 1; }

FFMPEG_PATH=$(which ffmpeg)

# --- NEW: cover file (лежит в этой же папке) ---
COVER_FILE="Спикерские.jpg"
# ------------------------------------------------

# Включаем NULL_GLOB, чтобы не ругалось, если файлов нет
setopt NULL_GLOB

# Создаем папки для сортировки
mkdir -p mp3_original
mkdir -p mp3_converted

dur(){ ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 -- "$1" 2>/dev/null; }
cols(){ tput cols 2>/dev/null || echo 80; }

line(){ 
    local p="$1" name="$2" w=40 c nmax nshow f i s pstr
    c=$(cols)
    pstr=$(printf '%6.2f%%' "$p")
    nmax=$(( c - (w + 20) )) 
    (( nmax < 10 )) && nmax=10
    name="${name:t}"
    nshow="${name[1,$nmax]}"
    (( ${#name} > nmax )) && nshow="${nshow[1,$((nmax-1))]}…"
    
    f=$(( (p*w+50)/100 ))
    s="|"
    for ((i=0;i<w;i++)); do 
        if (( i < f )); then s+="█"; else s+="░"; fi
    done
    s+="|"
    printf "\r\033[2K%s %s | %s" "$s" "$pstr" "$nshow"
}

# Берем только файлы в текущей директории
typeset -a files; files=( *.mp3 )
(( ${#files} == 0 )) && { echo "В папке нет mp3 файлов для обработки."; exit 0; }

echo "Расчет длительности..."
total=0
for f in "${files[@]}"; do 
    d=$(dur "$f")
    [[ -z "$d" ]] && d=0
    total=$(awk -v a="$total" -v b="$d" 'BEGIN{printf "%.6f",a+b}')
done

done_sec=0
processed_count=0

for f in "${files[@]}"; do
    fname="${f:t}"
    # Сохраняем сразу в целевую папку под тем же именем
    out="mp3_converted/${fname}"

    [[ "$fname" =~ "«([^»]+)»" ]] && m_title=$(echo "$match[1]" | xargs) || m_title="${fname%.*}"
    [[ "$fname" =~ "\(([^)]+)\)" ]] && m_artist=$(echo "$match[1]" | xargs) || m_artist="Speaker"
    m_album=$(echo "${fname%%«*}" | xargs)
    [[ -z "$m_album" || "$m_album" == "$fname" ]] && m_album="${fname%% *}"

    dfile=$(dur "$f")
    tmp_log=$(mktemp)
    
    # Конвертация: MP3, 64k, Mono
    $FFMPEG_PATH -y -hide_banner -loglevel error -i "$f" \
        -codec:a libmp3lame -b:a 64k -ac 1 \
        -af "loudnorm=I=-16:TP=-1.5:LRA=11" \
        -metadata title="$m_title" \
        -metadata artist="$m_artist" \
        -metadata album="$m_album" \
        -progress "$tmp_log" "$out" &
    
    pid=$!
    while kill -0 $pid 2>/dev/null; do
        if [[ -f "$tmp_log" ]]; then
            line_in=$(tail -n 15 "$tmp_log" | grep "out_time_ms=" | tail -n 1)
            if [[ -n "$line_in" ]]; then
                ms="${line_in#out_time_ms=}"
                pct=$(awk -v done="$done_sec" -v ms="$ms" -v total="$total" 'BEGIN{cur=ms/1000000.0; printf "%.2f", ((done+cur)/total)*100}')
                line "$pct" "$f"
            fi
        fi
        sleep 0.5
    done
    wait $pid
    rm -f "$tmp_log"

    if [[ -f "$out" && -s "$out" ]]; then
        done_sec=$(awk -v a="$done_sec" -v b="$dfile" 'BEGIN{printf "%.6f",a+b}')

        # --- NEW: удалить старую обложку (если есть) + записать Спикерские.jpg ---
        if [[ -f "$COVER_FILE" && -s "$COVER_FILE" ]]; then
            clean_tmp="mp3_converted/.clean_${fname}"
            cover_tmp="mp3_converted/.cover_${fname}"

            # 1) оставить только аудио (убрать любые embedded картинки)
            $FFMPEG_PATH -y -hide_banner -loglevel error -i "$out" \
                -map 0:a -c copy "$clean_tmp"

            # 2) добавить новую обложку (считаем как MJPEG и отмечаем attached_pic)
            $FFMPEG_PATH -y -hide_banner -loglevel error -i "$clean_tmp" -i "$COVER_FILE" \
                -map 0:a -map 1:v \
                -map_metadata 0 \
                -c:a copy -c:v mjpeg \
                -write_id3v2 1 -id3v2_version 3 \
                -metadata:s:v title="Album cover" \
                -metadata:s:v comment="Cover (front)" \
                -disposition:v attached_pic \
                "$cover_tmp"

            if [[ -f "$cover_tmp" && -s "$cover_tmp" ]]; then
                mv -f -- "$cover_tmp" "$out"
            else
                printf "\n⚠️ Не удалось записать обложку в: %s\n" "$fname"
            fi

            rm -f -- "$clean_tmp" "$cover_tmp"
        else
            printf "\n⚠️ Обложка не найдена или пустая: %s (пропускаю)\n" "$COVER_FILE"
        fi
        # --- END NEW ---

        # Переносим оригинал в папку mp3_original с пометкой old_
        mv -- "$f" "mp3_original/old_${f}"
        
        (( processed_count++ ))
    else
        printf "\n❌ Ошибка при обработке: %s\n" "$fname"
    fi
done

printf "\r\033[2K|████████████████████████████████████████| 100.00%% | Done!\n"
echo "--------------------------------------"
echo "Готово! Файлы распределены по папкам:"
echo "📁 mp3_original  <- Исходники (old_...)"
echo "📁 mp3_converted <- Результаты (64k Mono)"
echo "Всего обработано: $processed_count"